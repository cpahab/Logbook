import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/home/presentation/home_screen.dart';
import '../features/home/presentation/day_detail_screen.dart';

final GoRouter appRouter = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),

    GoRoute(
      path: '/day/:year/:month/:day',
      builder: (context, state) {
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
