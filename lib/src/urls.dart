/// 外部链接与版本常量 centralized，避免各页面散落硬编码。
class AppLinks {
  /// 本 App（Flutter 移植版）源码仓库。
  static const String project = 'https://github.com/tianduoyuguang/SubsCheck--android';

  /// 本 App 的 release 列表，用于「检查更新」和下载页。
  static const String releases = 'https://github.com/tianduoyuguang/SubsCheck--android/releases';

  /// 最新 release 的 GitHub API（直连，不走网页）。
  static const String latestReleaseApi =
      'https://api.github.com/repos/tianduoyuguang/SubsCheck--android/releases/latest';

  /// 内核上游：SubsCheck（beck-8）。
  static const String kernel = 'https://github.com/beck-8/subs-check';

  /// 内核上游 release 页（含 Windows/macOS/Linux 官方包）。
  static const String kernelReleases = 'https://github.com/beck-8/subs-check/releases';

  /// 内核作者发布的安卓部署说明（Termux + proot 方案）。
  static const String kernelAndroidDoc = 'https://github.com/beck-8/subs-check/blob/main/doc/android.md';

  /// 本项目遵循的许可证。
  static const String license = 'https://www.gnu.org/licenses/gpl-3.0.html';

  /// 内置 ACL4SSR 分流模板来源。
  static const String acl4ssr = 'https://github.com/ACL4SSR/ACL4SSR';
}
