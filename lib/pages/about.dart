import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../src/app_state.dart';
import '../src/native.dart';
import '../src/updater.dart';
import '../src/urls.dart';

/// 「关于」页：版本信息、检查更新、项目/内核地址、开源许可。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key, required this.state});
  final AppState state;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  UpdateResult? _update;
  bool _checking = false;
  String _downloadMsg = '';
  double _progress = 0;
  bool _downloading = false;
  /// 包已下载完，只差系统「安装未知应用」授权。
  bool _needInstallPermission = false;
  Timer? _poll;

  /// 等待用户去系统设置授权期间的轮询。
  ///
  /// 不能只依赖 Activity.onResume：部分 ROM / 多显示器环境下系统设置页会在
  /// 另一个 display 上打开，本 App 的 Activity 根本没被 pause，也就收不到
  /// resume 回调。轮询权限状态对两种情况都成立。
  Timer? _permPoll;

  String get _currentVersion => (widget.state.info['versionName'] ?? '未知').toString();

  @override
  void initState() {
    super.initState();
    _check(silent: true);
    _restorePendingInstall();
  }

  /// 进程重建、或上次下载到一半离开页面时，内存里「还差授权」的标记会丢。
  /// 这里按缓存里的包和系统权限把状态还原出来，免得用户回来找不到继续安装的入口。
  Future<void> _restorePendingInstall() async {
    final s = await Native.installState();
    if (!mounted) return;
    if (s['hasCached'] == true && s['allowed'] != true) {
      setState(() {
        _needInstallPermission = true;
        _downloadMsg = '安装包已下载，还需允许「安装未知应用」';
      });
      _startPermWatch();
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _permPoll?.cancel();
    super.dispose();
  }

  /// 卡在「安装未知应用」授权上时，反复问一次系统当前是否已允许。
  ///
  /// 一旦允许就自动续装，用户不需要回来再点「我已允许，继续安装」。
  void _startPermWatch() {
    if (_permPoll != null) return;
    _permPoll = Timer.periodic(const Duration(milliseconds: 1200), (_) async {
      final allowed = await Native.installAllowed();
      if (!mounted) {
        _permPoll?.cancel();
        _permPoll = null;
        return;
      }
      if (!allowed) return;
      _permPoll?.cancel();
      _permPoll = null;
      // 等一拍再拉起安装器。刚从系统设置返回时，系统会把本 App 的任务栈
      // 重新置于前台；若此时立刻 startActivity，安装器会先弹出来又被压到
      // 后面，用户看到的还是 App 自己的页面（模拟器 logcat 实测差 1.5s）。
      await Future<void>.delayed(const Duration(milliseconds: 2000));
      if (!mounted) return;
      if (_needInstallPermission) await _installNow();
    });
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking) return;
    setState(() => _checking = true);
    final r = await UpdateChecker.check(
      repo: 'tianduoyuguang/SubsCheck--android',
      currentVersion: _currentVersion,
    );
    if (!mounted) return;
    setState(() {
      _update = r;
      _checking = false;
    });
    if (!silent) {
      if (!r.ok) {
        _toast('检查失败：${r.error ?? '未知错误'}');
      } else if (r.hasUpdate) {
        _toast('发现新版本 ${r.latestVersion}');
      } else {
        _toast('已是最新版本');
      }
    }
  }

  Future<void> _open(String url) async {
    final ok = await Native.openUrl(url);
    if (!ok && mounted) _toast('没有找到可用的浏览器');
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    _toast('已复制$label');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _startDownload(UpdateAsset asset) async {
    if (_downloading) return;
    final url = mirrorUrl(asset.downloadUrl);
    final r = await Native.startDownload(url, asset.name);
    if (!mounted) return;
    if (r['downloading'] != true && r['done'] != true) {
      _toast('下载启动失败：${r['error'] ?? '未知原因'}');
      return;
    }
    _permPoll?.cancel();
    _permPoll = null;
    setState(() {
      _downloading = true;
      _needInstallPermission = false;
      _progress = 0;
      _downloadMsg = '正在下载 ${asset.name}';
    });
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 600), (_) => _tickDownload());
  }

  Future<void> _tickDownload() async {
    final s = await Native.downloadStatus();
    if (!mounted) return;
    final done = s['done'] == true;
    final downloading = s['downloading'] == true;
    final err = s['error'];
    setState(() {
      _progress = ((s['percent'] is int) ? s['percent'] as int : 0) / 100.0;
      final received = (s['received'] is int) ? s['received'] as int : 0;
      if (downloading) {
        _downloadMsg = '正在下载 ${(received / 1048576).toStringAsFixed(1)} MB';
      }
    });
    final needPerm = s['needPermission'] == true;
    if (done && needPerm) {
      // 装完系统才允许安装：不再轮询下载进度，改成等用户去授权。
      _poll?.cancel();
      setState(() {
        _downloading = false;
        _needInstallPermission = true;
        _progress = 1;
        _downloadMsg = '安装包已下载，还需允许「安装未知应用」';
      });
      _startPermWatch();
    } else if (done) {
      _poll?.cancel();
      setState(() {
        _downloading = false;
        _needInstallPermission = false;
        _downloadMsg = '下载完成，请在弹出的安装器中确认';
      });
      _toast('下载完成');
    } else if (err != null && !downloading) {
      _poll?.cancel();
      setState(() {
        _downloading = false;
        _downloadMsg = '下载失败：$err';
      });
    }
  }

  /// 跳到系统「安装未知应用」页。授权后系统会回到 App，onResume 里会自动续装；
  /// 若用户其实已经开好了开关，这里直接续装。
  Future<void> _grantInstallPermission() async {
    final r = await Native.requestInstallPermission();
    if (!mounted) return;
    if (r['allowed'] == true) {
      await _installNow();
      return;
    }
    if (r['ok'] != true) {
      _toast('没找到系统设置页，请到「设置 → 应用 → 特殊权限 → 安装未知应用」里手动允许');
      return;
    }
    _toast('已打开系统授权页，允许后返回会自动继续安装');
    _startPermWatch();
  }

  /// 拉起安装器。
  ///
  /// 先按正常路径走（续装上次卡住的、或安装缓存里的包）；失败时不再相信
  /// 自己读到的权限值——部分 ROM 上它和系统开关就是不同步，用户明明授权好了
  /// 依然收到「还没有允许」。此时直接把包丢给系统安装器，由系统自己裁决并引导，
  /// 这样点下去至少总有一个结果。
  Future<void> _installNow() async {
    var r = await Native.installNow();
    if (!mounted) return;
    if (r['relaunched'] != true) {
      r = await Native.installForce();
      if (!mounted) return;
    }
    _permPoll?.cancel();
    _permPoll = null;
    if (r['relaunched'] == true) {
      setState(() {
        _needInstallPermission = false;
        _downloadMsg = '已拉起安装器，请确认安装';
      });
      return;
    }
    setState(() => _needInstallPermission = false);
    _toast('安装包已不在，请重新下载');
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.state.info;
    final abi = (info['abi'] ?? '-').toString();
    final u = _update;
    final asset = u == null ? null : pickAssetFor(u.assets, abi);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        children: <Widget>[
          // 版本卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
              child: Column(
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.asset('assets/icon.png', width: 72, height: 72),
                  ),
                  const SizedBox(height: 10),
                  Text('SubsCheck for Android', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text('v$_currentVersion',
                      style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('内核 ${widget.state.kernelVersion.isEmpty ? '未知' : widget.state.kernelVersion}  ·  $abi',
                      style: TextStyle(fontSize: 12, color: scheme.outline)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 检查更新
          Card(
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.system_update_alt),
                  title: const Text('检查更新'),
                  subtitle: Text(_subtitleForUpdate(u)),
                  trailing: _checking
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                  onTap: _checking ? null : () => _check(),
                ),
                if (_downloading) ...<Widget>[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        LinearProgressIndicator(value: _progress == 0 ? null : _progress),
                        const SizedBox(height: 6),
                        Text(_downloadMsg, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ],
                // 包已下载完，只差系统「安装未知应用」授权：给出直达入口，
                // 不再让用户面对一句「没有安装权限」不知所措。
                if (_needInstallPermission && !_downloading) ...<Widget>[
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.shield_outlined, color: scheme.error),
                    title: const Text('允许安装未知应用'),
                    subtitle: const Text('系统要求手动开启一次；返回本应用后会自动继续安装'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _grantInstallPermission,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.refresh),
                    title: const Text('我已允许，继续安装'),
                    onTap: _installNow,
                  ),
                ],
                if (u != null && u.ok && u.hasUpdate && asset != null) ...<Widget>[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.download),
                    title: Text('下载 ${asset.name}${asset.sizeText.isEmpty ? '' : '（${asset.sizeText}）'}'),
                    subtitle: const Text('走 gh-proxy 镜像下载，完成后自动唤起安装器'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _downloading ? null : () => _startDownload(asset),
                  ),
                ],
                if (u != null && u.ok && u.hasUpdate && u.htmlUrl != null && u.htmlUrl!.isNotEmpty) ...<Widget>[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.open_in_new),
                    title: const Text('在浏览器中查看该版本'),
                    subtitle: Text(u.tagName ?? ''),
                    onTap: () => _open(u.htmlUrl!),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 链接
          Text('相关链接', style: Theme.of(context).textTheme.titleMedium),
          Card(
            child: Column(
              children: <Widget>[
                _linkTile(Icons.code, '项目地址', AppLinks.project, '本安卓移植版的开源仓库'),
                const Divider(height: 1),
                _linkTile(Icons.memory, '内核地址', AppLinks.kernel, '上游 SubsCheck（beck-8）'),
                const Divider(height: 1),
                _linkTile(Icons.system_update, '内核发布页', AppLinks.kernelReleases, '上游官方 Windows / macOS / Linux 版本'),
                const Divider(height: 1),
                _linkTile(Icons.menu_book_outlined, '上游安卓部署说明', AppLinks.kernelAndroidDoc, 'Termux + proot 方案，与本应用实现不同'),
                const Divider(height: 1),
                _linkTile(Icons.route_outlined, '分流模板来源', AppLinks.acl4ssr, '内置 ACL4SSR_Online_Full.yaml'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 运行信息
          Text('运行信息', style: Theme.of(context).textTheme.titleMedium),
          Card(
            child: Column(
              children: <Widget>[
                _infoTile('包名', (info['packageName'] ?? '-').toString()),
                const Divider(height: 1),
                _infoTile('构建号', (info['versionCode'] ?? '-').toString()),
                const Divider(height: 1),
                _infoTile('设备', (info['device'] ?? '-').toString()),
                const Divider(height: 1),
                _infoTile('ABI', abi),
                const Divider(height: 1),
                _infoTile('Android SDK', (info['sdk'] ?? '-').toString()),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: const Text('本机 API Key'),
                  subtitle: SelectableText(widget.state.apiKey, style: const TextStyle(fontSize: 12)),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () => _copy(widget.state.apiKey, ' API Key'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 许可
          Text('许可', style: Theme.of(context).textTheme.titleMedium),
          Card(
            child: Column(
              children: <Widget>[
                _linkTile(Icons.gavel_outlined, 'GNU GPL v3', AppLinks.license, '本应用与内置内核的许可证'),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('第三方组件'),
                  subtitle: const Text('Flutter、yaml、http、share_plus、cupertino_icons'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'SubsCheck for Android',
                    applicationVersion: _currentVersion,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Center(
            child: Text('本程序按 GPLv3 发布，不提供任何担保',
                style: TextStyle(fontSize: 11, color: scheme.outline)),
          ),
        ],
      ),
    );
  }

  String _subtitleForUpdate(UpdateResult? u) {
    if (_checking) return '正在连接 GitHub ...';
    if (u == null) return '尚未检查';
    if (!u.ok) return '检查失败：${u.error ?? '未知错误'}（可稍后重试）';
    if (u.hasUpdate) {
      return '发现新版本 ${u.latestVersion}（当前 v$_currentVersion）';
    }
    return '已是最新版本（v$_currentVersion）${u.source == null ? '' : ' · 通过 ${u.source} 获取'}';
  }

  Widget _linkTile(IconData icon, String title, String url, String subtitle) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text('$subtitle\n$url', style: const TextStyle(fontSize: 11.5, height: 1.4)),
      isThreeLine: true,
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: () => _open(url),
      onLongPress: () => _copy(url, '链接'),
    );
  }

  Widget _infoTile(String label, String value) {
    return ListTile(
      dense: true,
      title: Text(label, style: const TextStyle(fontSize: 13)),
      trailing: SelectableText(value, style: const TextStyle(fontSize: 12)),
    );
  }
}
