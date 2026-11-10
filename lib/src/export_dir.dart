import 'package:flutter/material.dart';

import 'app_state.dart';
import 'native.dart';

/// 导出目录设置：应用私有目录 / 手机 Download/SubsCheck / SAF 自选目录。
/// 选择即时生效并持久化，下次导出直接写到该目录。
Future<void> showExportDirSheet(BuildContext context, AppState state) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext ctx) => _ExportDirSheet(state: state),
  );
}

class _ExportDirSheet extends StatefulWidget {
  const _ExportDirSheet({required this.state});
  final AppState state;

  @override
  State<_ExportDirSheet> createState() => _ExportDirSheetState();
}

class _ExportDirSheetState extends State<_ExportDirSheet> {
  bool _busy = false;

  AppState get s => widget.state;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _choose(String mode) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (mode == 'custom') {
        // 拉起系统文件夹选择器；选完 Kotlin 侧会主动回推 exportDirChanged。
        await Native.pickExportDir();
        if (!mounted) return;
        _toast('请在系统文件选择器里挑一个目录');
      } else {
        final r = await Native.setExportMode(mode);
        s.applyExportInfo(r);
        if (mode == 'download' && r['exportNeedsPermission'] == true) {
          _toast('需要存储权限，请在系统授权框里允许');
        }
      }
    } catch (e) {
      _toast('切换失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetCustom() async {
    setState(() => _busy = true);
    try {
      final r = await Native.clearExportTree();
      s.applyExportInfo(r);
      _toast('已清除自定义目录，改回应用私有目录');
    } catch (e) {
      _toast('操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _tile({
    required String value,
    required IconData icon,
    required String title,
    required String subtitle,
    bool error = false,
    bool mono = true,
  }) {
    final theme = Theme.of(context);
    return RadioListTile<String>(
      value: value,
      title: Text(title),
      secondary: Icon(icon),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 11,
          fontFamily: mono ? 'monospace' : null,
          color: error ? theme.colorScheme.error : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // AppState 是 ChangeNotifier：SAF 选完目录由 Kotlin 侧回推 exportDirChanged，
    // 只有监听它，弹窗内的单选项与「当前导出到」才会即时刷新。
    return ListenableBuilder(
      listenable: s,
      builder: (BuildContext context, Widget? _) => _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final info = s.info;
    final mode = (info['exportMode'] ?? 'private').toString();
    final hasTree = info['exportHasTree'] == true;
    final needsPerm = info['exportNeedsPermission'] == true;
    final current = (info['exportPath'] ?? '').toString();
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('导出目录', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('「导出完整 mihomo 配置 / 仅节点配置」会写到这里；选择会记住，随时可改。',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: mode,
              onChanged: (String? v) {
                if (v != null && !_busy) _choose(v);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _tile(
                    value: 'private',
                    icon: Icons.lock_outline,
                    title: '应用私有目录',
                    subtitle: (info['exportPrivatePath'] ?? '').toString(),
                  ),
                  _tile(
                    value: 'download',
                    icon: Icons.download_outlined,
                    title: '手机 Download/SubsCheck',
                    subtitle: needsPerm
                        ? '需要授予存储权限后才能写入'
                        : (info['exportDownloadPath'] ?? '').toString(),
                    error: needsPerm,
                  ),
                  _tile(
                    value: 'custom',
                    icon: Icons.drive_file_move_outline,
                    title: '自定义目录',
                    subtitle: mode == 'custom'
                        ? current
                        : (hasTree ? '已记住上次选择的目录，点此再次选择' : '用系统文件夹选择器挑一个目录'),
                    mono: mode == 'custom',
                  ),
                ],
              ),
            ),
            if (mode == 'custom' || hasTree)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _busy ? null : _resetCustom,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('清除自定义目录'),
                ),
              ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('当前导出到', style: theme.textTheme.labelSmall),
                  const SizedBox(height: 2),
                  SelectableText(current,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '提示：应用私有目录在卸载后会被系统清理；放到 Download 目录或自定义目录则卸载后仍保留。',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
