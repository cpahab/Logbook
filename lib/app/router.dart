import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// Screens
import '../features/home/presentation/home_screen.dart';
import '../features/home/presentation/day_detail_screen.dart';
import '../features/home/presentation/home_shell.dart';

import '../features/tracking/presentation/tracking_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/auth/presentation/login_screen.dart';

// Routes
import 'routes.dart';

final router = GoRouter(
  initialLocation: AppRoutes.home,

  routes: [
    // LOGIN (no shell)
    GoRoute(
      path: AppRoutes.login,
      builder: (_, __) => const LoginScreen(),
    ),

    // MAIN SHELL (bottom navigation)
    ShellRoute(
      builder: (_, __, child) => HomeShell(child: child),
      routes: [
        // HOME (collapsible logbook)
        GoRoute(
          path: AppRoutes.home, // "/home"
          builder: (_, __) => const HomeScreen(),
        ),

        // TRACKING TAB
        GoRoute(
          path: AppRoutes.tracking,
          builder: (_, __) => const TrackingScreen(),
        ),

        // SETTINGS TAB
        GoRoute(
          path: AppRoutes.settings,
          builder: (_, __) => const SettingsScreen(),
        ),
      ],
    ),

    // DAY DETAIL (outside shell so it overlays cleanly)
    GoRoute(
      path: '/day/:year/:month/:day',
      builder: (_, state) {
        final year = int.parse(state.pathParameters['year']!);
        final month = int.parse(state.pathParameters['month']!);
        final day = int.parse(state.pathParameters['day']!);

        return DayDetailScreen(
          year: year,
          month: month,
          day: day,
        );
      },
    ),
  ],
);
