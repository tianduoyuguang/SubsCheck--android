# SubsCheck 安卓移植 — 进度与续做说明

最后更新：2026-11-02 22:35

## 一句话状态

**可交付。** 两个 ARM release 包已用正式 keystore 签名，x86_64 同源代码包在模拟器上验证过完整链路（启动内核 → 拉 23 个订阅源 → 检测 → 导出）。**唯一未做的是真实 ARM 手机上的验证。**

## 交付产物

**交付目录 `dist/`（可直接发给别人）：**

| 文件 | 大小 | SHA-256 | 说明 |
|---|---|---|---|
| `dist/SubsCheck-1.2.8-arm64-v8a.apk` | 34,453,613 B (32.9MB) | `225b3a344648907a854cd514f1c554ccd6a6e9206ab08bae69bb6f5de2df0578` | arm64 真机 |
| `dist/SubsCheck-1.2.8-armeabi-v7a.apk` | 34,368,989 B (32.8MB) | `c299dcb4fc67ef1882dde32395132cffab2ba689a4f2eb8b821463f3b6061ead` | armv7 老机器 |
| `dist/README.md` / `dist/SHA256SUMS.txt` | — | — | 安装说明与校验 |

`build/app/outputs/flutter-apk/app-x86_64-release-test.apk`（36.5MB）只用于模拟器验证，**不要分发**。

发布签名 keystore 不纳入版本控制。请使用自己的签名密钥进行分发构建。

- minSdk 24 / targetSdk 28 / versionCode 11 / versionName 1.2.8
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

### 1.2.2：概览页目录信息跟随设置（2026-11-11，MuMu x86_64 release 包）

需求来自「app 的概览页面的显示输出目录不会随着更改而变化」。

- **根因**：`lib/pages/overview.dart` 那张卡从 v1.0 起就是写死的 `Text(state.outputDir)`，
  而 `AppState.outputDir`（`lib/src/app_state.dart:30`）取的是 `info['outputDir']`，
  即 `KernelManager.kt` 里 `val outputDir: File get() = File(baseDir, "output")` 的**内核固定数据目录**，
  用户在任何界面都改不了它；用户能改的是「导出目录」`AppState.exportPath` / `exportLabel`
  （`app_state.dart:33-34`，来自 `ExportStore.info(app)`），概览页从未读过。刷新链路本身没问题：
  `lib/pages/home.dart:23` 用 `AnimatedBuilder(animation: widget.state)` 包住 IndexedStack，
  `applyExportInfo` 会 `notifyListeners`。
- **修法**：原来单张「输出目录」卡改成两行 ——
  - 「导出目录」：`state.exportLabel` + 11px 的 `state.exportPath` + 右侧 chevron，
    `onTap` 直接 `showExportDirSheet(context, state)`，概览页不用跑去设置页也能改；
  - 「内核数据目录」：`Icons.storage_outlined` + `state.outputDir`，只读展示。
- 弹窗侧的刷新早在 1.2.0 就修好了（`lib/src/export_dir.dart:99` 的 `_ExportDirSheet.build` 用
  `ListenableBuilder(listenable: s, ...)` 包住 `_buildBody`）；本次只是让概览页也走同一条 `AppState` 通知链路。
- 实测（MuMu x86_64，display 2，2560x1440）：概览页切到「手机 Download/SubsCheck」后卡片**原地**变为
  `/storage/emulated/0/Download/SubsCheck`，再切回私有目录同样即时刷新。
- `flutter analyze` → No issues found；`flutter test` → 2 passed。
- 产物：`SubsCheck-1.2.2-arm64-v8a.apk`（34,433,649 B，sha256 `5fb440c6…8c73`）、
  `SubsCheck-1.2.2-armeabi-v7a.apk`（34,349,001 B，sha256 `d9d5bb83…e3d8`），versionCode 5，
  签名证书与 1.2.0/1.2.1 相同（`d3af548e…eb9b`），可直接覆盖安装。

### 1.2.3：修复「已授权安装未知应用仍显示未授权」（2026-11-11，MuMu x86_64 release 包）

用户反馈：「app 内升级时出现了问题，已经授权安装未知权限，点击已经授权仍然显示未授权」。

