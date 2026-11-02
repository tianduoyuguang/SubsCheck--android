import 'dart:async';
import 'package:flutter/services.dart';

/// 与 Android 侧 MainActivity 的 MethodChannel 桥接。
class Native {
  static const MethodChannel _ch = MethodChannel('subscheck/native');

  static Future<Map<String, dynamic>> _call(String method, [Map<String, dynamic>? args]) async {
    final raw = await _ch.invokeMethod<Map<dynamic, dynamic>>(method, args);
    return raw == null ? <String, dynamic>{} : raw.map((k, v) => MapEntry(k.toString(), v));
  }

  static Future<Map<String, dynamic>> info() => _call('info');

  static Future<Map<String, dynamic>> prepare(String template) =>
      _call('prepare', <String, dynamic>{'template': template});

  static Future<Map<String, dynamic>> start() => _call('start');
  static Future<Map<String, dynamic>> stop() => _call('stop');
  static Future<Map<String, dynamic>> restart() => _call('restart');
  static Future<Map<String, dynamic>> status() => _call('status');

  static Future<String> log([int limit = 300]) async {
    final r = await _call('log', <String, dynamic>{'limit': limit});
    return (r['text'] ?? '') as String;
  }

  static Future<void> clearResults() => _call('clearResults');

  static Future<Map<String, dynamic>> readConfig() => _call('readConfig');

  static Future<Map<String, dynamic>> writeConfig(String text) =>
      _call('writeConfig', <String, dynamic>{'text': text});

  static Future<Map<String, dynamic>> setPort(int port) =>
      _call('setPort', <String, dynamic>{'port': port});

  static Future<Map<String, dynamic>> setHost(String host) =>
      _call('setHost', <String, dynamic>{'host': host});

  static Future<Map<String, dynamic>> saveExport(String name, String content) =>
      _call('saveExport', <String, dynamic>{'name': name, 'content': content});

  static Future<bool> hasNotificationPermission() async {
    final r = await _call('notifyPermission');
    return r['granted'] == true;
  }

  static Future<bool> requestNotificationPermission() async {
    final r = await _call('requestNotifyPermission');
    return r['granted'] == true;
  }
}
