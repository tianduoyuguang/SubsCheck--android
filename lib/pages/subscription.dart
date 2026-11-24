import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../src/app_state.dart';
import '../src/export_dir.dart';
import '../src/exporter.dart';
import '../src/native.dart';

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key, required this.state});
  final AppState state;

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  int nodeCount = 0;
  String? lastPath;
  String? lastName;
  String? lastContent;
  bool busy = false;
  String? err;

  /// 上一次统计节点数时的检测时间戳；变化说明结果文件换了，要重新数。
  String _countedAt = '';
  bool _counting = false;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onStateChanged);
    _reloadCount();
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    final at = widget.state.checkedAt;
    if (at == _countedAt || _counting) return;
    _reloadCount();
  }

  Future<void> _reloadCount() async {
    final api = widget.state.api;
    if (api == null) return;
    _counting = true;
    try {
      final all = await api.allYaml();
      if (all == null) return;
      final n = Exporter.countProxies(Exporter.proxiesBlock(all));
      _countedAt = widget.state.checkedAt;
      if (mounted) setState(() => nodeCount = n);
    } finally {
      _counting = false;
    }
  }

  Future<void> _export({required bool full}) async {
    final api = widget.state.api;
    if (api == null) return;
    setState(() {
      busy = true;
      err = null;
    });
    try {
      final all = await api.allYaml();
      if (all == null || all.trim().isEmpty) {
        throw StateError('拿不到 /sub/all.yaml，请先运行内核并完成一轮检测');
      }
      final content = full ? await Exporter.buildMihomo(all) : Exporter.buildPlain(all);
      final name = full ? 'mihomo.yaml' : 'proxies.yaml';
      final r = await Native.saveExport(name, content);
      final path = (r['path'] ?? '') as String;
      widget.state.applyExportInfo(r);
      setState(() {
        lastPath = path;
        lastName = name;
        lastContent = content;
        nodeCount = Exporter.countProxies(Exporter.proxiesBlock(all));
      });
      // 导出只负责落盘，不自动弹系统分享面板：分享是单独的动作，
      // 由「已导出」卡片右侧的分享按钮触发（见 _share）。
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('已保存到 $path'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(label: '分享', onPressed: () => _share(name, content)),
      ));
    } catch (e) {
      setState(() => err = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// 拉系统「保存到…」对话框，由用户自己挑文件名和保存位置（Downloads、网盘等）。
  /// 这条路径不经过导出目录设置，也不会弹分享面板。
  Future<void> _saveAs({required bool full}) async {
    final api = widget.state.api;
    if (api == null) return;
    setState(() {
      busy = true;
      err = null;
    });
    try {
      final all = await api.allYaml();
      if (all == null || all.trim().isEmpty) {
        throw StateError('拿不到 /sub/all.yaml，请先运行内核并完成一轮检测');
      }
      final content = full ? await Exporter.buildMihomo(all) : Exporter.buildPlain(all);
      final name = full ? 'mihomo.yaml' : 'proxies.yaml';
      final r = await Native.saveExportAs(name, content);
      if (r['canceled'] == true) {
        setState(() => busy = false);
        return;
      }
      if (r['ok'] != true) {
        throw StateError((r['error'] ?? '保存失败') as String);
      }
      final path = (r['path'] ?? '') as String;
      setState(() {
        lastPath = path;
        lastName = name;
        lastContent = content;
        nodeCount = Exporter.countProxies(Exporter.proxiesBlock(all));
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('已保存到 $path'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(label: '分享', onPressed: () => _share(name, content)),
      ));
    } catch (e) {
      setState(() => err = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// 分享一份真实存在的副本（导出目录是 SAF 文档时原路径不可读）。
  Future<void> _share(String name, String content) async {
    try {
      final r = await Native.shareCopy(name, content);
      final real = (r['path'] ?? '') as String;
      if (real.isEmpty) return;
      if (!mounted) return;
      await Share.shareXFiles(<XFile>[XFile(real)], text: 'SubsCheck 导出 $name');
    } catch (e) {
      if (mounted) setState(() => err = '分享失败：$e');
    }
  }

  Future<void> _copyUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制链接')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
        animation: widget.state, builder: (context, _) => _body(context));
  }

  Widget _body(BuildContext context) {
    final base = widget.state.api?.baseUrl ?? 'http://127.0.0.1:${widget.state.port}';
    // 内核在 Sub-Store 关闭时只会写 all.yaml 这一个产物（kernel/save/save.go），
    // /all.txt 与 /mihomo.yaml 都依赖 Sub-Store，本 App 没有启用，
    // 所以这里只列真实存在的地址，免得用户复制过去是 404。
    final urls = <MapEntry<String, String>>[
      MapEntry<String, String>('节点列表 (all.yaml)', '$base/sub/all.yaml'),
    ];
    return RefreshIndicator(
      onRefresh: _reloadCount,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: <Widget>[
          Text('导出订阅', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('内核只产出 all.yaml（纯节点）。完整 mihomo 配置由 App 拼接内置 ACL4SSR 规则模板生成。',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.merge_type),
                  title: const Text('导出完整 mihomo 配置'),
                  subtitle: Text('节点 + 分流规则 + 规则集，可直接导入 Clash/Mihomo 客户端'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      IconButton(
                        icon: const Icon(Icons.save_alt),
                        tooltip: '另存为…',
                        onPressed: busy ? null : () => _saveAs(full: true),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  enabled: !busy,
                  onTap: () => _export(full: true),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.list_alt),
                  title: const Text('导出仅节点配置'),
                  subtitle: const Text('proxies 列表，用于导入到已有配置或订阅转换'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      IconButton(
                        icon: const Icon(Icons.save_alt),
                        tooltip: '另存为…',
                        onPressed: busy ? null : () => _saveAs(full: false),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  enabled: !busy,
                  onTap: () => _export(full: false),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.drive_file_move_outline),
                  title: const Text('导出自定义位置'),
                  subtitle: Text('当前：${widget.state.exportLabel}，点此可改到手机目录或自选文件夹'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await showExportDirSheet(context, widget.state);
                    if (mounted) setState(() {});
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: const Text('刷新节点数量'),
                  subtitle: Text('当前可导出 $nodeCount 个节点'),
                  trailing: busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync),
                  onTap: busy ? null : _reloadCount,
                ),
              ],
            ),
          ),
          if (err != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(err!),
              ),
            ),
          if (lastPath != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: const Text('已导出'),
                subtitle: SelectableText(lastPath!),
                trailing: IconButton(
                  icon: const Icon(Icons.share),
                  // 同样走临时副本：自定义目录下 lastPath 只是展示用的拼接路径。
                  onPressed: (lastName == null || lastContent == null)
                      ? null
                      : () => _share(lastName!, lastContent!),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text('本机订阅地址', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('在其他客户端里可直接填这些地址（仅本机 / 同一网络下可访问，取决于监听地址）。'
              '这是纯节点列表；需要带分流规则的完整配置或 Base64 订阅，请用上面的导出功能生成文件。',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: <Widget>[
                for (var i = 0; i < urls.length; i++) ...<Widget>[
                  ListTile(
                    dense: true,
                    title: Text(urls[i].key),
                    subtitle: SelectableText(urls[i].value, style: const TextStyle(fontSize: 12)),
                    trailing: IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () => _copyUrl(urls[i].value),
                    ),
                  ),
                  if (i != urls.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
