import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'features/auth/domain/auth_provider.dart' as app_auth;
import 'features/home/data/home_repository.dart';
import 'features/home/domain/day_entry.dart';
import 'features/home/domain/timeline_entry.dart';
import 'features/home/domain/daily_track.dart';
import 'features/home/domain/track_point.dart';
import 'features/home/domain/crew_member.dart';
import 'features/emergency/domain/emergency_contact.dart';
import 'features/emergency/data/emergency_repository.dart';
import 'features/settings/domain/theme_provider.dart';
import 'core/services/boat_service.dart';
import 'core/services/firestore_service.dart';
import 'core/services/storage_service.dart';
import 'firebase_options.dart';

import 'app/router.dart';
import 'app.dart';

// Module-level references kept so _initFirestore can reach them without
// threading every object through every call site.
late HomeRepository _repo;
late EmergencyRepository _emergencyRepo;
late ThemeProvider _themeProvider;
String? _activeBoatId;

/// Resolves the boatId for [user], then (re-)attaches Firestore and Storage.
///
/// Guard: if the boatId hasn't changed since the last call, returns early so
/// re-attaching is not triggered on every auth-state emission.
/// Reset _activeBoatId to null on sign-out (see listener in main) so that
/// a subsequent sign-in always re-runs this path.
Future<void> _initFirestore(User user) async {
  try {
    final inviteCode = _themeProvider.installationId;
    final boatId = await BoatService().resolveBoatId(user.uid, inviteCode);
    if (_activeBoatId == boatId) return;
    _activeBoatId = boatId;

    final initialSync = _themeProvider.needsInitialSync;
    final firestore = FirestoreService(boatId: boatId);
    final storage = StorageService(boatId: boatId);

    unawaited(
      Future.wait([
        _repo.attachFirestore(firestore, initialSync: initialSync),
        _repo.attachStorage(storage, initialSync: initialSync),
        _themeProvider.attachFirestore(firestore, initialSync: initialSync),
        _emergencyRepo.attachFirestore(firestore, initialSync: initialSync),
      ]).then((_) {
        if (initialSync) _themeProvider.markInitialSyncDone();
      }),
    );
  } catch (_) {
    // Offline or Firestore error — continue with local data, retry next launch.
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de_CH');
  await initializeDateFormatting('en');

  await Hive.initFlutter();

  Hive.registerAdapter(DayEntryAdapter());
  Hive.registerAdapter(TimelineEntryAdapter());
  Hive.registerAdapter(DailyTrackAdapter());
  Hive.registerAdapter(TrackPointAdapter());
  Hive.registerAdapter(CrewMemberAdapter());
  Hive.registerAdapter(EmergencyContactAdapter());

  _repo = HomeRepository();
  await _repo.init();

  _emergencyRepo = EmergencyRepository();
  await _emergencyRepo.init();

  _themeProvider = ThemeProvider();
  await _themeProvider.init();

  // Initialize Firebase and attach Firestore sync.
  // FirestoreService.configure() must be called before Firebase.initializeApp
  // so offline persistence settings are applied before any SDK code runs.
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    FirestoreService.configure();

    // Resolve auth state synchronously (first emission from the stream).
    // If the user is already signed in, initialize Firestore immediately.
    // If not, the router redirects to /auth/login and the listener below
    // handles initialization once sign-in completes.
    final initialUser =
        await FirebaseAuth.instance.authStateChanges().first;
    if (initialUser != null) {
      await _initFirestore(initialUser);
    }

    // Watch for sign-in transitions after startup (null → User).
    // _initFirestore deduplicates by boatId, so no double-init occurs
    // when the stream re-emits the user that was already initialized above.
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) {
        _activeBoatId = null; // allow re-init on next sign-in
        return;
      }
      await _initFirestore(user);
    });
  } catch (_) {
    // Firebase unavailable — continue offline.
  }

  final router = buildRouter(_themeProvider.lastRouteToday);
  router.routerDelegate.addListener(() {
    final location =
        router.routerDelegate.currentConfiguration.uri.toString();
    _themeProvider.saveLastRoute(location);
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _repo),
        ChangeNotifierProvider.value(value: _themeProvider),
        ChangeNotifierProvider.value(value: _emergencyRepo),
        ChangeNotifierProvider(create: (_) => app_auth.AuthProvider()),
      ],
      child: Logbook(router: router),
    ),
  );
}

void unawaited(Future<void> future) => future.catchError((_) {});
