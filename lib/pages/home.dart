import 'package:flutter/material.dart';

import '../src/app_state.dart';
import 'overview.dart';
import 'nodes.dart';
import 'subscription.dart';
import 'settings.dart';
import 'logs.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state});
  final AppState state;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.state,
      builder: (context, _) {
        final tabs = <Widget>[
          OverviewPage(state: widget.state),
          NodesPage(state: widget.state),
          SubscriptionPage(state: widget.state),
          SettingsPage(state: widget.state),
          LogsPage(state: widget.state),
        ];
        return Scaffold(
          body: SafeArea(
            child: IndexedStack(index: index, children: tabs),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => setState(() => index = i),
            destinations: const <NavigationDestination>[
              NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: '概览'),
              NavigationDestination(icon: Icon(Icons.dns_outlined), selectedIcon: Icon(Icons.dns), label: '节点'),
              NavigationDestination(icon: Icon(Icons.ios_share_outlined), selectedIcon: Icon(Icons.ios_share), label: '订阅'),
              NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '设置'),
              NavigationDestination(icon: Icon(Icons.article_outlined), selectedIcon: Icon(Icons.article), label: '日志'),
            ],
          ),
        );
      },
    );
  }
}
