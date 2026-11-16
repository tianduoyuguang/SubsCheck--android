import 'package:flutter_test/flutter_test.dart';
import 'package:subscheck/src/models.dart';

void main() {
  test('KernelStatus.fromJson parses pipeline', () {
    final s = KernelStatus.fromJson(<String, dynamic>{
      'checking': true,
      'proxyCount': 120,
      'available': 42,
      'progress': 35,
      'phase': 2,
      'pipeline': <String, dynamic>{
        'total': 120,
        'aliveDone': 120,
        'alivePass': 60,
        'mediaDone': 60,
        'filterPass': 55,
        'speedDone': 40,
        'speedPass': 20,
      },
      'hasSpeedTest': true,
    });
    expect(s.checking, true);
    expect(s.proxyCount, 120);
    expect(s.alivePass, 60);
    expect(s.speedPass, 20);
    expect(s.hasSpeedTest, true);
    expect(s.aliveRatio, greaterThan(0.0));
  });

  test('NodeItem.fromJson parses node fields', () {
    final n = NodeItem.fromJson(<String, dynamic>{
      'name': 'HK 01',
      'baseName': 'HK',
      'type': 'trojan',
      'server': '1.2.3.4',
      'port': 443,
      'sni': 'a.example.com',
      'tls': true,
      'reality': false,
      'udp': true,
      'network': 'tcp',
      'speed': 2048,
      'country': 'HK',
      'ip': '1.2.3.4',
      'ipRisk': 'low',
      'media': <Map<String, dynamic>>[
        <String, dynamic>{'platform': 'openai', 'tag': 'ok'},
      ],
      'subTag': 'free',
    });
    expect(n.name, 'HK 01');
    expect(n.port, '443');
    expect(n.tls, true);
    expect(n.speedText, contains('MB/s'));
    expect(n.media.length, 1);
  });

  test('测速进度分母是可用节点数（filterPass），不是订阅节点总数', () {
    final s = KernelStatus.fromJson(<String, dynamic>{
      'proxyCount': 120,
      'available': 42,
      'pipeline': <String, dynamic>{
        'total': 120,
        'aliveDone': 120,
        'alivePass': 42,
        'mediaDone': 42,
        'filterPass': 55,
        'speedDone': 40,
        'speedPass': 20,
      },
      'hasSpeedTest': true,
    });
    expect(s.speedTotal, 55);
    expect(s.speedRatio, closeTo(40 / 55, 1e-9));
  });

  test('filterPass 还没涨起来时回落到 available，避免 0/0', () {
    final s = KernelStatus.fromJson(<String, dynamic>{
      'proxyCount': 120,
      'available': 42,
      'pipeline': <String, dynamic>{'filterPass': 0, 'speedDone': 0},
      'hasSpeedTest': true,
    });
    expect(s.speedTotal, 42);
    expect(s.speedRatio, 0);
  });
}