- **根因**：权限判定只有一个来源 —— `ApkDownloader.isInstallAllowed()` 里的
  `PackageManager.canRequestPackageInstalls()`。本应用为让非 PIE 的内核能被 exec，
  把 `targetSdk` 锁死在 28（`android/app/build.gradle.kts` 有注释说明），
  这个 API 在部分系统上与「安装未知应用」开关并不同步，开关已开仍返回 false，
  于是 UI 永远停在未授权。设备侧证据：`cmd appops get … REQUEST_INSTALL_PACKAGES`
  在开关打开后返回 `REQUEST_INSTALL_PACKAGES: allow`，而 `set … default` 后回到
  `No operations. / Default mode: default` —— 这条 AppOp 可读回且与开关一致，是更可靠的来源。
- **改法**：
  - `ApkDownloader.kt` 新增 `private const val OP_INSTALL_PACKAGES = "android:request_install_packages"`
    （`AppOpsManager.OPSTR_REQUEST_INSTALL_PACKAGES` 在公开 SDK 里是隐藏常量，直接引用编译报
    `Unresolved reference`）与 `installOpMode()`（SDK>=29 用 `unsafeCheckOpNoThrow`，否则
    `checkOpNoThrow`）；`isInstallAllowed()` 改为「AppOps 为 MODE_ALLOWED 即放行，否则回落原 API」。
  - 新增 `hasCachedApk()` / `cachedApk()`（扫 `cacheDir/update`，取最新一个大于 1024 B 的 apk）、
    `installCached()`、`forceInstallCached()`（不判权限，走 `install(ctx, apk, force = true)`）。
  - `MainActivity.kt`：`installStatus` 增返 `hasCached`；`installNow` 改为
    `resumeIfPending() || installCached()` 并回传 `allowed`；新增 `installForce` 通道方法。
  - `lib/src/native.dart`：新增 `installState()`、`installForce()`。
  - `lib/pages/about.dart`：新增 `_restorePendingInstall()`（进页面时按 `hasCached && !allowed`
    还原「只差授权」状态）；`_installNow()` 在正常续装失败后自动走 `installForce()` 兜底；
    `_grantInstallPermission()` 打开设置页后启动轮询监视，不再只给一句 toast。
- 实测（MuMu，SDK 32 / Android 12）：
  - 把 release 包装进 `cacheDir/update/SubsCheck-1.2.3.apk` 并 `appops set … default` 后打开关于页，
    两项引导正常出现；
  - 点「我已允许，继续安装」→ 日志 `force install cached apk: SubsCheck-1.2.3.apk` →
    系统直接弹出「要更新此应用吗？」→「更新」→ `versionCode=6`、`InstallSuccess`；
  - 点「允许安装未知应用」→ 系统页开关打开后 `REQUEST_INSTALL_PACKAGES: allow` →
    返回即自动拉起安装器（日志 `install cached apk: SubsCheck-1.2.3.apk`），无需再点第二次。
- `flutter analyze` → No issues found；`flutter test` → 2 passed。
- 产物：`SubsCheck-1.2.3-arm64-v8a.apk`（34,434,777 B，sha256 `b5603bda…e803`）、
  `SubsCheck-1.2.3-armeabi-v7a.apk`（34,350,121 B，sha256 `dd75fd4a…08fb`），versionCode 6。

### 1.2.4：导出目录入口收敛到设置页（2026-11-11，MuMu x86_64 release 包）

用户反馈：「概览和设置里都能改输出目录，留一个就行」。

- **实际有三处入口**（用户只注意到两处）：`lib/pages/overview.dart:159`「导出目录」、
  `lib/pages/settings.dart:218`「导出目录」、`lib/pages/subscription.dart:179`「导出文件位置」
  （标题不同所以此前没被当成同一开关），三处都 `onTap: showExportDirSheet(...)`。
- **改法**：导出目录属于设置项，只保留 **设置 → 导出文件** 一个可改入口；
  概览页与订阅页的对应 ListTile 去掉 `trailing: Icon(Icons.chevron_right)` 与 `onTap`，
  改为只读展示当前路径，并删掉两页里已无用的 `import '../src/export_dir.dart';`
  （否则 `unused_import` 会让 `flutter analyze` 报错）。
  这样做的理由：同一开关分散在多处，每处都要各自维护刷新逻辑（1.2.2 就为此改过一轮），
  收敛到一处后 `showExportDirSheet` 内部的状态监听成为唯一刷新路径。
