# SubsCheck 安卓移植 — 进度与续做说明

最后更新：2026-11-02 22:35

## 一句话状态

**可交付。** 两个 ARM release 包已用正式 keystore 签名，x86_64 同源代码包在模拟器上验证过完整链路（启动内核 → 拉 23 个订阅源 → 检测 → 导出）。**唯一未做的是真实 ARM 手机上的验证。**

## 交付产物

**交付目录 `dist/`（可直接发给别人）：**

| 文件 | 大小 | SHA-256 | 说明 |
|---|---|---|---|
| `dist/SubsCheck-1.1.0-arm64-v8a.apk` | 34,395,181 B (32.8MB) | `d2ec594cd95f62d4003b66af558f9e92caecf4db56ad9347f7c26e1ce800f4a7` | arm64 真机 |
| `dist/SubsCheck-1.1.0-armeabi-v7a.apk` | 34,301,329 B (32.7MB) | `0aaac7a3097e8937a18f5eb9d2ae881a4c9788ade5fa311c71e4fbf64e68ebcd` | armv7 老机器 |
| `dist/README.md` / `dist/SHA256SUMS.txt` | — | — | 安装说明与校验 |

`build/app/outputs/flutter-apk/app-x86_64-release-test.apk`（36.5MB）只用于模拟器验证，**不要分发**。

发布签名 keystore 不纳入版本控制。请使用自己的签名密钥进行分发构建。

- minSdk 24 / targetSdk 28 / versionCode arm64=2002 armv7=1002 / versionName 1.1.0
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

### 1.1.0 新增功能验证（2026-11-02 22:30，MuMu x86_64 release 包）

- 设置页底部「关于」卡三项：「关于 SubsCheck（v1.1.0 · 内核 X）」「免责声明」「开源协议」。
- AboutPage：图标 + 版本号 + 内核版本/ABI、检查更新、相关链接、运行信息、许可，全部正常渲染。
- 检查更新实测：直连 `api.github.com` 成功返回「已是最新版本（v1.0.0）· 通过 api.github.com 获取」；镜像链 `gh-proxy.com` / `ghfast.top` 作为回退。
- 免责声明对话框五节全文可滚动、可关闭。
- 「项目地址」点击 → Chrome 打开 `github.com/tianduoyuguang/SubsCheck--android`，加载正常。
- `flutter analyze` → No issues found；`flutter test` → 2 passed。

### 1.2.0：导出目录可配置（2026-11-10，MuMu x86_64 release 包）

需求来自「app 的导出文件位置不能修改」，选定方案 A：设置页里可选目录。

- 三种模式：应用私有目录 / 手机 `Download/SubsCheck` / SAF 自选目录，选择持久化，重启 App 保持。
- **关键坑：Android 10+ 拿不到 `WRITE_EXTERNAL_STORAGE`。** 原先 `ExportStore.hasStoragePermission` 直接查该权限，
  但清单里它带 `maxSdkVersion="28"`，在 SDK 32 上请求必然落空，弹窗里出现红字「需要授予存储权限后才能写入」且文件不落盘。
  logcat 佐证：`SubsCheckMain: storage permission granted=false`，
  `GrantPermissionsViewModel: None of [WRITE_EXTERNAL_STORAGE, READ_EXTERNAL_STORAGE, ACCESS_MEDIA_LOCATION] in {}`。
  修法：`SDK_INT >= 29` 一律视为有权限（走 MediaStore 不需要权限）；Download 落盘改用
  `MediaStore.Downloads.getContentUri(VOLUME_EXTERNAL_PRIMARY)` + `RELATIVE_PATH="Download/SubsCheck"`，
  先按 DISPLAY_NAME 查同名再 `update` 复用，实现覆盖写而不产生 `proxies.yaml (1)`；`IS_PENDING` 前后置位。
  同时从清单删掉 `MANAGE_EXTERNAL_STORAGE` 与 `xmlns:tools`。
