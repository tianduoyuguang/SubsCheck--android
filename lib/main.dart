import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app_state.dart';
import 'src/disclaimer.dart';
import 'src/native.dart';
import 'src/update_prompt.dart';
import 'src/updater.dart';
import 'pages/about.dart';
import 'pages/home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SubsCheckApp());
}

class SubsCheckApp extends StatefulWidget {
  const SubsCheckApp({super.key});

  @override
  State<SubsCheckApp> createState() => _SubsCheckAppState();
}

class _SubsCheckAppState extends State<SubsCheckApp> {
  final AppState state = AppState();
  final GlobalKey<NavigatorState> _nav = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    state.initialize();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startupSequence());
  }

  /// 启动后先问免责声明（首启），再静默检查一次更新。
  ///
  /// 两者串行：免责声明是本 App 唯一的强制前置条件，若和更新弹窗同时出现，
  /// 两个对话框会叠在一起，用户点完上面那个才会看到下面那个。
  Future<void> _startupSequence() async {
    final accepted = await _maybeDisclaimer();
    // 免责声明没同意时 App 正在退出，不要再叠一个更新弹窗。
    if (!mounted || !accepted) return;
    await _maybeUpdate();
  }

  /// 首次启动弹一次免责声明；不同意就直接退出，不写标记位，下次仍会再问。
  Future<bool> _maybeDisclaimer() async {
    bool seen = false;
    try {
      seen = await Native.disclaimerSeen();
    } catch (_) {
      // 原生侧偶发异常时不要卡住启动。
      return true;
    }
    if (seen) return true;
    final ctx = _nav.currentContext;
    if (ctx == null || !ctx.mounted) return true;
    final ok = await showDisclaimerDialog(ctx, requireAccept: true);
    if (!mounted) return false;
    if (!ok) {
      await SystemNavigator.pop();
      return false;
    }
    try {
      await Native.markDisclaimerSeen();
    } catch (_) {}
    return true;
  }

  /// 启动时静默检查一次更新；有新版本才弹窗。
  ///
  /// 静默指：网络不通、接口限流、当前已是最新，一律什么都不显示——启动过程中
  /// 报「检查更新失败」对用户没有意义，想知道结果可以去「设置 → 关于」手动点。
  Future<void> _maybeUpdate() async {
    UpdateResult r;
    String skipped = '';
    try {
      final prefs = await Native.updatePrefs();
      if (prefs['auto'] == false) return;
      skipped = (prefs['version'] ?? '') as String;
      // 版本号必须问原生侧，不能用 state.info：本方法在首帧后就跑，而
      // AppState.initialize() 可能还没走完，此时 info 是空的，compareVersion
      // 会把任何版本都判定成「有更新」，正常用户也会被弹窗骚扰。
      final info = await Native.info();
      final current = (info['versionName'] ?? '').toString();
      // 版本号拿不到就放弃这次检查：compareVersion('', x) 会算出「有更新」。
      if (current.isEmpty || current == '未知') return;
      r = await UpdateChecker.check(
        repo: 'tianduoyuguang/SubsCheck--android',
        currentVersion: current,
      );
    } catch (_) {
      return;
    }
    if (!mounted || !r.ok || !r.hasUpdate) return;
    final latest = r.latestVersion;
    if (latest == null) return;
    // 「不再提示此版本」只压住这一个版本；用户下次更新后又会被提醒。
    if (skipped.isNotEmpty && compareVersion(latest, skipped) <= 0) return;

    final ctx = _nav.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final choice = await showUpdatePrompt(
      ctx,
      currentVersion: r.currentVersion,
      latestVersion: latest,
      notes: r.notes,
    );
    if (!mounted) return;
    if (choice == UpdateChoice.skip) {
      try {
        await Native.setUpdateSkipVersion(latest);
      } catch (_) {}
      return;
    }
    if (choice != UpdateChoice.update) return;
    // 下载与安装授权都在「关于」页，那里已有完整进度与续装逻辑，直接带过去。
    final nav = _nav.currentState;
    if (nav == null) return;
    await nav.push(MaterialPageRoute<void>(
      builder: (_) => AboutPage(state: state, autoUpdate: true),
    ));
  }

  @override
  void dispose() {
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _nav,
      title: 'SubsCheck',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3E6BE0)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3E6BE0),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: HomePage(state: state),
    );
  }
}
