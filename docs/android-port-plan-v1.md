# SubsCheck 安卓移植方案 v1

> 基于你已确认的方向：**Flutter UI / armv7 / 给别人用（APK 分发）/ 不做 Windows 同步 / 不要 Sub-Store，App 自己导出 clash yaml**

---

## 0. 你的决定带来的连锁反应

| 决定 | 后果 |
|---|---|
| 不要 Sub-Store | 不需要 node 运行时（省 74MB），不需要 Sub-Store bundle（省 3MB），不需要在 32 位 Android 上跑 Node —— 而 Node 官方已停发 armv7 二进制，这条路本来就是死路 |
| 要 clash yaml | 内核在 `sub-store-port` 留空时**只产出 all.yaml（纯 proxies，无 rules）**；这是我实测你 `output/all.yaml` 只有 16 行、而 `mihomo.yaml` 有 220 行的原因。所以 yaml 拼装必须由 App 自己做 |
| 只 armv7 | 内核官方 release 有 `subs-check_Linux_armv7.tar.gz`（60.3MB，v1.6.5），但版本较旧，我们倾向自己交叉编译 |

**结论：原本 F2 方案里 80% 的复杂度（proot 跑 Node）消失了。剩下唯一硬需求是「让 Go 内核在 Android armv7 上跑起来 + 自己拼 clash yaml」。**

---

## 1. 路线调整：F2 → F2'

| | F2（原计划） | **F2'（本方案）** |
|---|---|---|
| 运行时 | proot + Alpine armhf rootfs + 官方 Linux_armv7 内核 | 内核静态二进制直接 exec |
| 需要解决 | exec 权限 + resolv.conf + rootfs 挂载 | exec 位置 + DNS |
| 体积 | ~80MB | ~62MB（单 ABI） |
| targetSdk | 必须降到 28 | 可以保持 35 |
| 运行开销 | proot 用 ptrace 拦截每个 syscall，测速（高并发网络）时开销显著 | 零 |
| 维护成本 | 需要维护 rootfs、proot 二进制、挂载脚本 | 只需要一个二进制 |

**为什么必须用 GOOS=linux 的二进制，不能编译成 GOOS=android：**

Go 官方源码 `src/net/conf.go:183-186` 写得很明确：

```go
// DNS requests don't work on Android, so prefer the cgo resolver.
// Issue #10714.
case "android":
    return true
```

内核是 `CGO_ENABLED=0` 构建（`.goreleaser.yaml` 已确认），没有 cgo resolver 可用，所以 `GOOS=android` 编出来的程序**无法解析域名**。而 `GOOS=linux` 的静态二进制在 Android 上能跑，只是要处理 exec 权限和 DNS 两个问题。

---

## 2. 目标架构

```
┌─────────────────────────────────────────────────────┐
│  Flutter (Dart)                                     │
│  ├── UI        配置页 / 日志页 / 结果页 / 分享页      │
│  ├── EngineService   启动/停止/看护 Go 进程          │
│  ├── KernelApi       HTTP 127.0.0.1:8199 (X-API-Key)│
│  └── ClashBuilder    all.yaml + 模板 → mihomo.yaml  │
└───────────────────┬─────────────────────────────────┘
                    │ HTTP
┌───────────────────▼─────────────────────────────────┐
│  Go 内核 subs-check（fork，GPLv3）                   │
│  ├── 补丁 1：Android DNS 覆盖（必须）                │
│  ├── 补丁 2：-f 传入配置路径（已有 flag，直接用）    │
│  └── 补丁 3：os.Exit 改为返回错误（可选，稳定性）    │
└─────────────────────────────────────────────────────┘
```

### 工程结构

```
app/
├── android/
│   └── app/src/main/
│       ├── jniLibs/armeabi-v7a/libsubscheck.so      ← Go 内核（改名）
│       ├── jniLibs/arm64-v8a/libsubscheck.so         ← 可选
│       └── assets/ca-certificates.pem                ← Go 需要，见 §3.3
├── lib/
│   ├── main.dart
│   ├── engine/engine_service.dart    进程生命周期 + 前台服务
│   ├── engine/kernel_api.dart        /api/status /api/trigger-check ...
│   ├── clash/clash_builder.dart      模板合并
│   ├── clash/templates/acl4ssr.yaml  内置模板（可替换）
│   └── ui/
├── kernel/                            Go 内核 fork（git submodule 或子树）
└── docs/android-port-plan-v1.md
```