- SAF：`ACTION_OPEN_DOCUMENT_TREE` + `takePersistableUriPermission`，回推 `exportDirChanged` 事件。
- 另一个缺陷：`lib/src/export_dir.dart` 的 `_ExportDirSheet` 不监听 `AppState`，SAF 返回后外层卡片已更新但弹窗内
  单选项与「当前导出到」仍是旧值，需关掉重开才刷新。修法：`build` 改为 `ListenableBuilder(listenable: s, builder: ...)`
  包住原 body（抽成 `_buildBody`）。
- 实测（2560x1440，MuMu）：Download 模式导出 `proxies.yaml` 261 B，重复导出仍是同一文件；SAF 选 Documents 后
  外层与弹窗内均显示 `/storage/emulated/0/Documents`，重启 App 保持。`flutter analyze` → No issues found。
- 产物：`SubsCheck-1.2.0-arm64-v8a.apk`（34,427,929 B，sha256 `d159554e…284a`）、
  `SubsCheck-1.2.0-armeabi-v7a.apk`（34,342,529 B，sha256 `631a3a33…3303`），versionCode 3。

### 1.2.1：修复自动更新无法安装（2026-11-10，MuMu x86_64 release 包）

需求来自「app 自带的更新下载完成后显示没有安装权限导致更新不了」。

- **根因**：`AndroidManifest.xml` 从未声明 `REQUEST_INSTALL_PACKAGES`。Android 8.0+ 拉起系统安装器必须先有该权限，
  旧 `ApkDownloader.install()` 直接 `startActivity(ACTION_VIEW)` 且无任何判断与兜底，用户也没有去授权的入口。
  证据：`cmd appops get com.subscheck.subscheck REQUEST_INSTALL_PACKAGES` → `No operations. Default mode: default`；
  系统权限页 `GrantPermissionsViewModel` 里根本没有该项可申请。
  另注意：该机器 `appops` 命令不可用（`inaccessible or not found`），必须用 `cmd appops`。
- 清单补 `REQUEST_INSTALL_PACKAGES`；`ApkDownloader` 新增 `isInstallAllowed()`（`canRequestPackageInstalls()`，SDK<26 恒 true）、
  `openInstallSettings()`（`ACTION_MANAGE_UNKNOWN_APP_SOURCES` + `package:` uri → 无 uri 版本 → `ACTION_APPLICATION_DETAILS_SETTINGS` 三级兜底）、
  `resumeIfPending()`、`requestPermission()`；`install()` 开头加权限闸门并置 `needPermission` 状态；
  `run()` 改为**先 install 再置 done**，保证 Flutter 看到 done 时权限状态已确定。
- `MainActivity` 新增 `installPermission` / `installStatus` / `installNow` 三个 channel 方法（`startActivity` 必须包 `runOnUiThread`，
  因为 dispatch 跑在工作线程池），并 override `onResume()` 调 `resumeIfPending`。
- 关于页：`_tickDownload` 在 `done && needPermission` 时停止轮询并显示两张卡片「允许安装未知应用」「我已允许，继续安装」。
- **为什么不能只靠 onResume**：MuMu 会把系统设置页开到另一个虚拟 display（实测 Display #12，本 App 在 #11），
  App 的 Activity 从未被 pause，`onResume` 永不触发。修法：`_startPermWatch()` 用 `Timer.periodic(1200ms)` 轮询
  `Native.installAllowed()`，授权后自动续装；`_permPoll` 幂等、在 `dispose`/重新下载/拉起成功后取消。
- **为什么要等 2 秒**：抢在系统恢复任务栈之前拉安装器会看到
  `ActivityTaskManager: [KeepAlive] startActivityFromRecents 9:Task{... MainActivity}`，
  系统把刚弹出的安装器压回去、把 App 拉回前台。加 `Future.delayed(2000ms)` 后日志变为
  `[KeepAlive] reused display 7 for pkg com.android.packageinstaller`，安装器正常留在前台。
