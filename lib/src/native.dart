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

  /// 拉系统「保存到…」对话框（ACTION_CREATE_DOCUMENT），由用户自己挑文件名和位置。
  /// 返回 ok / canceled / path；用户取消时 ok=false 且 canceled=true。
  static Future<Map<String, dynamic>> saveExportAs(String name, String content) =>
      _call('saveExportAs', <String, dynamic>{'name': name, 'content': content});

  /// 把内容写到一份真实存在的缓存副本并返回路径（分享用）。
  /// 自定义目录（SAF）下 saveExport 返回的是展示用的拼接路径，磁盘上并没有这个文件。
  static Future<Map<String, dynamic>> shareCopy(String name, String content) =>
      _call('shareCopy', <String, dynamic>{'name': name, 'content': content});

  /// 是否已在系统「忽略电池优化」白名单里。
  static Future<bool> ignoringBattery() async {
    final r = await _call('batteryStatus');
    return r['ignoring'] == true;
  }

  /// 打开系统的电池优化设置（优先直接弹本应用的授权框）。
  static Future<void> requestIgnoreBattery() async {
    await _call('requestBattery');
  }

  /// 首启免责声明是否已经确认过。
  static Future<bool> disclaimerSeen() async {
    final r = await _call('disclaimerSeen');
    return r['seen'] == true;
  }

  static Future<void> markDisclaimerSeen() async {
    await _call('setDisclaimerSeen');
  }

  /// 启动自动检查更新的偏好：version 是被「不再提示此版本」忽略的版本号
  /// （空串表示没忽略过），auto 是「启动时自动检查」开关（默认开）。
  static Future<Map<String, dynamic>> updatePrefs() => _call('updateSkip');

  static Future<void> setAutoCheckUpdate(bool on) async {
    await _call('setAutoUpdate', <String, dynamic>{'on': on});
  }

  static Future<void> setUpdateSkipVersion(String version) async {
    await _call('setUpdateSkip', <String, dynamic>{'version': version});
  }

  /// 当前导出目录配置：mode / label / path / privatePath / downloadPath /
  /// hasTree / storageGranted / needsPermission。
  static Future<Map<String, dynamic>> exportInfo() => _call('exportInfo');

  static Future<Map<String, dynamic>> setExportMode(String mode) =>
      _call('setExportMode', <String, dynamic>{'mode': mode});

  static Future<Map<String, dynamic>> setExportTree(String uri) =>
      _call('setExportTree', <String, dynamic>{'uri': uri});

  static Future<Map<String, dynamic>> clearExportTree() => _call('clearExportTree');

  /// 拉起系统文件夹选择器（SAF）。结果通过 [exportDirEvents] 回调。
  static Future<void> pickExportDir() async {
    await _call('pickExportDir');
  }

  /// 目录选择完成后 Kotlin 侧主动推送。
  static void bindExportDirEvents(void Function(Map<String, dynamic> info) onChanged) {
    _ch.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'exportDirChanged') {
        final raw = call.arguments;
        if (raw is Map) {
          onChanged(raw.map((k, v) => MapEntry(k.toString(), v)));
        }
      }
      return null;
    });
  }

  static Future<bool> hasNotificationPermission() async {
    final r = await _call('notifyPermission');
    return r['granted'] == true;
  }

  static Future<bool> requestNotificationPermission() async {
    final r = await _call('requestNotifyPermission');
    return r['granted'] == true;
  }

  /// 用系统浏览器打开链接（GitHub 在国内经常需要切浏览器/代理）。
  static Future<bool> openUrl(String url) async {
    final r = await _call('openUrl', <String, dynamic>{'url': url});
    return r['ok'] == true;
  }

  /// 后台下载更新包到私有缓存，完成后自动唤起系统安装器。
  static Future<Map<String, dynamic>> startDownload(String url, String fileName) =>
      _call('downloadApk', <String, dynamic>{'url': url, 'name': fileName});

  /// 轮询下载进度：downloading / percent / received / total / done / error / path /
  /// needPermission / installing。
  static Future<Map<String, dynamic>> downloadStatus() => _call('downloadStatus');

  /// 跳到系统「安装未知应用」授权页（Android 8.0+ 系统强制交互，App 不能代授权）。
  /// 返回 ok（是否成功打开设置页）与 allowed（当前是否已允许）。
  static Future<Map<String, dynamic>> requestInstallPermission() =>
      _call('installPermission');

  /// 当前是否已允许安装未知应用。
  static Future<bool> installAllowed() async {
    final r = await _call('installStatus');
    return r['allowed'] == true;
  }

  /// 是否已允许安装未知应用 + 缓存里是否还留着下好的更新包。
  static Future<Map<String, dynamic>> installState() => _call('installStatus');

  /// 不判权限，直接把缓存里的更新包交给系统安装器（由系统再挡一次）。
  static Future<Map<String, dynamic>> installForce() => _call('installForce');

  /// 用户授权后立即续装这次下载的包；relaunched 表示是否真的重新拉起了安装器。
  static Future<Map<String, dynamic>> installNow() => _call('installNow');
}
