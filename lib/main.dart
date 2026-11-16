import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app_state.dart';
import 'src/disclaimer.dart';
import 'src/native.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeDisclaimer());
  }

  /// 首次启动弹一次免责声明；不同意就直接退出，不写标记位，下次仍会再问。
  Future<void> _maybeDisclaimer() async {
    bool seen = false;
    try {
      seen = await Native.disclaimerSeen();
    } catch (_) {
      // 原生侧偶发异常时不要卡住启动。
      return;
    }
    if (seen) return;
    final ctx = _nav.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final ok = await showDisclaimerDialog(ctx, requireAccept: true);
    if (!mounted) return;
    if (!ok) {
      await SystemNavigator.pop();
      return;
    }
    try {
      await Native.markDisclaimerSeen();
    } catch (_) {}
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
