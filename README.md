# SubsCheck for Android

把 [beck-8/subs-check](https://github.com/beck-8/subs-check) 的 Go 检测内核直接跑在 Android 上的原生 App。
内核做全部测活/测速/媒体检测，App 提供界面、配置管理与订阅导出。

> 内核与 Sub-Store 均为 **GNU GPL v3**，本 App 同样以 GPL v3 发布。

---

## 它是什么

Windows 版 SubsCheck 依赖 proot / Termux 那套才能上安卓。本 App 换了思路：

- 内核用 `GOOS=linux` **静态 ET_EXEC** 交叉编译（不是 PIE、不是 GOOS=android），
  以 `libsubscheck.so` 的名字塞进 APK 的 `jniLibs`，
  靠 `android:extractNativeLibs="true"` 落到 `nativeLibraryDir` 后**直接 exec**。
- 因此 `targetSdk` 被锁在 **28**——Android 10+ 仅允许 targetSdk < 29 的应用执行可写目录里的二进制。
- 不用 Sub-Store、不打包 Node：`sub-store-port` 被 patch 成空字符串，
  clash 完整配置由 App 自己拼（内置 ACL4SSR 模板 + 内核产出的 proxies）。

## 安装

安装包**不在仓库里**，请到 [Releases](https://github.com/tianduoyuguang/SubsCheck--android/releases) 下载：

| 包 | 适用 | SHA-256 |
|---|---|---|
| `SubsCheck-1.2.8-arm64-v8a.apk` | 2018 年之后绝大多数手机 | `225b3a344648907a854cd514f1c554ccd6a6e9206ab08bae69bb6f5de2df0578` |
| `SubsCheck-1.2.8-armeabi-v7a.apk` | 老 32 位设备 | `c299dcb4fc67ef1882dde32395132cffab2ba689a4f2eb8b821463f3b6061ead` |

`minSdkVersion` = 24（Android 7.0），`targetSdkVersion` = 28，`versionName` = 1.2.8。

> **安装时提示「未经验证的开发者 / 无开发者认证」是正常的，直接继续安装即可。**
> 系统从 Android 16 QPR2 起内置了开发者身份校验，会核对包名是否登记过开发者身份。
> 本项目是个人开源发布，没有登记，所以每次装新版本都会提示一次 —— 这不代表安装包损坏或被篡改。
> 校验安装包请比对上面的 SHA-256，或按下面的命令运行 `sha256sum -c SHA256SUMS.txt`。
> 如果不想看到这个提示，可以用 `adb install -r <apk>` 安装（官方保留的开发/测试通道，不受该提示影响）。

> APK 每次发版约 33 MB 且必然变化，提交进 Git 会让历史永久膨胀，
> 因此仓库只保留源码与校验文件 `dist/SHA256SUMS.txt`，二进制一律走 Release。

各版本变更记录见 [docs/android-port-status.md](docs/android-port-status.md)。

校验：

```bash
cd dist
sha256sum -c SHA256SUMS.txt
```

安装时系统会提示「此应用专为旧版 Android 打造」，属正常现象（就是上面说的 targetSdk=28）。

## 使用

1. 首次打开 → 点「启动内核」。首次启动会自动写出 `config.yaml`（在 App 私有目录）。
2. 「概览 → 立即检测一轮」拉取订阅源并开始测活/测速。一轮完整检测通常 10~30 分钟。
3. 「节点」看结果（可按速度排序、点开看协议详情）。
4. 「订阅」页导出：
   - **完整 mihomo 配置**：基础段（port/mode/dns）+ proxies + proxy-groups + rule-providers + rules（内置 ACL4SSR 模板）
   - **仅节点**：只有 proxies
   - **另存为…**：每行右侧的保存图标，直接弹系统「保存到…」对话框，
     由你自己挑文件名和位置（Documents、网盘、U 盘都行），不经过下面的导出目录设置。
   点击行本身只做「保存到当前导出目录」，不会弹分享面板；
   保存成功后的提示条上有个「分享」按钮，需要分享时才点它。
   导出目录由「订阅 → 导出自定义位置」或「设置 → 导出文件 → 导出目录」决定（同一个开关），
   默认 `Android/data/com.subscheck.subscheck/files/exports/`；
   可改成公共 `Download/SubsCheck` 或任意自选目录。
5. 「设置」里可以：
   - 改监听地址与端口（默认 `127.0.0.1:8199`）
   - 直接编辑 `config.yaml`（订阅源、并发、超时、测速阈值等都在这里）
   - 查看 API Key（外部工具调内核 HTTP API 用，头名 `X-API-Key`）
   - 改导出目录、通知权限、忽略电池优化

启动时会自动静默检查一次新版本：发现更新会弹窗询问，可选「立即更新 / 以后再说 / 不再提示此版本」
（「不再提示」只压住当前这一版，出现更新的版本仍会提醒；这个开关在「设置 → 关于」里可以关掉）。

### 内核 HTTP API

内核跑起来后监听 `127.0.0.1:8199`，除订阅导出外都只允许本机访问：

```
GET  /sub/all.yaml                         ← 节点列表（本 App 唯一会产出的订阅文件）
GET  /all.yaml                             ← 同上，兼容老地址
POST /api/trigger-check                    ← 触发一轮检测（需 X-API-Key）
GET  /api/status /api/results /api/logs    ← 状态（需 X-API-Key）
```

> 内核只有在启用 Sub-Store 时才会额外生成 `/mihomo.yaml`、`/base64.txt` 与
> `/export/:target` 的各种格式；本 App 没有启用 Sub-Store，所以这几项不可用。
> 需要完整 mihomo 配置或 Base64 订阅，请用 App 内的导出功能生成文件。

## 从源码构建

本仓库包含 Android App 源码，不包含 Go 检测内核的源码。内核上游位于
[beck-8/subs-check](https://github.com/beck-8/subs-check)；当前 APK 使用的预编译内核已放在
`android/app/src/main/jniLibs/`。

安装 Flutter、Android SDK 和 JDK 后，在仓库根目录执行：

```bash
flutter pub get
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64
```

产物在 `build/app/outputs/flutter-apk/`。

签名使用 `android/keystore/subscheck-release.jks`（口令见 `android/app/build.gradle.kts`）；
**分发给他人前请换成你自己的 keystore**，否则任何人都能用这份私钥给「同一应用」发更新。

调试时可用 `-PtargetAbi=x86_64` 只打 x86_64 包给模拟器（该模拟器必须能原生执行 x86_64；
ARM 内核在 x86 模拟器的 ARM 转译层下会触发 Go runtime 崩溃，属模拟器限制）。

## 已知限制

- **targetSdk=28** 是硬约束。Google Play 对 targetSdk 有最低要求，本 App 不适合上架 Play。
- 部分国产 ROM 的后台限制会杀掉长任务，建议在系统设置里给 App 加白名单（「设置 → 通知权限」页有提示）。
- 默认订阅源里有几条已失效（上游仓库删除），可在 `config.yaml` 的 `sub-urls` 里自行增删。
- 分享导出文件依赖系统分享面板，个别精简 ROM 可能没有可用目标，可直接从文件管理器取文件。

## 目录结构

```
lib/                     Flutter UI
  src/api.dart           内核 HTTP 客户端
  src/app_state.dart     全局状态与 2 秒轮询
  src/exporter.dart      拼接完整 mihomo 配置
  src/export_dir.dart    导出目录选择（私有 / Download / SAF）
  src/native.dart        MethodChannel 桥
  pages/                 概览/节点/订阅/设置/日志
android/app/src/main/kotlin/com/subscheck/subscheck/
  KernelManager.kt       内核进程生命周期、配置 patch、日志缓冲
  KernelService.kt       前台服务（保活）
  ExportStore.kt         导出落盘（MediaStore / SAF / 私有目录）
assets/                  ACL4SSR 模板、config.yaml 模板
android/app/src/main/jniLibs/
                         APK 内置的各 ABI 预编译内核
docs/                    移植方案与进度记录
```

## 许可

GPL v3。内核版权归 [beck-8/subs-check](https://github.com/beck-8/subs-check) 与
[bestruirui/BestSub](https://github.com/bestruirui/BestSub) 的作者所有。