- 实测（MuMu，SDK 32 / Android 12）：概览页「导出目录」行已无 chevron、点击无任何反应；
  订阅页「导出文件位置」同样只读；设置页「导出文件」卡片点击仍能正常弹出三项选择框。
- `flutter analyze` → No issues found；`flutter test` → 2 passed。
- 产物：`SubsCheck-1.2.4-arm64-v8a.apk`（34,434,513 B，sha256 `40270ab0…5177`）、
  `SubsCheck-1.2.4-armeabi-v7a.apk`（34,349,845 B，sha256 `30ce7f86…48e`），versionCode 7。

### 1.2.8：导出不再自动弹分享面板 + 新增「另存为…」（2026-11-24，MuMu x86_64 release 包复测）

用户反馈（m07646 原文）：「我点导出是出现的是分享页面，而不是保存文件的页面」。

#### 根因

`lib/pages/subscription.dart` 的 `_export()` 在 `Native.saveExport()` 落盘之后**无条件**调用
`_share()` → `Share.shareXFiles()`，所以每次导出都会立即弹出系统分享面板。
这个行为是 1.2.6 引入的：原本直接分享磁盘路径，在 SAF 自定义目录下该路径不可读会 FileNotFoundException，
改成先写一份 cacheDir 副本后，自动弹分享这个动作被一并保留了下来。导出本该只负责保存。

#### 改动

- `_export()` 尾部去掉 `await _share(...)`，改为 SnackBar「已保存到 <path>」，右侧带一个「分享」按钮，
  分享变成显式动作。
- 新增 `_saveAs({required bool full})`：拉系统 `ACTION_CREATE_DOCUMENT` 对话框，由用户自己挑文件名和位置，
  不经过导出目录设置，也不会弹分享面板。用户取消时静默返回（`canceled=true` 不报错）。
- 两个导出 ListTile 的 `trailing` 从单个 chevron 改成 `Row`：`IconButton(Icons.save_alt, tooltip: '另存为…')` + chevron。
- `lib/src/native.dart` 新增 `Native.saveExportAs(name, content)`。
- `MainActivity.kt`：新增 `REQ_SAVE = 9004`、`pendingSaveResult/Name/Content` 三个字段、
  `launchSaveDocument()` / `finishPendingSave()` / `handleSaveDocumentResult()`；
  `runAsync()` 里对 `saveExportAs` 特判并 `return`（必须早于线程池，因为要等系统对话框返回）。
- `ExportStore.kt`：`mimeFor()` 由 private 改 public；新增 `friendlyLabelFor(ctx, uri)`，
  对 `com.android.externalstorage.documents` 用 `DocumentsContract.getDocumentId` 还原成 `/storage/emulated/0/...`。
- 写入用 `openOutputStream(uri, "wt")` 先截断，避免覆盖已有文件时留旧尾巴。

#### 实测（MuMu x86_64 / SDK 32 / Android 12）

- 点「导出仅节点配置」行本身 → 不再弹 ChooserActivity，`topResumedActivity` 仍是 MainActivity，
  直接落盘 `/storage/emulated/0/Download/SubsCheck/proxies.yaml`（255 B），SnackBar 显示「已保存到 …」。
- 点行右侧「另存为…」→ `com.android.documentsui/.picker.PickActivity`，
  默认落在 Documents，点「保存」后 `/storage/emulated/0/Documents/proxies.yaml`（255 B）内容正确。
- 在 picker 里按返回键取消 → 回到 App，无任何错误提示，UI 保持原状（取消路径已验证）。
- 连续导出两次同名文件 → MediaStore 命中已有行并 `update` 覆盖，**不产生 "proxies.yaml (1)"**。
  注意：用 `adb shell rm` 直接删文件只会移除文件、留着 MediaStore 行，再导出会命中那条空行变成 `(1)`；
  模拟器上清测试数据要用 `content delete --uri content://media/external/downloads --where ...`。
