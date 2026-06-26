import 'package:go_router/go_router.dart';

import '../core/config/feature_flags.dart';
import '../core/services/auth_service.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/verify_email_screen.dart';
import '../features/emergency/presentation/emergency_manifest_screen.dart';
import '../features/emergency/presentation/emergency_screen.dart';
import '../features/emergency/presentation/mayday_screen.dart';
import '../features/home/presentation/day_detail_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/home/screens/crew_roster_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/tracks/presentation/tracks_screen.dart';

GoRouter buildRouter(String initialLocation, AuthService authService) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: authService,
    redirect: (context, state) {
      final signedIn = authService.currentUser != null;
      final onAuth = state.matchedLocation.startsWith('/auth');
      final onVerify = state.matchedLocation == '/auth/verify-email';

      if (!signedIn && !onAuth) return '/auth/login';

      if (signedIn) {
        // Email verification gate — flip kEnforceEmailVerification in
        // feature_flags.dart to activate. No other code changes needed.
        final needsVerification =
            kEnforceEmailVerification && !authService.emailVerified;
        if (needsVerification && !onVerify) return '/auth/verify-email';
        if (!needsVerification && onVerify) return '/';
        if (onAuth && !onVerify) return '/';
      }

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
      GoRoute(
        path: '/auth/verify-email',
        builder: (context, state) => const VerifyEmailScreen(),
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
        path: '/settings/crew-roster',
        builder: (context, state) => const CrewRosterScreen(),
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
