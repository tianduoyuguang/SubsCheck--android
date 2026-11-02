import 'dart:convert';
import 'dart:io';

/// 直接访问本机内核 HTTP 服务（127.0.0.1:port），带 X-API-Key。
class KernelApi {
  KernelApi({required this.host, required this.port, required this.apiKey});

  String host;
  int port;
  String apiKey;

  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5)
    ..idleTimeout = const Duration(seconds: 3);

  String get baseUrl => 'http://$host:$port';

  Map<String, String> get _headers => <String, String>{'X-API-Key': apiKey};

  Future<_Resp> _get(String path) async {
    final uri = Uri.parse(baseUrl + path);
    final req = await _client.getUrl(uri);
    _headers.forEach((k, v) => req.headers.set(k, v));
    final resp = await req.close().timeout(const Duration(seconds: 10));
    final body = await resp.transform(utf8.decoder).join();
    return _Resp(resp.statusCode, body);
  }

  Future<_Resp> _post(String path) async {
    final uri = Uri.parse(baseUrl + path);
    final req = await _client.postUrl(uri);
    _headers.forEach((k, v) => req.headers.set(k, v));
    req.contentLength = 0;
    final resp = await req.close().timeout(const Duration(seconds: 10));
    final body = await resp.transform(utf8.decoder).join();
    return _Resp(resp.statusCode, body);
  }

  Future<bool> ping() async {
    try {
      final r = await _get('/api/status');
      return r.code == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> status() async {
    try {
      final r = await _get('/api/status');
      if (r.code != 200) return null;
      final v = jsonDecode(r.body);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> results() async {
    try {
      final r = await _get('/api/results');
      if (r.code != 200) return null;
      final v = jsonDecode(r.body);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// 内核 /api/logs 返回纯文本（最后 100 行）。
  Future<String> serverLogs() async {
    try {
      final r = await _get('/api/logs');
      return r.body;
    } catch (_) {
      return '';
    }
  }

  /// 内核静态路由 /sub/all.yaml 返回只含 proxies 的节点列表
  Future<String?> allYaml() async {
    try {
      final r = await _get('/sub/all.yaml');
      if (r.code != 200) return null;
      return r.body;
    } catch (_) {
      return null;
    }
  }

  Future<String?> config() async {
    try {
      final r = await _get('/api/config');
      if (r.code != 200) return null;
      try {
        final v = jsonDecode(r.body);
        if (v is Map<String, dynamic>) {
          final c = v['content'] ?? v['config'];
          if (c is String) return c;
        }
      } catch (_) {}
      return r.body;
    } catch (_) {
      return null;
    }
  }

  Future<bool> saveConfig(String content) async {
    try {
      final uri = Uri.parse('$baseUrl/api/config');
      final req = await _client.postUrl(uri);
      _headers.forEach((k, v) => req.headers.set(k, v));
      req.headers.contentType = ContentType.json;
      final payload = jsonEncode(<String, dynamic>{'content': content});
      req.add(utf8.encode(payload));
      final resp = await req.close().timeout(const Duration(seconds: 10));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> triggerCheck() async {
    try {
      final r = await _post('/api/trigger-check');
      return r.code == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> forceClose() async {
    try {
      final r = await _post('/api/force-close');
      return r.code == 200;
    } catch (_) {
      return false;
    }
  }

  /// 内核版本。新版内核返回 {"version":"v1.6.5"}，老版本返回纯文本。
  Future<String?> version() async {
    try {
      final r = await _get('/api/version');
      if (r.code != 200) return null;
      final body = r.body.trim();
      try {
        final v = jsonDecode(body);
        if (v is Map && v['version'] != null) return v['version'].toString();
      } catch (_) {}
      return body;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    try {
      _client.close(force: true);
    } catch (_) {}
  }
}

class _Resp {
  _Resp(this.code, this.body);
  final int code;
  final String body;
}
