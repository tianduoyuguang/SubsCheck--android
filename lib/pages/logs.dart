import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../src/app_state.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key, required this.state});
  final AppState state;

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  String source = 'kernel';
  String serverLog = '';
  bool loading = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (source == 'server') _loadServer();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadServer() async {
    final api = widget.state.api;
    if (api == null) return;
    if (!loading) setState(() => loading = true);
    final text = await api.serverLogs();
    if (!mounted) return;
    setState(() {
      serverLog = text;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = source == 'kernel' ? widget.state.kernelLog : serverLog;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Row(
            children: <Widget>[
              SegmentedButton<String>(
                segments: const <ButtonSegment<String>>[
                  ButtonSegment<String>(value: 'kernel', label: Text('内核'), icon: Icon(Icons.terminal, size: 16)),
                  ButtonSegment<String>(value: 'server', label: Text('HTTP'), icon: Icon(Icons.http, size: 16)),
                ],
                selected: <String>{source},
                onSelectionChanged: (s) {
                  setState(() => source = s.first);
                  if (source == 'server') _loadServer();
                },
              ),
              const Spacer(),
              IconButton(
                tooltip: '复制',
                icon: const Icon(Icons.copy_all_outlined),
                onPressed: text.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: text));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制')));
                        }
                      },
              ),
              IconButton(
                tooltip: '刷新',
                icon: loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                onPressed: () {
                  if (source == 'server') {
                    _loadServer();
                  } else {
                    widget.state.refresh();
                  }
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: SingleChildScrollView(
              reverse: true,
              child: SelectableText(
                text.isEmpty ? '暂无日志' : text,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.35),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
