import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'models.dart';
import 'native.dart';

class AppState extends ChangeNotifier {
  bool ready = false;
  bool busy = false;
  String? error;

  Map<String, dynamic> info = <String, dynamic>{};
  KernelApi? api;
  KernelStatus status = KernelStatus.empty;
  List<NodeItem> nodes = <NodeItem>[];
  String kernelLog = '';
  String checkedAt = '';
  String kernelVersion = '';
  bool kernelRunning = false;
  DateTime? lastRefresh;

  Timer? _poll;

  int get port => (info['port'] is int) ? info['port'] as int : 8199;
  String get host => (info['host'] ?? '127.0.0.1') as String;
  String get apiKey => (info['apiKey'] ?? '') as String;
  String get configPath => (info['configPath'] ?? '') as String;
  String get outputDir => (info['outputDir'] ?? '') as String;

  /// App 导出文件当前写到哪（用户可在设置里改）。
  String get exportPath => (info['exportPath'] ?? '') as String;
  String get exportLabel => (info['exportLabel'] ?? '应用私有目录') as String;

  /// 目录选择完成后（Kotlin 回推 / 用户点选）刷新本机信息。
  void applyExportInfo(Map<String, dynamic> patch) {
    if (patch.isEmpty) return;
    info = <String, dynamic>{...info, ...patch};
    notifyListeners();
  }

  Future<void> initialize() async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final template = await rootBundle.loadString('assets/config_template.yaml');
      final prepared = await Native.prepare(template);
      info = prepared;
      api = KernelApi(
        host: (prepared['host'] ?? '127.0.0.1') as String,
        port: (prepared['port'] is int) ? prepared['port'] as int : 8199,
        apiKey: (prepared['apiKey'] ?? '') as String,
      );
      kernelRunning = prepared['running'] == true;
      // 系统文件夹选择器返回后由 Kotlin 主动回推，避免 Dart 侧轮询等结果。
      Native.bindExportDirEvents(applyExportInfo);
      ready = true;
      _startPolling();
      await refresh();
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> startKernel() async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final r = await Native.start();
      info = <String, dynamic>{...info, ...r};
      kernelRunning = r['running'] == true;
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      await refresh();
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> stopKernel() async {
    busy = true;
    notifyListeners();
    try {
      final r = await Native.stop();
      info = <String, dynamic>{...info, ...r};
      kernelRunning = false;
      kernelVersion = '';
      status = KernelStatus.empty;
      notifyListeners();
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> restartKernel() async {
    busy = true;
    notifyListeners();
    try {
      final r = await Native.restart();
      info = <String, dynamic>{...info, ...r};
      kernelRunning = r['running'] == true;
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      await refresh();
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => refresh(silent: true));
  }

  Future<void> refresh({bool silent = false}) async {
    final a = api;
    if (a == null) return;
    try {
      final st = await Native.status();
      kernelRunning = st['running'] == true;
      final s = await a.status();
      final wasChecking = status.checking;
      if (s != null) {
        status = KernelStatus.fromJson(s);
      } else {
        status = status.copyWithZero();
      }
      // 轮询是 silent 的，但一轮检测刚结束时必须把结果拉回来，
      // 否则节点页永远停在旧数据（或空列表）。
      final justFinished = wasChecking && !status.checking;
      if (justFinished) {
        silent = false;
      }
      if (!silent) {
        final res = await a.results();
        if (res != null) {
          final list = res['nodes'];
          nodes = list is List
              ? list.whereType<Map>().map((e) => NodeItem.fromJson(e.map((k, v) => MapEntry(k.toString(), v)))).toList()
              : <NodeItem>[];
          checkedAt = (res['checkedAt'] ?? '') as String;
        }
        kernelLog = await Native.log(400);
        if (kernelVersion.isEmpty) {
          final v = await a.version();
          if (v != null && v.isNotEmpty) kernelVersion = v;
        }
      }
      lastRefresh = DateTime.now();
    } catch (e) {
      // 内核可能刚启动还没监听端口，静默忽略
    }
    notifyListeners();
  }

  Future<void> triggerCheck() async {
    await api?.triggerCheck();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await refresh();
  }

  Future<void> forceClose() async {
    await api?.forceClose();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await refresh();
  }

  Future<void> clearResults() async {
    await Native.clearResults();
    nodes = <NodeItem>[];
    notifyListeners();
  }

  Future<String?> readConfig() async {
    final r = await Native.readConfig();
    return (r['text'] ?? '') as String;
  }

  Future<bool> writeConfig(String text) async {
    try {
      await Native.writeConfig(text);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    api?.dispose();
    super.dispose();
  }
}

extension _Zero on KernelStatus {
  KernelStatus copyWithZero() => KernelStatus.empty;
}