- **验证教训**：验证自更新必须让测试包的 `versionCode` **小于**目标包。首次用 `--build-number=90` 打测试包去升级
  versionCode=3 的 1.2.0，被系统按降级拒绝：`PackageInstallerSession: Failed to verify session ... [INSTALL_FAILED_VERSION_DOWNGRADE]`。
  改用 `--build-number=2` 即通过。
- 端到端实测（1.1.9(2) → 1.2.0(3)）：下载 34,427,929 B 完成 → `SubsCheckDownload: install blocked: REQUEST_INSTALL_PACKAGES not granted`
  → 点「允许安装未知应用」→ 系统设置开在 Display #12 → 开关 (2450,660) → `REQUEST_INSTALL_PACKAGES: allow`
  → 返回后日志 `install permission granted, resuming install` → 安装器 → 「更新」→ `InstallSuccess`「已安装应用。」
- `flutter analyze` → No issues found；`flutter test` → 2 passed。
- 产物：`SubsCheck-1.2.1-arm64-v8a.apk`（34,433,021 B，sha256 `788fd015…c81b`）、
  `SubsCheck-1.2.1-armeabi-v7a.apk`（34,348,441 B，sha256 `880696ba…17e3`），versionCode 4。

## 仓库体积治理（2026-11-10）

发版三轮后仓库膨胀到 580 MB，做了两步处理：

1. **停止跟踪 APK**（`b622e64`）：`.gitignore` 增加 `/dist/*.apk`、`/dist/*.aab`、`/dist/*.zip`，
   `git rm --cached` 掉两个安装包（磁盘文件保留），提交 `b622e64`，HEAD 跟踪体积 277 MB → 211 MB。
2. **重写历史**（`199affd`）：用 `git filter-repo --invert-paths --path SubsCheck_Win_GUI/ --path-glob 'dist/*.apk'`，
   只作用于 `master` + 三个 tag（`--refs master v1.0.0 v1.1.0 v1.2.0`），随后 `git reflog expire --expire=now --all` + `git gc --prune=now`。
   - `.git` 580 MB → **235 MB**（本地），远端 bare 仓 `71.6 MiB`，全新 clone 的 `.git` 为 72 MB、含 212 MB 工作树。
   - 清掉的历史：`SubsCheck_Win_GUI/` 171.1 MB、`dist/*.apk` 196.3 MB。
   - **保留** `jniLibs/*/libsubscheck.so`（3 个 ABI 共约 221 MB，是运行时必需的内核二进制，无法外置）。
   - 文件树完全一致：`HEAD^{tree}` 重写前后同为 `7685720b38df2867f007779bba0e128617e55c6c`。
   - tag 指向变更：`v1.0.0` `a98c0ac`→`0709393`、`v1.1.0` `8841019`→`c32f6b9`、`v1.2.0` `06bebc1`→`489954f`（新建附注 tag，指向 `8ab2f1e` 重写后的等价 commit）。
   - GitHub 上三个 Release 及其资产（各 3 个）**未受影响**，直链下载仍 302→200。
   - 重写前完整备份：`D:\DeepSeek\Workspace\subscheck-backup-20261110-222426.bundle`（234 MB，`git bundle verify` 通过）。
3. `6a2fe85`：README 与 dist/README 的安装段改为指向 Releases，并说明 APK 不入库的原因。

发现但保留的现象：harness 自动生成的 `refs/agents/.../checkpoints/turn/{0..8}` 仍持有 WinGUI 的 blob（turn/0~4 树 449 MB），
这些引用不在 `filter-repo` 的 `--refs` 范围内且被 `gc` 视为可达，因此本地 `.git` 仍是 235 MB 而非 20 MB。
它们不参与 fetch/push（`refs/agents/*` 不随 clone 出来），对远端和协作者零影响；若将来要彻底清理，需先删掉这些 ref 再 gc。

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
