import 'dart:convert';
import 'dart:io';

/// 一条 release 资产（APK 等）。
class UpdateAsset {
  const UpdateAsset({required this.name, required this.downloadUrl, required this.size});

  final String name;
  final String downloadUrl;
  final int size;

  String get sizeText {
    if (size <= 0) return '';
    final mb = size / (1024 * 1024);
    return mb >= 1 ? '${mb.toStringAsFixed(1)} MB' : '${(size / 1024).round()} KB';
  }
}

/// 检查更新的结果。
class UpdateResult {
  const UpdateResult({
    required this.ok,
    required this.currentVersion,
    this.latestVersion,
    this.tagName,
    this.htmlUrl,
    this.notes,
    this.publishedAt,
    this.assets = const <UpdateAsset>[],
    this.error,
    this.source,
  });

  final bool ok;
  final String currentVersion;
  final String? latestVersion;
  final String? tagName;
  final String? htmlUrl;
  final String? notes;
  final String? publishedAt;
  final List<UpdateAsset> assets;
  final String? error;

  /// 实际取到数据的那条链路（直连 / 镜像域名），便于排查网络问题。
  final String? source;

  bool get hasUpdate =>
      ok &&
      latestVersion != null &&
      compareVersion(latestVersion!, currentVersion) > 0;
}

/// 按 ABI 挑出当前设备应该下载的 APK。
UpdateAsset? pickAssetFor(List<UpdateAsset> assets, String abi) {
  bool has(UpdateAsset a, String key) => a.name.toLowerCase().contains(key);
  final apks = assets.where((a) => a.name.toLowerCase().endsWith('.apk')).toList();
  if (apks.isEmpty) return null;
  if (abi.contains('arm64')) {
    for (final a in apks) {
      if (has(a, 'arm64') || has(a, 'aarch64') || has(a, 'v8a')) return a;
    }
  }
  if (abi.contains('arm') || abi.contains('v7')) {
    for (final a in apks) {
      if (has(a, 'v7a') || has(a, 'armeabi')) return a;
    }
  }
  final exact = apks.where((a) => has(a, abi));
  if (exact.isNotEmpty) return exact.first;
  return apks.first;
}

/// 把 release 资产的直链换成走镜像的地址（GitHub 在部分网络下不可达）。
String mirrorUrl(String url) {
  if (!url.contains('github.com') && !url.contains('githubusercontent.com')) return url;
  return 'https://gh-proxy.com/$url';
}

/// 解析 1.2.3 / v1.2.3 / 1.2.3-beta 之类的版本号并比较。
int compareVersion(String a, String b) {
  final pa = _parts(a);
  final pb = _parts(b);
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x > y ? 1 : -1;
  }
  return 0;
}

List<int> _parts(String v) {
  final stripped = v.replaceFirst(RegExp(r'^[vV]'), '');
  final head = stripped.split(RegExp(r'[-+ ]')).first;
  return head
      .split('.')
      .map((s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();
}

/// 检查 GitHub 上的最新 release。
///
/// 先直连 api.github.com，失败再退到 gh-proxy.com 镜像；两者都不可用时不抛异常，
/// 而是返回 ok=false 并把原因交给调用方展示。
class UpdateChecker {
  static const List<String> _apiBases = <String>[
    'https://api.github.com/repos/{repo}/releases/latest',
    'https://gh-proxy.com/https://api.github.com/repos/{repo}/releases/latest',
    'https://ghfast.top/https://api.github.com/repos/{repo}/releases/latest',
  ];

  static Future<UpdateResult> check({
    required String repo,
    required String currentVersion,
  }) async {
    Object? lastError;
    for (final tpl in _apiBases) {
      final url = tpl.replaceFirst('{repo}', repo);
      try {
        final json = await _getJson(url);
        if (json == null) continue;
        final tag = (json['tag_name'] ?? json['name'] ?? '').toString();
        final assets = <UpdateAsset>[];
        final rawAssets = json['assets'];
        if (rawAssets is List) {
          for (final a in rawAssets) {
            if (a is! Map) continue;
            assets.add(UpdateAsset(
              name: (a['name'] ?? '').toString(),
              downloadUrl: (a['browser_download_url'] ?? '').toString(),
              size: (a['size'] is int) ? a['size'] as int : 0,
            ));
          }
        }
        return UpdateResult(
          ok: true,
          currentVersion: currentVersion,
          latestVersion: tag.isEmpty ? null : tag,
          tagName: tag,
          htmlUrl: (json['html_url'] ?? '').toString(),
          notes: (json['body'] ?? '').toString(),
          publishedAt: (json['published_at'] ?? '').toString(),
          assets: assets,
          source: Uri.parse(url).host,
        );
      } catch (e) {
        lastError = e;
      }
    }
    return UpdateResult(
      ok: false,
      currentVersion: currentVersion,
      error: lastError == null ? '网络不可用：GitHub 与镜像均未连通' : _short(lastError),
    );
  }

  static String _short(Object e) {
    final s = e.toString();
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }

  static Future<Map<String, dynamic>?> _getJson(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, 'SubsCheck-Android');
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final resp = await req.close().timeout(const Duration(seconds: 15));
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode != 200) {
        throw HttpException('HTTP ${resp.statusCode}');
      }
      final v = jsonDecode(body);
      return v is Map<String, dynamic> ? v : null;
    } finally {
      client.close(force: true);
    }
  }
}
