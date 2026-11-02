# SubsCheck 安卓移植 — 进度与续做说明

最后更新：2026-11-02 13:30

## 一句话状态

**可交付。** 两个 ARM release 包已用正式 keystore 签名，x86_64 同源代码包在模拟器上验证过完整链路（启动内核 → 拉 23 个订阅源 → 检测 → 导出）。**唯一未做的是真实 ARM 手机上的验证。**

## 交付产物

**交付目录 `dist/`（可直接发给别人）：**

| 文件 | 大小 | SHA-256 | 说明 |
|---|---|---|---|
| `dist/SubsCheck-1.0.0-arm64-v8a.apk` | 34,214,062 B (32.6MB) | `3315b38b063e30a2336b3c38ed2db47fe2194e83313da43c835bd28a237a5a4a` | arm64 真机 |
| `dist/SubsCheck-1.0.0-armeabi-v7a.apk` | 34,117,298 B (32.5MB) | `bc9602edbb93adf1a5777411adef65598d08e0437c998c4b15069888f2e211f4` | armv7 老机器 |
| `dist/README.md` / `dist/SHA256SUMS.txt` | — | — | 安装说明与校验 |

`build/app/outputs/flutter-apk/app-x86_64-release-test.apk`（36.5MB）只用于模拟器验证，**不要分发**。

发布签名 keystore 不纳入版本控制。请使用自己的签名密钥进行分发构建。

- minSdk 24 / targetSdk 28 / versionCode arm64=2001 armv7=1001 / versionName 1.0.0
- 应用图标已换成自绘的蓝色圆角对勾（5 个 mipmap 密度全覆盖），启动器实测正常。

## 架构

```
Flutter UI (lib/)
  ↓ MethodChannel 'com.subscheck/native'
MainActivity.kt → KernelManager.kt / KernelService.kt（前台 Service 保活）
  ↓ exec
lib/<abi>/libsubscheck.so  ← Go 内核（GOOS=linux 静态 ET_EXEC，slim 构建）
  ↓ 监听 127.0.0.1:8199
Dart HTTP 客户端 (lib/src/api.dart) 带 X-API-Key
```

- 内核以 `libsubscheck.so` 混进 jniLibs，靠 `extractNativeLibs="true"` 落到 nativeLibraryDir 后直接 exec（Android 会自动 chmod 755）。
- targetSdk 必须 ≤28，否则 Android 10+ 禁止执行可写目录里的二进制。
- 内核 `sub-store-port` 被 patch 成空串 → 不启 Sub-Store、不拉 node。
- clash 完整配置由 App 自己拼：`assets/ACL4SSR_Online_Full.yaml`（513 行模板）+ 内核 `/sub/all.yaml` 的 proxies。

## 源码位置

- Go 内核上游：[beck-8/subs-check](https://github.com/beck-8/subs-check)，本地构建基于 commit `3c320fd5` 及 Android 适配补丁。
- 内核源码是独立 checkout，不包含在本 Android 仓库中；仓库内只保留 APK 使用的预编译内核：`android/app/src/main/jniLibs/`。

### 重新编译内核

以下命令需要单独准备包含 Android 适配补丁的内核源码 checkout；本仓库不包含该源码或 `kernel-build/` 产物。

```bash
export PATH=/d/Android/go/bin:$PATH GOPATH=/d/Android/gopath GOMODCACHE=/d/Android/gopath/pkg/mod
cd kernel
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -tags subscheck_slim -trimpath \
  -ldflags "-s -w -X main.Version=android -X main.CurrentCommit=dev" \
  -o ../kernel-build/slim/arm64.so .
# armv7 用 GOARCH=arm GOARM=7；模拟器用 GOARCH=amd64
```

编完要把产物复制到 `android/app/src/main/jniLibs/<abi>/libsubscheck.so`。

### 重新构建 APK

```bash
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export PUB_CACHE=D:/Android/pubcache
export JAVA_HOME=D:/Android/jdk-21.0.2
export ANDROID_HOME=D:/Android/sdk ANDROID_SDK_ROOT=D:/Android/sdk
export PATH=$JAVA_HOME/bin:$PATH

# 分发包
/d/Flutter/flutter/bin/flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64
# 模拟器验证包
/d/Flutter/flutter/bin/flutter build apk --release -PtargetAbi=x86_64
```

## 已完成的验证

- **最终版（12:56 出包）在 MuMu 12 上完整重跑一遍**：全新安装 → 启动内核（pid 4167，日志页显示的 pid 与 `ps` 一致）→ 23 个订阅源 → 19883 节点 → 297 存活 → 297 过媒体检测 → 174 过测速 → 导出 `mihomo.yaml` 50,928 B / 1841 行、`proxies.yaml` 36,340 B / 1327 行。整轮约 24 分钟（04:59:33 起，05:23:54 结束）。
- 导出配置用 pyyaml 做语义校验：`proxies` 174 条、名字 174 个全不重复；`proxy-groups` 29 个、`rule-providers` 31 个、`rules` 34 条；组内引用与规则目标**无悬空**（`DIRECT`/`REJECT` 是内置策略，不算悬空）；`rule-providers` 只有 `OpenAi` 未被 rules 引用（模板自带，无害）；末尾 `MATCH,🐟 漏网之鱼` 兜底存在。
- 两个 ARM 包内嵌内核 ELF 头校验：arm64 `e_machine=183`、armv7 `e_machine=40`，均为 `ET_EXEC`，与目录名一致。
- 5 个页面全部实拍确认：概览、节点（可搜索/排序/详情）、订阅、设置、日志。
- 三个 UI 缺陷已修复：检测结束结果不刷新、日志 ANSI 乱码、内核 pid 显示成 App pid。
- release 包 apksigner 校验通过（v2 scheme），aapt2 确认 targetSdk=28 / 单 ABI / 图标资源正确。

## 待办

1. **真机 ARM 验证**（唯一大缺口）。模拟器是 x86_64，ARM 内核在 MuMu 的 libhoudini 转译层下会触发 Go runtime `casgstatus` 断言崩溃 —— 这是模拟器限制，不是代码缺陷，但也意味着两个 ARM 包没在真实 ARM 设备上跑过。
2. 可选：给 ARM 真机加一个「首次启动自检」提示（DNS 补丁是否生效）。
3. 可选瘦身：armv7 内核 71MB 里还有可裁剪的依赖，收益有限。

## 已知限制

- 分享导出文件用 `share_plus`，精简 ROM 上可能没有分享目标，可直接从文件管理器取文件（路径见订阅页）。
- 内核拉订阅走 Go 的 `net.DefaultResolver`，已由 `kernel/android_support_linux.go` 补 223.5.5.5/119.29.29.29；测速与媒体检测走 mihomo 自己的 DNS，不受影响。
- 默认订阅源里几条已 404（Barabama/FreeNodes、shuaidaoya/FreeNodes、aiboboxx/v2rayfree），用户可在设置里编辑 config.yaml 增删。
- targetSdk=28 → 不适合上架 Google Play。

## 环境

JDK 21.0.2 / Go 1.25.4 / Android SDK 36 / Flutter 3.47.8，分别在 `D:\Android` 与 `D:\Flutter`。
MuMu 启动：`cd /e/MuMuPlayer/nx_main && ./MuMuManager.exe control -v 0 launch`，然后 `adb connect 127.0.0.1:16384`。
adb 在 git-bash 里必须先 `export MSYS_NO_PATHCONV=1`，且本地路径写成 `D:/...` 形式。