---

## 3. 三个必须解决的技术点

### 3.1 exec 权限（Android 10+ 的 W^X 限制）

Android 10（API 29）起，targetSdk ≥ 29 的 App 不能 execve 自己的私有数据目录里的文件。两个解法：

| | A. targetSdk = 28 | B. nativeLibraryDir（推荐先试） |
|---|---|---|
| 做法 | 打包时降 targetSdk，二进制解压到 filesDir 再 exec | 二进制改名 `libsubscheck.so` 放 jniLibs，AGP 会解压到只读的 nativeLibraryDir，该目录不受 W^X 限制 |
| 稳定性 | 极高（Termux 用了很多年） | 需要真机验证 AGP 不会 strip 掉它 |
| Google Play | 不能上架 | 可以上架 |
| 代码差异 | 无 | 无 |

**代码完全一致，只是打包配置不同。建议先做 B，B 不通再退 A。**

### 3.2 DNS（内核必须打补丁）

Android 没有 `/etc/resolv.conf`，Go 的 netgo resolver 会直接失败。补丁放在 `main.go`：

```go
func initAndroidResolver(dnsServers []string) {
    server := "223.5.5.5:53"
    if len(dnsServers) > 0 {
        server = dnsServers[0] + ":53"
    }
    net.DefaultResolver = &net.Resolver{
        PreferGo: true,
        Dial: func(ctx context.Context, network, _ string) (net.Conn, error) {
            d := net.Dialer{Timeout: 5 * time.Second}
            return d.DialContext(ctx, "udp", server)
        },
    }
}
```

新增配置项 `android-dns: ["223.5.5.5", "119.29.29.29"]`，留空则用默认值。
补丁以独立 fork 维护（GPLv3 允许），不污染上游。

### 3.3 CA 证书

Go 无 cgo 时不会读 Android 的系统证书库，会从 `SSL_CERT_FILE` 指向的文件读。上游 `doc/android.md` 的官方做法就是设这个环境变量：

```dart
env: {
  'SSL_CERT_FILE': '${appDir}/ca-certificates.pem',
  'HOME': appDir,
}
```

把 `ca-certificates.crt` 打包进 assets，首次启动复制到 filesDir 即可。

---

## 4. clash yaml 生成（替代 Sub-Store）

**输入**：内核产出的 `output/all.yaml` —— 已经是完整 proxies 数组，节点名已含国家 emoji、媒体标签、速度标签（如 `🇵🇱PL_1|1.6MB/s`）。

**模板**：内置一份 clash 模板，包含 `proxy-groups` / `rule-providers` / `rules` 三段。默认用 Sub-Store 输出的那份结构（我已从你机器上的 `mihomo.yaml` 提取，中文分组 + MetaCubeX 规则集）。

**合并逻辑**（这是关键，比想象中简单）：

```dart
final proxies = loadYaml(allYaml)['proxies'];      // 节点
final tpl     = loadYaml(templateYaml);            // 模板
return {
  'proxies': proxies,
  'proxy-groups': tpl['proxy-groups'], // 分组用 include-all + filter 自动圈节点
  'rule-providers': tpl['rule-providers'],
  'rules': tpl['rules'],
};
```

**为什么不需要自己算节点归属**：mihomo 的 `proxy-groups` 支持 `include-all: true` 加 `filter: "(?i)香港|HK|🇭🇰"`，节点圈选是内核运行时做的，我们只要照抄模板。你机器上的 `mihomo.yaml` 第 164 行就是这个写法，可以直接复用。

**V1 范围**：只做 clash yaml。`base64.txt`（订阅 URI 列表）需要内核补丁暴露 `proxy.Uri()`，放到 V2。

---

## 5. 里程碑

