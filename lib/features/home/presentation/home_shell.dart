import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/routes.dart';

class HomeShell extends StatelessWidget {
  final Widget child;
  const HomeShell({super.key, required this.child});

  int _indexForLocation(String location) {
    if (location.startsWith(AppRoutes.tracking)) return 1;
    if (location.startsWith(AppRoutes.settings)) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = _indexForLocation(location);

    return Scaffold(
      body: SafeArea(child: child),

      bottomNavigationBar: NavigationBar(
        height: 65,
        elevation: 3,
        selectedIndex: currentIndex,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              context.go(AppRoutes.home);
              break;
            case 1:
              context.go(AppRoutes.tracking);
              break;
            case 2:
              context.go(AppRoutes.settings);
              break;
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Logbook',
          ),
          NavigationDestination(
            icon: Icon(Icons.timeline_outlined),
            selectedIcon: Icon(Icons.timeline),
            label: 'Tracking',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
