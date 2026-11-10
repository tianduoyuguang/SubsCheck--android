import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../src/app_state.dart';
import '../src/disclaimer.dart';
import '../src/export_dir.dart';
import '../src/native.dart';
import 'about.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.state});
  final AppState state;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _host;
  late final TextEditingController _port;
  bool _notifyGranted = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _host = TextEditingController(text: widget.state.host);
    _port = TextEditingController(text: widget.state.port.toString());
    Native.hasNotificationPermission().then((v) {
      if (mounted) setState(() => _notifyGranted = v);
    });
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _applyAddress() async {
    final p = int.tryParse(_port.text.trim());
    if (p == null || p < 1024 || p > 65535) {
      _toast('端口需在 1024 - 65535 之间');
      return;
    }
    setState(() => _saving = true);
    try {
      await Native.setHost(_host.text.trim());
      await Native.setPort(p);
      await widget.state.initialize();
      if (mounted) {
        _host.text = widget.state.host;
        _port.text = widget.state.port.toString();
      }
      _toast('已保存监听地址，重启内核后生效');
    } catch (e) {
      _toast('保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editConfig() async {
    final text = await widget.state.readConfig();
    if (!mounted || text == null) return;
    final controller = TextEditingController(text: text);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑 config.yaml'),
        content: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: TextField(
            controller: controller,
            maxLines: null,
            expands: true,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok == true) {
      final saved = await widget.state.writeConfig(controller.text);
      _toast(saved ? '已保存，重启内核后生效' : '保存失败');
      if (saved) await widget.state.restartKernel();
    }
    controller.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openAbout() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AboutPage(state: widget.state)),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.state.info;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: <Widget>[
        Text('内核', style: Theme.of(context).textTheme.titleMedium),
        Card(
          child: Column(
            children: <Widget>[
              ListTile(
                leading: Icon(widget.state.kernelRunning ? Icons.play_circle : Icons.stop_circle,
                    color: widget.state.kernelRunning ? Colors.green : null),
                title: Text(widget.state.kernelRunning ? '内核运行中' : '内核已停止'),
                subtitle: Text('PID ${info['pid'] ?? '-'}  ·  ${info['abi'] ?? '-'}  ·  SDK ${info['sdk'] ?? '-'}'),
                trailing: Switch(
                  value: widget.state.kernelRunning,
                  onChanged: widget.state.busy
                      ? null
                      : (v) async {
                          if (v) {
                            await widget.state.startKernel();
                          } else {
                            await widget.state.stopKernel();
                          }
                        },
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.restart_alt),
                title: const Text('重启内核'),
                subtitle: const Text('修改配置后需要重启生效'),
                onTap: widget.state.busy ? null : () => widget.state.restartKernel(),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined),
                title: const Text('清空检测结果'),
                subtitle: const Text('删除 output 目录下的产物与缓存'),
                onTap: () async {
                  await widget.state.clearResults();
                  await widget.state.refresh();
                  _toast('已清空');
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('监听地址', style: Theme.of(context).textTheme.titleMedium),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _host,
                        decoration: const InputDecoration(
                          labelText: '监听地址',
                          helperText: '127.0.0.1 仅本机；0.0.0.0 局域网可访问',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _port,
                        keyboardType: TextInputType.number,
                        inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(labelText: '端口', isDense: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: _saving ? null : _applyAddress,
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text('保存'),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () {
                        _host.text = '127.0.0.1';
                        _port.text = '8199';
                      },
                      icon: const Icon(Icons.settings_backup_restore, size: 18),
                      label: const Text('恢复默认'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('导出文件', style: Theme.of(context).textTheme.titleMedium),
        Card(
          child: ListTile(
            leading: const Icon(Icons.save_alt),
            title: const Text('导出目录'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(widget.state.exportLabel,
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 2),
                SelectableText(widget.state.exportPath, style: const TextStyle(fontSize: 11)),
              ],
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await showExportDirSheet(context, widget.state);
              if (mounted) setState(() {});
            },
          ),
        ),
        const SizedBox(height: 16),
        Text('通知与后台', style: Theme.of(context).textTheme.titleMedium),
        Card(
          child: Column(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: const Text('通知权限'),
                subtitle: Text(_notifyGranted ? '已授权，内核运行时显示前台通知' : '未授权，内核可能被系统回收'),
                trailing: _notifyGranted
                    ? const Icon(Icons.check, color: Colors.green)
                    : TextButton(
                        onPressed: () async {
                          final ok = await Native.requestNotificationPermission();
                          if (mounted) setState(() => _notifyGranted = ok);
                          if (!ok) _toast('请在系统设置中手动授权通知');
                        },
                        child: const Text('去授权'),
                      ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.battery_saver_outlined),
                title: const Text('忽略电池优化'),
                subtitle: const Text('建议在系统设置里把本应用加入白名单，避免后台被杀'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('高级', style: Theme.of(context).textTheme.titleMedium),
        Card(
          child: Column(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.code),
                title: const Text('编辑配置文件'),
                subtitle: SelectableText(widget.state.configPath, style: const TextStyle(fontSize: 11)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _editConfig,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: const Text('API Key'),
                subtitle: SelectableText(widget.state.apiKey, style: const TextStyle(fontSize: 12)),
                trailing: IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: widget.state.apiKey));
                    _toast('已复制 API Key');
                  },
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.storage_outlined),
                title: const Text('内核二进制'),
                subtitle: SelectableText((info['nativeLibraryDir'] ?? '').toString(), style: const TextStyle(fontSize: 11)),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('工作目录'),
                subtitle: SelectableText((info['filesDir'] ?? '').toString(), style: const TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('关于', style: Theme.of(context).textTheme.titleMedium),
        Card(
          child: Column(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('关于 SubsCheck'),
                subtitle: Text(
                    'v${info['versionName'] ?? '未知'}  ·  内核 ${widget.state.kernelVersion.isEmpty ? '未知' : widget.state.kernelVersion}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openAbout,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.report_gmailerrorred_outlined),
                title: const Text('免责声明'),
                subtitle: const Text('使用风险、数据说明与责任限制'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showDisclaimerDialog(context),
              ),
              const Divider(height: 1),
              const ListTile(
                leading: Icon(Icons.gavel_outlined),
                title: Text('开源协议'),
                subtitle: Text('本项目及内置内核遵循 GNU GPL v3，源码随发布提供'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