- `flutter analyze` → No issues found；`flutter test` → 10 passed。
- aapt2 核验：versionCode 11 / versionName 1.2.8 / minSdk 24 / targetSdk 28 / compileSdk 36。
- 产物：`dist/SubsCheck-1.2.8-arm64-v8a.apk`（34,453,613 B，sha256 `225b3a34…0578`）、
  `dist/SubsCheck-1.2.8-armeabi-v7a.apk`（34,368,989 B，sha256 `c299dcb4…1ead`）。
- 提交 `e3829f7` 已 push master，tag `v1.2.8` 已 push。
  Release id **456700115**，https://github.com/tianduoyuguang/SubsCheck--android/releases/tag/v1.2.8
  三资产均 `uploaded`，匿名直链 302→200。

### 1.2.7：启动自动检查更新 + 订阅页新增导出自定义位置入口（2026-11-24，MuMu x86_64 release 包复测）

用户需求（m07078 原文）：「加一个启动自动检查更新，可以选择是否更新还有不想更新时可以选择不再提示」；
追加需求（m07366 原文）：「订阅page上加一个导出自定义位置」。

#### 启动自动检查更新

- 启动流程改为串行：免责声明 → 静默检查更新（`lib/main.dart` 的 `_startupSequence()`），
  避免两个对话框叠在一起。
- 检查复用已有的 `lib/src/updater.dart`（`UpdateChecker.check`，三链路 api.github.com → gh-proxy.com → ghfast.top，
  全失败不抛异常），不阻塞首屏。
- 新文件 `lib/src/update_prompt.dart`：`showUpdatePrompt(context, {currentVersion, latestVersion, notes})`
  返回 `UpdateChoice.update / later / skip` 三选一，标题「发现新版本」，正文含 release notes（`BoxConstraints(maxHeight: 220)` 内滚动）。
- 「不再提示」= **只记住被忽略的那个版本号**（SharedPreferences `update_skip_version`），
  不是永久关闭：远端版本严格更新时仍会提示。
- 版本号必须用 `await Native.info()` 的 `versionName`，**不能用 `state.info`**：
  `_maybeUpdate()` 在首帧后就跑，`AppState.initialize()` 可能未完成，
  空版本会让 `compareVersion` 把任何版本都判成「有更新」。
- 「设置 → 关于」新增「启动时自动检查更新」开关（`SwitchListTile`，默认开，
  SharedPreferences `auto_check_update`）；关闭时清空忽略版本号。
- 从弹窗点「立即更新」→ `push(AboutPage(autoUpdate: true))`，进入后自动选资产并开始下载，
  复用 about.dart 已有的下载/安装/权限轮询链路。
- 原生侧 `MainActivity.kt` 新增三个分支：`updateSkip` / `setUpdateSkip` / `setAutoUpdate`。

#### 订阅页「导出自定义位置」

- 订阅页导出卡片原来三项（完整配置 / 仅节点 / 刷新节点数），在「仅节点」之后插入
  「导出自定义位置」，副标题动态显示 `widget.state.exportLabel`。
- 复用 `showExportDirSheet`（与设置页同一个弹窗、同一份逻辑），三个选项：
  应用私有目录 / 手机 Download/SubsCheck / 自定义目录（SAF）。
- 注意：这一项**不违反** 1.2.4 的「入口收敛」结论 —— 1.2.4 收敛的是「只读展示」的伪入口；
  这里是用户明确要求新增的可改入口，且与设置页共用同一份监听刷新逻辑。
- 弹窗内状态由 `_ExportDirSheetState` 的 `ListenableBuilder(listenable: s)` 驱动，
  Kotlin 侧 `exportDirChanged` 回推后单选项与「当前导出到」即时刷新。

#### 构建坑（已修）

