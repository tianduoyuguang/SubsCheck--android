import 'package:flutter/material.dart';

import 'src/app_state.dart';
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

  @override
  void initState() {
    super.initState();
    state.initialize();
  }

  @override
  void dispose() {
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
