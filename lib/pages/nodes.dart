import 'package:flutter/material.dart';

import '../src/app_state.dart';
import '../src/models.dart';

class NodesPage extends StatefulWidget {
  const NodesPage({super.key, required this.state});
  final AppState state;

  @override
  State<NodesPage> createState() => _NodesPageState();
}

class _NodesPageState extends State<NodesPage> {
  String query = '';
  bool onlyAlive = false;
  String sortBy = 'speed';

  List<NodeItem> _filtered() {
    var list = widget.state.nodes;
    if (onlyAlive) list = list.where((n) => n.speed > 0).toList();
    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      list = list.where((n) =>
          n.name.toLowerCase().contains(q) ||
          n.server.toLowerCase().contains(q) ||
          n.type.toLowerCase().contains(q)).toList();
    }
    final copy = List<NodeItem>.from(list);
    if (sortBy == 'speed') {
      copy.sort((a, b) => b.speed.compareTo(a.speed));
    } else if (sortBy == 'name') {
      copy.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return copy;
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered();
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    hintText: '搜索节点 / 服务器 / 协议',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: (v) => setState(() => query = v.trim()),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '只看有速度的节点',
                isSelected: onlyAlive,
                icon: const Icon(Icons.filter_alt_outlined),
                selectedIcon: const Icon(Icons.filter_alt),
                onPressed: () => setState(() => onlyAlive = !onlyAlive),
              ),
              PopupMenuButton<String>(
                tooltip: '排序',
                initialValue: sortBy,
                onSelected: (v) => setState(() => sortBy = v),
                itemBuilder: (_) => const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(value: 'speed', child: Text('按速度')),
                  PopupMenuItem<String>(value: 'name', child: Text('按名称')),
                  PopupMenuItem<String>(value: 'origin', child: Text('按原序')),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: <Widget>[
              Text('共 ${widget.state.nodes.length} 个节点，显示 ${items.length}',
                  style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              if (widget.state.checkedAt.isNotEmpty)
                Text(widget.state.checkedAt.replaceFirst('T', ' ').split('.').first,
                    style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.inbox_outlined, size: 48),
                      const SizedBox(height: 8),
                      Text(
                        !widget.state.kernelRunning
                            ? '内核未运行'
                            : (widget.state.status.checking ? '检测进行中，稍后自动刷新' : '还没有检测结果，点「概览 → 立即检测一轮」'),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => widget.state.refresh(),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('刷新结果'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => widget.state.refresh(),
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 24, top: 4),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final n = items[i];
                      return ListTile(
                        dense: true,
                        title: Text(n.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${n.type.toUpperCase()}  ·  ${n.server}:${n.port}${n.network.isNotEmpty ? '  ·  ${n.network}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: <Widget>[
                            Text(n.speedText,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: n.speed > 0 ? Colors.green : Theme.of(context).hintColor,
                                )),
                            if (n.media.isNotEmpty)
                              Text(n.media.join(' '), style: const TextStyle(fontSize: 10)),
                          ],
                        ),
                        onTap: () => _showDetail(context, n),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  void _showDetail(BuildContext context, NodeItem n) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        Widget row(String k, String v) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                SizedBox(width: 96, child: Text(k, style: Theme.of(ctx).textTheme.bodySmall)),
                Expanded(child: SelectableText(v)),
              ]),
            );
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(n.name, style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 10),
              row('协议', n.type),
              row('服务器', n.server),
              row('端口', n.port),
              if (n.sni.isNotEmpty) row('SNI', n.sni),
              row('传输', n.network.isEmpty ? '-' : n.network),
              row('TLS', n.tls ? '是' : '否'),
              if (n.reality) row('Reality', '是'),
              row('UDP', n.udp ? '支持' : '不支持'),
              row('速度', n.speedText),
              if (n.country.isNotEmpty) row('地区', n.country),
              if (n.ip.isNotEmpty) row('IP', n.ip),
              if (n.ipRisk.isNotEmpty) row('IP 风险', n.ipRisk),
              if (n.media.isNotEmpty) row('解锁', n.media.join(', ')),
              if (n.subTag.isNotEmpty) row('订阅', n.subTag),
            ],
          ),
        );
      },
    );
  }
}
