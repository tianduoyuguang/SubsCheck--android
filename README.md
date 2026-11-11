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
| `SubsCheck-1.2.3-arm64-v8a.apk` | 2018 年之后绝大多数手机 | `b5603bda608ce256ae027b6ea3d5c8f9767aaff7166d7cffb6af1ae498c7e803` |
| `SubsCheck-1.2.3-armeabi-v7a.apk` | 老 32 位设备 | `dd75fd4aadc1021cd8ad82a83f2e5d33399d561620456d052819cf60736708fb` |

`minSdkVersion` = 24（Android 7.0），`targetSdkVersion` = 28，`versionName` = 1.2.3。

> APK 每次发版约 33 MB 且必然变化，提交进 Git 会让历史永久膨胀，
> 因此仓库只保留源码与校验文件 `dist/SHA256SUMS.txt`，二进制一律走 Release。

### 1.2.3 更新内容

- **修复「已经允许安装未知应用，App 仍说没授权」**：权限判断原来只信
  `PackageManager.canRequestPackageInstalls()`。本应用因内核要求把 `targetSdk` 锁在 28，
  这个 API 在部分系统上会和「安装未知应用」开关不同步 —— 用户明明开好了，它仍返回 false，
  界面于是永远停在未授权。现在改为先读系统的 AppOps 值（`android:request_install_packages`，
  也就是设置页真正写入的那一项），读不到才回落到原 API。
- **「我已允许，继续安装」不会再没反应**：原来它依赖内存里的「下载完成且待授权」标记，
  进程被回收或离开关于页再回来，标记就丢了，点了只弹一句「安装包已失效」。
  现在改为直接看缓存目录里是否还留着 apk；确实已经授权时，即便权限读取仍有偏差，
  也会把安装包交给系统安装器，由系统自己裁决并引导。
- 打开关于页时会自动还原「还差一步授权」的状态，不用重新下载。

### 1.2.2 更新内容

- **概览页的目录信息会跟随设置变化**：概览页原来那张「输出目录」卡片显示的是内核固定数据目录
  （`files/output`，用户根本改不了），改导出目录时页面毫无反应。现在拆成两行：
  - 「导出目录」显示当前导出位置，点击可直接切换（应用私有 / 手机 Download / 自定义目录）；
  - 「内核数据目录」保留原信息，只读展示。
- 导出目录弹窗（1.2.0 已监听应用状态）与概览页现在共用同一套刷新逻辑，切完目录两处同时更新。

### 1.2.1 更新内容

- **修复「更新下载完却装不上」**：应用此前没有声明 `REQUEST_INSTALL_PACKAGES`，Android 8.0+ 拉起系统安装器只会提示
  「没有安装权限」，且没有任何去授权的入口。现在：
  - 清单补上 `REQUEST_INSTALL_PACKAGES`；
  - 关于页检测到缺少权限时，进度条下方出现「允许安装未知应用」与「我已允许，继续安装」两项；
  - 点前者直达系统「安装未知应用」设置页（多级兜底，打不开会提示手动路径）；
  - 授权后**自动继续安装**，不用重新下载 —— 既监听 `Activity.onResume`，也用 1.2 秒一次的轮询兜底，
    覆盖「部分 ROM 把设置页开到另一个 display、本应用根本没被 pause」的情况；
  - 拉起安装器前等 2 秒，避免刚返回前台时被系统任务栈恢复动作顶掉安装器窗口。
- 下载完成的判定改为「先拉起安装器、再置完成标记」，Flutter 侧看到完成时权限状态必然已确定。

### 1.2.0 更新内容

- 新增 **导出目录可选**（设置 → 导出文件 → 导出目录）：
  - **应用私有目录**：`Android/data/com.subscheck.subscheck/files/exports/`，卸载即清理。
  - **手机 Download/SubsCheck**：走 MediaStore 写入公共下载目录，**无需任何存储权限**（Android 10+），
    卸载后文件保留，重复导出覆盖同名文件而不是生成 `xxx (1).yaml`。
  - **自定义目录**：调系统文件夹选择器（SAF）任选一个目录，授权持久化保存；可随时「清除自定义目录」。
- 修正导出目录弹窗不随选择即时刷新的问题（系统选择器返回后原地更新单选项与「当前导出到」）。
- 移除 `MANAGE_EXTERNAL_STORAGE` 等不再需要的存储权限声明。

### 1.1.0 更新内容

- 设置页新增 **免责声明**（软件性质 / 使用风险 / 数据与隐私 / 责任限制 / 开源许可）。
- 设置页新增 **关于**：版本信息、运行信息（包名、构建号、设备、ABI、SDK、API Key）、相关链接。
- 关于页支持 **检查更新**：读取 GitHub Release，按设备 ABI 自动选包，可直连或走镜像下载并调起安装器。
- 关于页可打开项目地址、内核地址、内核发布页、上游安卓部署说明与分流模板来源（失败回落为系统分享）。
- 修正内核版本号解析（新版内核 `/api/version` 返回 JSON）。

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
   - **完整 mihomo 配置**：proxies + proxy-groups + rule-providers + rules（内置 ACL4SSR 模板）
   - **仅节点**：只有 proxies
   导出位置由「设置 → 导出文件 → 导出目录」决定，默认 `Android/data/com.subscheck.subscheck/files/exports/`；
   可改成公共 `Download/SubsCheck` 或任意自选目录。导出后可直接分享给其他设备/clash 客户端。
5. 「设置」里可以：
   - 改监听地址与端口（默认 `127.0.0.1:8199`）
   - 直接编辑 `config.yaml`（订阅源、并发、超时、测速阈值等都在这里）
   - 查看 API Key（外部工具调内核 HTTP API 用，头名 `X-API-Key`）

### 内核 HTTP API

内核跑起来后监听 `127.0.0.1:8199`，除订阅导出外都只允许本机访问：

```
GET  /all.yaml /mihomo.yaml /base64.txt   ← 结果导出
GET  /sub/<file>                           ← 静态输出
GET  /export/:target                      ← 转换导出
POST /api/trigger-check                    ← 触发一轮检测（需 X-API-Key）
GET  /api/status /api/results /api/logs    ← 状态（需 X-API-Key）
```

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
