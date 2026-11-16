/// 内核 /api/status 的解析结果。
class KernelStatus {
  const KernelStatus({
    required this.checking,
    required this.proxyCount,
    required this.available,
    required this.progress,
    required this.phase,
    required this.aliveDone,
    required this.alivePass,
    required this.mediaDone,
    required this.filterPass,
    required this.speedDone,
    required this.speedPass,
    required this.hasSpeedTest,
  });

  final bool checking;
  final int proxyCount;
  final int available;
  final int progress;
  final int phase;
  final int aliveDone;
  final int alivePass;
  final int mediaDone;
  final int filterPass;
  final int speedDone;
  final int speedPass;
  final bool hasSpeedTest;

  static const KernelStatus empty = KernelStatus(
    checking: false,
    proxyCount: 0,
    available: 0,
    progress: 0,
    phase: 0,
    aliveDone: 0,
    alivePass: 0,
    mediaDone: 0,
    filterPass: 0,
    speedDone: 0,
    speedPass: 0,
    hasSpeedTest: false,
  );

  factory KernelStatus.fromJson(Map<String, dynamic> j) {
    final p = j['pipeline'];
    final pipe = p is Map ? p : <String, dynamic>{};
    int numOf(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return KernelStatus(
      checking: j['checking'] == true,
      proxyCount: numOf(j['proxyCount']),
      available: numOf(j['available']),
      progress: numOf(j['progress']),
      phase: numOf(j['phase']),
      aliveDone: numOf(pipe['aliveDone'] ?? j['progress']),
      alivePass: numOf(pipe['alivePass'] ?? j['available']),
      mediaDone: numOf(pipe['mediaDone']),
      filterPass: numOf(pipe['filterPass']),
      speedDone: numOf(pipe['speedDone']),
      speedPass: numOf(pipe['speedPass']),
      hasSpeedTest: j['hasSpeedTest'] == true,
    );
  }

  /// 测速阶段的总数：进入测速的是「通过过滤的可用节点」
  /// （内核 pipeline.filterPass），不是订阅里的节点总数。
  /// 未配置 filter / 未开流媒体检测时 filterPass 等于 available，
  /// 也就是概览页「可用节点」那个数字。
  /// 早期 filterPass 还没涨起来（0）时回落到 available，避免显示 0/0。
  int get speedTotal => filterPass > 0 ? filterPass : available;

  /// 媒体检测阶段的总数：只有测活通过的节点才会进入这一阶段。
  int get mediaTotal => alivePass;

  double get aliveRatio => proxyCount <= 0 ? 0 : aliveDone / proxyCount;
  double get mediaRatio => mediaTotal <= 0 ? 0 : mediaDone / mediaTotal;
  double get speedRatio => speedTotal <= 0 ? 0 : speedDone / speedTotal;

  /// 是否跑过媒体检测（内核只有开了 media-check 才会累加 mediaDone）。
  bool get hasMediaCheck => mediaDone > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KernelStatus &&
          other.checking == checking &&
          other.proxyCount == proxyCount &&
          other.available == available &&
          other.progress == progress &&
          other.phase == phase &&
          other.aliveDone == aliveDone &&
          other.alivePass == alivePass &&
          other.mediaDone == mediaDone &&
          other.filterPass == filterPass &&
          other.speedDone == speedDone &&
          other.speedPass == speedPass &&
          other.hasSpeedTest == hasSpeedTest;

  @override
  int get hashCode => Object.hash(checking, proxyCount, available, progress, phase,
      aliveDone, alivePass, mediaDone, filterPass, speedDone, speedPass, hasSpeedTest);
}

/// results.json 里指标的附加参数（cipher / ws-path / plugin ...），
/// 由内核 save.NodeRecord.Details 白名单产出。
class NodeDetail {
  const NodeDetail({required this.key, required this.value});
  final String key;
  final String value;

  factory NodeDetail.fromJson(Map<String, dynamic> j) => NodeDetail(
        key: (j['k'] ?? '').toString(),
        value: (j['v'] ?? '').toString(),
      );
}

/// /api/results 里的单个节点。
class NodeItem {
  NodeItem({
    required this.name,
    required this.baseName,
    required this.type,
    required this.server,
    required this.port,
    required this.sni,
    required this.tls,
    required this.reality,
    required this.udp,
    required this.network,
    required this.speed,
    required this.country,
    required this.ip,
    required this.ipRisk,
    required this.subTag,
    required this.media,
    required this.details,
  });

  final String name;
  final String baseName;
  final String type;
  final String server;
  final String port;
  final String sni;
  final bool tls;
  final bool reality;
  final bool udp;
  final String network;
  final int speed;
  final String country;
  final String ip;
  final String ipRisk;
  final String subTag;
  final List<String> media;
  final List<NodeDetail> details;

  factory NodeItem.fromJson(Map<String, dynamic> j) {
    String str(dynamic v) => v == null ? '' : v.toString();
    int numOf(dynamic v) => v is num ? v.toInt() : int.tryParse(str(v)) ?? 0;
    final m = j['media'];
    final media = <String>[];
    if (m is List) {
      for (final e in m) {
        if (e is Map && (e['tag'] ?? '') != '') media.add(e['tag'].toString());
      }
    }
    final d = j['details'];
    final details = <NodeDetail>[];
    if (d is List) {
      for (final e in d) {
        if (e is Map) {
          final det = NodeDetail.fromJson(e.map((k, v) => MapEntry(k.toString(), v)));
          if (det.key.isNotEmpty && det.value.isNotEmpty) details.add(det);
        }
      }
    }
    return NodeItem(
      name: str(j['name']),
      baseName: str(j['baseName']),
      type: str(j['type']),
      server: str(j['server']),
      port: str(j['port']),
      sni: str(j['sni']),
      tls: j['tls'] == true,
      reality: j['reality'] == true,
      udp: j['udp'] == true,
      network: str(j['network']),
      speed: numOf(j['speed']),
      country: str(j['country']),
      ip: str(j['ip']),
      ipRisk: str(j['ipRisk']),
      subTag: str(j['subTag']),
      media: media,
      details: details,
    );
  }

  String get speedText => speed <= 0 ? '-' : '${(speed / 1024).toStringAsFixed(1)} MB/s';
}