| 阶段 | 内容 | 交付物 | 预估 |
|---|---|---|---|
| **M0** | 环境搭建：Flutter 3.47.9 + JDK 21 + Android SDK + NDK（下载量约 3GB） | 能跑 `flutter doctor` 全绿 | 半天 |
| **M1** | 内核构建：fork + DNS 补丁 + `GOOS=linux GOARCH=arm` 交叉编译 | 能在模拟器/proot 里跑出 all.yaml | 1 天 |
| **M2** | 进程管理：Flutter 启动内核、读 /api/status、前台服务保活 | 打开展示实时进度 | 2 天 |
| **M3** | UI：配置页（33 个配置项）、日志页（stdout 流式）、结果页 | 可日常使用 | 3 天 |
| **M4** | clash 导出 + 分享（文件导出 / 局域网订阅 URL / 二维码） | 完整功能 | 2 天 |
| **M5** | 打包：armv7(+arm64)、签名、真机测试、体积优化 | 可分发 APK | 1 天 |

---

## 6. 风险清单

| 风险 | 影响 | 对策 |
|---|---|---|
| APK 体积 60MB+ | 内核二进制本身 60MB | 无法优化（Go 静态链接 + mihomo 规则集）；armv7 单架构可控制在 ~62MB |
| 后台被系统杀 | 测速跑到一半中断 | 前台服务 + WakeLock + 引导用户加电池白名单 |
| 内核 `os.Exit(0)` | 配置缺失时静默退出，用户看到"启动失败" | 首次启动由 App 预写完整 config.yaml，绝不触发 createDefaultConfig |
| 高并发测速耗电/发热 | 24 并发 × 20MB 下载 | UI 默认并发降到 8-10，给出提示 |
| GPLv3 | 分发 APK 必须开源 | 仓库已放 LICENSE.txt；fork 的补丁要公开，构建脚本一并提交 |
| armv7 设备性能 | 老设备测速慢 | 可选降级：直接给官方 Linux_armv7 release 二进制，不自编 |

---

## 7. 需要你拍板的三件事

1. **exec 方案**：先试 B（nativeLibraryDir，可上架）还是直接用 A（targetSdk=28，最稳）？
2. **ABI 范围**：只 armv7（62MB），还是 armv7 + arm64（约 122MB）？考虑到现在是 2026 年，arm64 设备占绝大多数，只发 armv7 会丢失大部分用户。
3. **首次启动的订阅源**：内置内核默认那 20 个公共订阅源，还是空白让用户自己填？

确认后我从 M0 开始执行。

---

## 8. 落地时必须改的配置（补充，来自源码核对）

这两点如果不处理，内核启动后第一次保存就失败：

| 配置 | 默认行为 | Android 上必须 |
|---|---|---|
| `-f <path>` | 空 → `os.Executable()` 所在目录的 `config/config.yaml` | 指向 `/data/data/<pkg>/files/config/config.yaml` |
| `output-dir` | 空（`save/method/local.go:NewLocalSaver`）→ exe 目录下 `output/` | 指向 `/data/data/<pkg>/files/output` |

原因：用 nativeLibraryDir 方案时，exe 所在目录是 `/data/app/~~xxx/<pkg>-yyy/lib/arm/`，**只读**。不显式指定路径，`SaveToLocal` 必然 EROFS。
顺带 `utils.SetCacheDir(app.configPath)` 也是跟着配置文件走的，所以配置文件放对位置，缓存目录自动正确。

另外：`AndroidManifest.xml` 需要 `android:extractNativeLibs="true"`，否则 `.so` 不会解压到 nativeLibraryDir（minSdk ≥ 23 时默认 false，`.so` 留在 APK 里无法 exec）。

## 9. 与上游的关系（GPLv3 合规）

- 内核 fork 单独一个仓库，只加补丁，保留原 LICENSE 与作者信息
- App 侧同样 GPLv3，仓库里放完整构建脚本
- 分发 APK 时提供源码地址即可

## 10. 不在本期范围

- base64 / v2ray 订阅格式导出（需要内核补丁暴露 `proxy.Uri()`）
- 远程保存（gist / webdav / s3 / r2）
- 通知推送（apprise）
- 与 Windows 版的数据同步
- Google Play 上架
