import 'package:go_router/go_router.dart';

import 'package:flutter/foundation.dart';

import 'route_names.dart';
import '../core/config/feature_flags.dart';
import '../core/services/auth_service.dart';
import '../features/settings/domain/theme_provider.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/verify_email_screen.dart';
import '../features/emergency/presentation/emergency_manifest_screen.dart';
import '../features/emergency/presentation/emergency_screen.dart';
import '../features/emergency/presentation/mayday_screen.dart';
import '../features/home/presentation/crew_roster_screen.dart';
import '../features/home/presentation/day_detail_screen.dart';
import '../features/home/presentation/gpx_import_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/settings/presentation/backup_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/tracks/presentation/tracks_screen.dart';

/// Builds the app's single [GoRouter], restoring [initialLocation] (the last
/// route the user was on) and re-running [redirect] whenever [authService]'s
/// sign-in state or [themeProvider]'s local-mode flag changes
/// (`refreshListenable`), so a sign-out/sign-in event, or entering/leaving
/// local mode, immediately bounces the user to/from the auth flow without a
/// manual nav call.
GoRouter buildRouter(
    String initialLocation, AuthService authService, ThemeProvider themeProvider) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: Listenable.merge([authService, themeProvider]),
    // Auth + (optional) email-verification gate, evaluated on every navigation.
    redirect: (context, state) {
      // iOS passes the share-intent file:// URI to Flutter as a navigation
      // route on cold start. Redirect it to home; the GPX import flow runs
      // independently via the method channel.
      if (state.uri.scheme == 'file') return '/';

      final signedIn = authService.currentUser != null;
      // A user who chose "Continue without an account" also passes the
      // gate below — but only while genuinely signed out. The instant
      // `signedIn` becomes true (e.g. mid-upgrade to cloud sync), this stops
      // mattering and the normal signed-in checks below take over, even if
      // the flag hasn't been cleared yet (see ThemeProvider.disableLocalMode
      // and _initFirestore in main.dart).
      final localMode = !signedIn && themeProvider.localModeEnabled;
      final onAuth = state.matchedLocation.startsWith('/auth');
      final onVerify = state.matchedLocation == '/auth/verify-email';

      if (!signedIn && !localMode && !onAuth) return '/auth/login';

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
        name: AppRoute.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/auth/register',
        name: AppRoute.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/auth/forgot-password',
        name: AppRoute.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/auth/verify-email',
        name: AppRoute.verifyEmail,
        builder: (context, state) => const VerifyEmailScreen(),
      ),

      // ── App ─────────────────────────────────────────────────────────
      GoRoute(
        path: '/',
        name: AppRoute.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/gpx-import',
        name: AppRoute.gpxImport,
        // No file path (e.g. a stale/duplicate deep link) — bounce home
        // instead of showing an import screen with nothing to import.
        redirect: (context, state) => state.extra == null ? '/' : null,
        builder: (context, state) =>
            GpxImportScreen(filePath: state.extra! as String),
      ),
      GoRoute(
        path: '/day/:year/:month/:day',
        name: AppRoute.dayDetail,
        builder: (context, state) {
          // Path segments, not query params, so the date is part of the
          // route identity (shareable/bookmarkable, restorable on relaunch).
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
        name: AppRoute.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/settings/crew-roster',
        name: AppRoute.crewRoster,
        builder: (context, state) => const CrewRosterScreen(),
      ),
      GoRoute(
        path: '/settings/backup-restore',
        name: AppRoute.backupRestore,
        builder: (context, state) =>
            BackupScreen(activeLogbookName: state.extra as String?),
      ),
      GoRoute(
        path: '/tracks',
        name: AppRoute.tracks,
        builder: (context, state) => const TracksScreen(),
      ),
      GoRoute(
        path: '/tracks/fullscreen',
        name: AppRoute.tracksFullscreen,
        builder: tracksFullScreenRouteBuilder,
      ),
      GoRoute(
        path: '/emergency',
        name: AppRoute.emergencyManifest,
        builder: (context, state) => const EmergencyManifestScreen(),
      ),
      GoRoute(
        path: '/emergency/mayday',
        name: AppRoute.mayday,
        builder: (context, state) => const MaydayScreen(),
      ),
      GoRoute(
        path: '/emergency/distress',
        name: AppRoute.emergencyGuide,
        builder: (context, state) => const EmergencyScreen(),
      ),
    ],
  );
}
