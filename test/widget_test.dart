import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subscheck/src/models.dart';
import 'package:subscheck/src/update_prompt.dart';
import 'package:subscheck/src/updater.dart';

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

  test('媒体检测分母是测活通过数（alivePass）', () {
    final s = KernelStatus.fromJson(<String, dynamic>{
      'proxyCount': 120,
      'available': 42,
      'pipeline': <String, dynamic>{
        'aliveDone': 120,
        'alivePass': 42,
        'mediaDone': 21,
        'filterPass': 20,
      },
      'hasSpeedTest': true,
    });
    expect(s.mediaTotal, 42);
    expect(s.mediaRatio, closeTo(0.5, 1e-9));
    expect(s.hasMediaCheck, true);
  });

  test('NodeItem 解析 details 数组', () {
    final n = NodeItem.fromJson(<String, dynamic>{
      'name': 'JP 02',
      'type': 'vmess',
      'details': <Map<String, dynamic>>[
        <String, dynamic>{'k': 'cipher', 'v': 'auto'},
        <String, dynamic>{'k': 'ws-path', 'v': '/ray'},
        <String, dynamic>{'k': '', 'v': 'dropped'},
      ],
    });
    expect(n.details.length, 2);
    expect(n.details.first.key, 'cipher');
    expect(n.details.last.value, '/ray');
  });

  test('版本比较：v 前缀与分段补零', () {
    expect(compareVersion('1.2.6', '1.2.5'), 1);
    expect(compareVersion('v1.3', '1.2.9'), 1);
    expect(compareVersion('1.2.6', '1.2.6'), 0);
    expect(compareVersion('1.2', '1.2.0'), 0);
    expect(compareVersion('1.10', '1.9'), 1);
  });

  test('「不再提示此版本」只压住被忽略的那个版本', () {
    UpdateResult r(String tag, {String current = '1.2.6'}) => UpdateResult(
          ok: true,
          currentVersion: current,
          latestVersion: tag,
          assets: const <UpdateAsset>[],
        );
    const skipped = 'v1.2.7';
    bool shouldPrompt(String tag, String current) =>
        r(tag, current: current).hasUpdate && compareVersion(tag, skipped) > 0;

    // 远端仍是用户忽略过的那个版本 → 不高于它，不再弹。
    expect(shouldPrompt('v1.2.7', '1.2.6'), false);
    // 又出了更新的版本 → 重新提示。
    expect(shouldPrompt('v1.2.8', '1.2.6'), true);
    // 用户已经装上去了，当前版本更高 → 本来就没有更新。
    expect(r('v1.2.7', current: '1.2.8').hasUpdate, false);
  });

  /// 弹一次启动更新框，点 [button]，返回选择结果。
  Future<String?> tapPrompt(WidgetTester tester, String button) async {
    String? picked;
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: SizedBox.shrink());
      }),
    ));
    // showDialog 不能在 build 阶段调用，等首帧结束再弹。
    showUpdatePrompt(
      ctx,
      currentVersion: '1.2.6',
      latestVersion: 'v1.2.7',
      notes: '修复若干问题',
    ).then((v) => picked = v);
    await tester.pumpAndSettle();
    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.textContaining('当前 v1.2.6'), findsOneWidget);
    expect(find.textContaining('修复若干问题'), findsOneWidget);
    await tester.tap(find.text(button));
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('启动更新弹窗三个出口各自返回对应结果', (tester) async {
    expect(await tapPrompt(tester, '立即更新'), UpdateChoice.update);
  });

  testWidgets('启动更新弹窗：以后再说 / 不再提示', (tester) async {
    expect(await tapPrompt(tester, '以后再说'), UpdateChoice.later);
    expect(await tapPrompt(tester, '不再提示'), UpdateChoice.skip);
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
