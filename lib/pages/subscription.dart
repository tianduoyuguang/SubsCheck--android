import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../src/app_state.dart';
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
  bool busy = false;
  String? err;

  @override
  void initState() {
    super.initState();
    _reloadCount();
  }

  Future<void> _reloadCount() async {
    final api = widget.state.api;
    if (api == null) return;
    final all = await api.allYaml();
    if (all == null) return;
    final n = Exporter.countProxies(Exporter.proxiesBlock(all));
    if (mounted) setState(() => nodeCount = n);
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
        nodeCount = Exporter.countProxies(Exporter.proxiesBlock(all));
      });
      if (!mounted) return;
      await Share.shareXFiles(<XFile>[XFile(path)], text: 'SubsCheck 导出 $name');
    } catch (e) {
      setState(() => err = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
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
    final base = widget.state.api?.baseUrl ?? 'http://127.0.0.1:${widget.state.port}';
    final urls = <MapEntry<String, String>>[
      MapEntry<String, String>('节点列表 (all.yaml)', '$base/sub/all.yaml'),
      MapEntry<String, String>('Base64 订阅 (all.txt)', '$base/sub/all.txt'),
      MapEntry<String, String>('规则模板 (ACL4SSR)', '$base/all.yaml'),
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
                  trailing: const Icon(Icons.chevron_right),
                  enabled: !busy,
                  onTap: () => _export(full: true),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.list_alt),
                  title: const Text('导出仅节点配置'),
                  subtitle: const Text('proxies 列表，用于导入到已有配置或订阅转换'),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: !busy,
                  onTap: () => _export(full: false),
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
                  onPressed: () => Share.shareXFiles(<XFile>[XFile(lastPath!)]),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text('本机订阅地址', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('在其他客户端里可直接填这些地址（仅本机 / 同一网络下可访问，取决于监听地址）。',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: <Widget>[
                for (final e in urls) ...<Widget>[
                  ListTile(
                    dense: true,
                    title: Text(e.key),
                    subtitle: SelectableText(e.value, style: const TextStyle(fontSize: 12)),
                    trailing: IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () => _copyUrl(e.value),
                    ),
                  ),
                  const Divider(height: 1),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('导出文件位置'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(widget.state.exportLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  SelectableText(widget.state.exportPath, style: const TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
