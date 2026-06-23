import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/emergency/presentation/emergency_manifest_screen.dart';
import '../features/emergency/presentation/emergency_screen.dart';
import '../features/emergency/presentation/mayday_screen.dart';
import '../features/home/presentation/day_detail_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/tracks/presentation/tracks_screen.dart';

// Routes that are accessible without signing in.
const _publicRoutes = {'/auth/login', '/auth/register', '/auth/forgot-password'};

GoRouter buildRouter(String initialLocation) {
  // Refresh the router whenever auth state changes.
  final authNotifier = _AuthNotifier();

  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: authNotifier,
    redirect: (context, state) {
      final signedIn = FirebaseAuth.instance.currentUser != null;
      final onPublic = _publicRoutes.contains(state.matchedLocation);

      if (!signedIn && !onPublic) return '/auth/login';
      if (signedIn && onPublic) return '/';
      return null;
    },
    routes: [
      // ── Auth ────────────────────────────────────────────────────────
      GoRoute(
        path: '/auth/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/auth/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/auth/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),

      // ── App ─────────────────────────────────────────────────────────
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
          final addEntry = state.uri.queryParameters['addEntry'] == '1';
          return DayDetailScreen(
              year: year, month: month, day: day, openAddDialog: addEntry);
        },
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/tracks',
        builder: (context, state) => const TracksScreen(),
      ),
      GoRoute(
        path: '/emergency',
        builder: (context, state) => const EmergencyManifestScreen(),
      ),
      GoRoute(
        path: '/emergency/mayday',
        builder: (context, state) => const MaydayScreen(),
      ),
      GoRoute(
        path: '/emergency/distress',
        builder: (context, state) => const EmergencyScreen(),
      ),
    ],
  );
}

// Bridges FirebaseAuth stream → GoRouter's refreshListenable.
class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier() {
    FirebaseAuth.instance.authStateChanges().listen((_) => notifyListeners());
  }
}
