import 'package:go_router/go_router.dart';

import '../core/services/auth_service.dart';
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

GoRouter buildRouter(String initialLocation, AuthService authService) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: authService,
    redirect: (context, state) {
      final signedIn = authService.currentUser != null;
      final onAuth = state.matchedLocation.startsWith('/auth');

      if (!signedIn && !onAuth) return '/auth/login';
      if (signedIn && onAuth) return '/';
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
        path: '/tracks/fullscreen',
        builder: tracksFullScreenRouteBuilder,
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