- 跨盘 Kotlin 增量编译失败：插件源码在 `C:\Users\...\AppData\Local\Pub\Cache`、工程在 `D:\`，
  `RelocatableFileToPathConverter` 报 `this and base files have different roots`。
  解法：设 `PUB_CACHE=D:/Android/pubcache` 让依赖解析到 D 盘，并在 `android/gradle.properties` 加
  `kotlin.incremental=false` 与 `kotlin.incremental.useClasspathSnapshot=false`。

#### 验证与产物

- `flutter analyze` → No issues found；`flutter test` → **10 passed**（新增 6 条：版本比较、
  「不再提示只压住该版本」、弹窗三个出口各一条）。
- MuMu x86_64（SDK 32 / Android 12，display 2）release 包实测：
  免责声明「同意并继续」→ 订阅页「导出自定义位置」条目正常出现（副标题「当前：应用私有目录」）→
  点击弹出三项选择框 → 选「手机 Download/SubsCheck」→ 弹窗内「当前导出到」立即变为
  `/storage/emulated/0/Download/SubsCheck` → 关闭弹窗后订阅页副标题同步变为
  「当前：手机 Download/SubsCheck，点此可改到手机目录或自选文件夹」。
- 启动更新弹窗未在模拟器上复测（本轮模拟器上 `releases/latest` 返回 1.2.7，与本地同版本故不弹），
  由 6 条单测/组件测试覆盖。
- 产物（aapt2 核验 versionCode 10 / versionName 1.2.7 / minSdk 24 / targetSdk 28）：
  - `dist/SubsCheck-1.2.7-arm64-v8a.apk` 34,447,053 B，sha256 `5ba36ad3b00dce802a0a823b9a2bc317a1dcd613de10e0d94001131a847ec11d`
  - `dist/SubsCheck-1.2.7-armeabi-v7a.apk` 34,365,169 B，sha256 `3ec843133176f270723eeb5a5a13bfd26447e9777725972a04cb03c62f322248`

### 1.2.6：测速进度分母修正 + 审查报告全部修理（2026-11-16，测速改动在 MuMu x86_64 复测）

用户反馈（m06201 原文）：「运行时的测速进度应该是已测速/可用节点，而不是已测速/节点总数」。

- 现象：概览页「测速进度 61/19883」——分母是订阅节点总数，进度条几乎不动。
  实际进入测速的只有通过测活 + 媒体检测 + 过滤的节点（内核 `pipeline.filterPass`）。
- 内核侧数据早就有了：`kernel/app/server.go:311-319` 的 `pipeline` 对象里
  `total` / `aliveDone` / `alivePass` / `mediaDone` / `filterPass` / `speedDone` / `speedPass`。
  三段流水线的总数是级联的：测活对 `total`、媒体对 `alivePass`、测速对 `filterPass`
  （见 `kernel/check/check.go:316-325` 的 `SavePhaseResult` 与
  `kernel/check/progress.go:120-122` 的 `formatStageLine("测速", speedDone, filterPass, ...)`）。
  App 只用了 `speedDone` 与 `proxyCount`，分母取错了。
- 改法：
  - `lib/src/models.dart` 新增 `int get speedTotal => filterPass > 0 ? filterPass : available;`
    （filterPass 还没涨起来时回落到 available，避免显示 0/0），
    `speedRatio` 从 `speedDone / proxyCount` 改为 `speedDone / speedTotal`。
  - `lib/pages/overview.dart:105` 文案改为 `'测速进度 ${st.speedDone}/${st.speedTotal}'`。
  - 未配置 filter、未开媒体检测时 `filterPass == available`，也就是概览页「可用节点」那一格，
    与用户描述的「已测速/可用节点」一致；配了 filter 时分母是过滤后的数量，语义仍正确。
- 验证：起了一个本地假内核（Node 写的 8199 服务，返回 proxyCount=19883 / available=297 /
  filterPass=174 / speedDone=61），`adb reverse tcp:8199 tcp:8199` 转发进模拟器，
  概览页实测显示 **「测速进度 61/174」**；改前同一份数据会显示 61/19883。
- 单测：`test/widget_test.dart` 新增两条 —— 「测速进度分母是可用节点数（filterPass）」断言
  speedTotal=55、speedRatio=40/55；「filterPass 还没涨起来时回落到 available」断言 speedTotal=42。
  `flutter analyze` → No issues found；`flutter test` → **4 passed**。
- 产物：versionCode 9 / versionName 1.2.6。

#### 同一版本内的「审查报告全部修理」（纯代码改动，未在模拟器复测）

用户 m06349 要求只读代码审查，随后 m06575 下令「全部修理，打包成1.2.6」。
下面按问题逐条记，涉及文件与行号以本次提交为准。

**必修项**

1. `lib/pages/subscription.dart` 的订阅地址错了两条 —— 原来列 `/sub/all.txt`（内核从不写这个文件，
   全仓唯一出现是 `kernel/app/server.go:69` 的 StaticFile → 必 404）与 `/all.yaml`（标成「规则模板」
   实际是节点列表，`kernel/save/save.go:72` `method.SaveToLocal(allYamlData, "all.yaml")`）。
   改法：`/all.txt`、`/mihomo.yaml` 都依赖 Sub-Store，本 App 未启用，直接删；只留 `节点列表 (all.yaml)`，
   并在说明里补「需要完整配置或 Base64 请用上面的导出功能」。
2. `lib/src/api.dart:71-78` `serverLogs()` 直接 `return r.body`，而内核 `getLogs` 返回的是
   `c.JSON(200, gin.H{"logs": lines})`（`kernel/app/server.go:344-359`）→ 日志页 HTTP 分页显示 JSON 原文。
   改法：`jsonDecode` 后取 `logs` 数组用 `\n` 拼接，解析失败回落纯文本（兼容老内核）。
3. `lib/pages/settings.dart` 「忽略电池优化」ListTile 没有 onTap（Manifest 里却声明了
   `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`）。改法：新增原生方法 `batteryStatus`（`PowerManager
   .isIgnoringBatteryOptimizations`）与 `requestBattery`（优先 `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`，
   失败退 `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`），设置页加 `WidgetsBindingObserver`，
   回前台时（`AppLifecycleState.resumed`）重查并刷新勾选状态。
4. `lib/src/disclaimer.dart` 注释称「启动时首次提示共用同一份文案」，实际只有设置页一个调用点，
   首启不弹免责声明。改法：`showDisclaimerDialog(context, requireAccept: true)` 增加 `PopScope(canPop: false)`
   与「不同意 / 同意并继续」两个按钮，`lib/main.dart` 用 `addPostFrameCallback` + `Native.disclaimerSeen()`
   判断首次启动，同意后 `Native.markDisclaimerSeen()`（`SharedPreferences("subscheck")` 的 `disclaimer_seen`），
   不同意则 `SystemNavigator.pop()` 退出且不写标记（下次仍会问）。
5. 分享与 SAF 自定义目录冲突：`ExportStore.saveToTree` 返回的是 `treeLabel + "/" + name` 拼接串
   （`ExportStore.kt:259`），磁盘上并不存在，`share_plus` 会把它 `copyTo` 到自己的 cache → FileNotFoundException。
   改法：新增原生方法 `shareCopy`（写 `cacheDir/share/<name>` 并返回真实绝对路径），
   订阅页所有分享（导出后自动分享、「已导出」卡片的分享按钮）统一改走它。

**建议项**

- 媒体检测阶段原来在 UI 上完全隐身（`mediaDone`/`alivePass` 只在 `models.dart` 出现）。
  改法：`KernelStatus` 新增 `mediaTotal => alivePass`、`mediaRatio`、`hasMediaCheck`，
  概览页在测活与测速之间加第三段进度条「媒体检测 x/y」。
- 订阅页节点数量只在 `initState` 数一次，检测完成后数字不更新。改法：监听 `AppState`，
  `checkedAt` 变化时重数（`_countedAt` + `_counting` 防重入）。
- `lib/pages/nodes.dart` 「只看有速度」用 `n.speed > 0`，与「可用」不等价 —— 未开测速时 speed 全为 0，
  一开筛选列表就空。改法：仅在 `status.hasSpeedTest` 时才应用该过滤。
- `NodeItem` 完全没有解析内核 `results.json` 里的 `details` 数组（`kernel/save/results.go` 的
  `NodeDetail{Key,Value}`，白名单 19 项：cipher/flow/alpn/ws-path/grpc-service-name/plugin 等）。
  改法：新增 `NodeDetail` 模型并解析，节点详情弹窗逐条展示；弹窗内容改为可滚动。
- `lib/pages/logs.dart` 的 3 秒定时器无条件常驻。改法：只在「HTTP」分页时启动，切回「内核」即取消。
- `lib/pages/settings.dart` 的 `_host/_port` 控制器在 `initState` 定型、不随 `AppState` 变化。
  改法：加 `FocusNode` 并在 `AppState` 监听里同步（正在编辑时不覆盖用户输入）。
- 导出 mihomo 配置缺 `port/mode/dns`：`assets/ACL4SSR_Online_Full.yaml` 第一行就是 `proxy-groups:`，
  拼出来的配置没有顶层基础键。改法：`lib/src/exporter.dart` 新增 `_base` 常量（mixed-port 7890、
  mode rule、fake-ip DNS），`buildMihomo` 输出「基础段 + proxies + 模板」。

**性能与清理**

- `lib/pages/home.dart` 原用 `AnimatedBuilder` 包住整个 `Scaffold` + `IndexedStack`，每 2 秒重建五页。
  改法：删掉外层 `AnimatedBuilder`，五个页面各自 `build()` 返回 `AnimatedBuilder`，
  并把原 `build` 改名为 `_body`。
- `lib/src/app_state.dart`：`initialize()` 换 `api` 前先 `api?.dispose()`（否则旧 HttpClient 泄漏）；
  `refresh()` 里 `Native.status()` 从每 2 秒都调改为每 5 个周期一次（`_tick % 5`）；
  `notifyListeners()` 改为先比对快照签名 `_snapshotChanged()`，无变化不通知；
  删掉命名骗人的 `copyWithZero()` 扩展（实为返回 `KernelStatus.empty`），直接写 `status = KernelStatus.empty`；
  `KernelStatus` 补 `operator ==` / `hashCode`。
- 删死代码：`lib/src/api.dart` 的 `ping()` / `config()` / `saveConfig()`（无调用方）；
  `pubspec.yaml` 去掉 `http ^1.2.2` 与 `yaml ^3.1.2`（`grep package:http|package:yaml` 在 `lib/` 下零命中），
  `lib/pages/about.dart:398` 的依赖文案同步改为「Flutter、share_plus、cupertino_icons」。

**验证与产物**

- `flutter analyze` → No issues found（修掉一处 `use_build_context_synchronously`：
  `lib/main.dart` 里原来用 `mounted` 校验另一个 `BuildContext`，改为 `ctx.mounted`）。
- `flutter test` → **6 passed**（新增「媒体检测分母是测活通过数（alivePass）」与「NodeItem 解析 details 数组」）。
- 产物（aapt2 核验 versionCode 9 / versionName 1.2.6 / minSdk 24 / targetSdk 28，native-code 分别为
  arm64-v8a 与 armeabi-v7a）：
  - `dist/SubsCheck-1.2.6-arm64-v8a.apk` 34,441,529 B，sha256 `622182e55d845c9897e9d4ae955c2da555a3cbc64b4364a4f875186171214c86`
  - `dist/SubsCheck-1.2.6-armeabi-v7a.apk` 34,358,285 B，sha256 `6318a8b5fdf378d6950c8f012a7e3d70367452275df7d7d155e4c5c90b300ebb`
- 出包后按用户要求（m05728）暂存未发；用户 m06885「发布」后已发布：
  提交 `f3e85d0` 与 `cd9377a` 一并 push 到 master，tag `v1.2.6`，
  Release id **446955432**，https://github.com/tianduoyuguang/SubsCheck--android/releases/tag/v1.2.6
  （两个 apk + SHA256SUMS.txt，三资产均为 `uploaded`；HEAD 校验 Content-Length 与本地一致：
  34,441,529 / 34,358,285 / 194）。
- 同一轮清理了 `dist/` 里 1.2.3 / 1.2.4 / 1.2.5 的旧包与 `build/` 下的历史 apk
  （含 1.2.1 的 `build/apk-v7a.apk`、1.0.0 的 debug 包、11-02 的旧 release）。

### 1.2.5：高级卡片精简 + 订阅页去掉导出文件位置（2026-11-14，未在模拟器复测）

用户要求（m05728 原文）：「app里设置-高级 里的内核二进制与工作目录删掉」；
（m06031 原文）：「把订阅page里的导出文件位置删掉」。
订阅页这处改动原计划作为 1.2.6 发布，最后按用户要求**合并进 1.2.5 一起发**，
所以 versionName 仍为 1.2.5、versionCode 仍为 8，两个 apk 重新打包。

- **设置 → 高级**：`lib/pages/settings.dart` 里删掉两个 ListTile ——
  「内核二进制」（显示 `info['nativeLibraryDir']`）、「工作目录」（显示 `info['filesDir']`），
  连同它们前面的两条 `const Divider(height: 1),` 一并删除。
  删后 `nativeLibraryDir` / `filesDir` 在 `lib/` 下已无任何引用；
  `info['pid'/'abi'/'sdk']`（settings.dart:123）与 `info['versionName']`（settings.dart:301）仍在用。
  结果：高级卡片只剩「编辑配置文件」与「API Key」两项（settings.dart:269、277）。
- **订阅页**：`lib/pages/subscription.dart` 里删掉「导出文件位置」那张 `Card`（`leading: Icon(Icons.folder_open)`，
  副标题展示 `widget.state.exportLabel` 与 `SelectableText(widget.state.exportPath)`），
  连同它前面的 `const SizedBox(height: 16),` 一起删除，避免页面底部多出空档。
  该卡片 1.2.4 起已无 `onTap`，纯只读，没有交互逻辑要迁移。
  删后 `exportLabel` / `exportPath` 在该文件中已无出现，`widget.state` 仍有 4 处使用
  （第 30、39、54、77 行），故 `import '../src/app_state.dart';` 保留。
- 剩余两处导出目录展示不变：`lib/pages/settings.dart:222/225`（唯一可改入口）、
  `lib/pages/overview.dart:165/167`（只读）。
- 校验：`flutter analyze` → No issues found（3.7s）；`flutter test` → 2 passed。
- **本轮没能装进模拟器验证**：MuMu 后端服务起不来（`MuMuManager.exe control -v 0 launch` 与
  `mumu-cli.exe control --vmindex 0 launch` 均返回 `{"errcode": -503, "errmsg": "mainnx connect failed"}`），
  复核方式退化为源码核对 + 编译通过。
- 产物（合并后重新打包）：`SubsCheck-1.2.5-arm64-v8a.apk`（34,434,589 B，sha256 `e3600485…a1eb`）、
  `SubsCheck-1.2.5-armeabi-v7a.apk`（34,348,501 B，sha256 `99fa0afd…8fb2`），versionCode 8，
  aapt2 确认 versionName=1.2.5 / targetSdk 28 / native-code 各为 arm64-v8a 与 armeabi-v7a。

### 真机安装时的「开发者身份验证」提示（2026-11-11，仅文档）

用户真机装 1.2.4 时报「安装的时候弹出无开发者认证」，追问确认**可以安装、只是弹提示**。

- **先排除包的问题**：`apksigner verify --print-certs` 显示 1.2.3 与 1.2.4 证书 SHA-256 同为
  `d3af548e20c9dcb10da3097101383340e0412c98267df649c7b7e50402a0eb9b`，
  且 `apksigner verify --verbose` 为 **v2 方案 true、v1/v3/v3.1 false**（Flutter 默认配置，正常）。
- **提示来源**：Android 的开发者身份校验（Android Developer Verifier），2026-04 起作为系统服务下发，
  已内置进 Android 16 QPR2 / 16.1；它核对的是**包名是否绑定过已注册开发者身份**，
  与 APK 是否损坏、签名是否有效无关。Google 的执行日程：2026-09-30 起在
  巴西 / 印尼 / 新加坡 / 泰国的认证设备上执行首批限制，2027 年扩大到全球；
  参与计划的商店为 Google Play、HONOR、OPPO、三星、传音、vivo、小米。
  国内 ROM（HyperOS / MagicOS 等）另有各自的开发者身份验证规范，措辞相近但入口不同。
- **结论与对策**：本项目未注册包名，因此每次装新版本都会提示一次，属预期行为，
  用户当前选择「接受提示、直接继续安装」。
  彻底消除的两条路：① `adb install -r <apk>` —— 官方保留的开发/测试通道，不受 24 小时冷静期约束；
  ② 注册 limited distribution 账号（免费、上限 20 台设备、无需政府证件）后登记包名；
  full 验证需 25 美元 + 身份证明 + 上传签名公钥。
  系统侧的高级流程（开发者选项 → 「允许未验证的软件包」→ 输密码 → 重启 → **等满 24 小时** →
  再验证 → 选「暂时允许（7 天）」/「无限期允许」）可行但对普通用户太重，未写进 App 引导。
- **文档改动**：`README.md` 安装段新增提示块（说明提示属正常、如何用 SHA-256 自证包未被篡改、
  adb 安装可绕开），`dist/README.md` 同步；**未改代码、未发新版本**。

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
