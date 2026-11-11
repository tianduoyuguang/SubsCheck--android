import 'package:flutter/material.dart';

import '../src/app_state.dart';
import '../src/export_dir.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key, required this.state});
  final AppState state;

  Widget _statCard(BuildContext context, String label, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(children: <Widget>[
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
            ]),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = state.status;
    return RefreshIndicator(
      onRefresh: () => state.refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text('SubsCheck', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: state.kernelRunning ? Colors.green.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  Icon(Icons.circle, size: 9, color: state.kernelRunning ? Colors.green : Colors.red),
                  const SizedBox(width: 6),
                  Text(state.kernelRunning ? '内核运行中' : '内核已停止', style: const TextStyle(fontSize: 12)),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '端口 ${state.port}  ·  ${state.info['abi'] ?? '-'}  ·  SDK ${state.info['sdk'] ?? '-'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (!state.kernelRunning)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.warning_amber_rounded),
                title: const Text('内核未运行'),
                subtitle: Text(state.error ?? '点击下方按钮启动内核'),
              ),
            ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.9,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: <Widget>[
              _statCard(context, '节点总数', st.proxyCount.toString(), Icons.cloud_outlined, Colors.blue),
              _statCard(context, '可用节点', st.available.toString(), Icons.check_circle_outline, Colors.green),
              _statCard(context, '已测活', st.aliveDone.toString(), Icons.network_check, Colors.orange),
              _statCard(context, '已测速', st.speedDone.toString(), Icons.speed, Colors.purple),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(children: <Widget>[
                    Text(st.checking ? '检测进行中' : '空闲', style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    if (st.checking) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ]),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: st.aliveRatio.clamp(0.0, 1.0)),
                  const SizedBox(height: 6),
                  Text('测活进度 ${st.aliveDone}/${st.proxyCount}', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 10),
                  if (st.hasSpeedTest) ...<Widget>[
                    LinearProgressIndicator(value: st.speedRatio.clamp(0.0, 1.0)),
                    const SizedBox(height: 6),
                    Text('测速进度 ${st.speedDone}/${st.proxyCount}', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: Icon(state.kernelRunning ? Icons.stop_circle_outlined : Icons.play_circle_outline),
                  title: Text(state.kernelRunning ? '停止内核' : '启动内核'),
                  subtitle: Text(state.kernelRunning ? '停止后不再自动检测' : '启动本地检测服务'),
                  trailing: state.busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
                  onTap: state.busy ? null : () { state.kernelRunning ? state.stopKernel() : state.startKernel(); },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: const Text('重启内核'),
                  subtitle: const Text('修改配置后需要重启生效'),
                  onTap: state.busy ? null : () => state.restartKernel(),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.play_arrow),
                  title: const Text('立即检测一轮'),
                  subtitle: const Text('拉取订阅源并开始测活/测速'),
                  enabled: state.kernelRunning,
                  onTap: () async {
                    await state.triggerCheck();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已触发检测')));
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cancel_outlined),
                  title: const Text('强制中止检测'),
                  enabled: state.kernelRunning,
                  onTap: () => state.forceClose(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('导出目录'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(state.exportLabel, style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 2),
                      Text(state.exportPath, style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showExportDirSheet(context, state),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.storage_outlined),
                  title: const Text('内核数据目录'),
                  subtitle: Text(state.outputDir, style: Theme.of(context).textTheme.bodySmall),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
