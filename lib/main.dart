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
import 'core/services/bootstrap_service.dart';
import 'core/services/firestore_service.dart';
import 'core/services/storage_service.dart';
import 'firebase_options.dart';

import 'app/router.dart';
import 'app.dart';

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

  final repo = HomeRepository();
  await repo.init();

  final emergencyRepo = EmergencyRepository();
  await emergencyRepo.init();

  final themeProvider = ThemeProvider();
  await themeProvider.init();

  // Initialize Firebase and attach Firestore sync.
  // Runs after local data is ready so the app is usable even if Firebase fails.
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    FirestoreService.configure();

    // Bootstrap the already-signed-in user before attaching services so we
    // have the authoritative boatId from their Firestore profile.
    var boatId = themeProvider.installationId; // local fallback
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      try {
        final profileBoatId = await BootstrapService.ensureUserAndBoat(
          uid: currentUser.uid,
          email: currentUser.email ?? '',
          fallbackBoatId: themeProvider.installationId,
        );
        if (profileBoatId != boatId) {
          themeProvider.reconcileBoatId(profileBoatId);
          boatId = profileBoatId;
        }
      } catch (_) {
        // Offline on first launch — use local code, retry next time.
      }
    }

    final initialSync = themeProvider.needsInitialSync;
    var firestore = FirestoreService(boatId: boatId);
    var storage = StorageService(boatId: boatId);

    unawaited(
      Future.wait([
        repo.attachFirestore(firestore, initialSync: initialSync),
        repo.attachStorage(storage, initialSync: initialSync),
        themeProvider.attachFirestore(firestore, initialSync: initialSync),
        emergencyRepo.attachFirestore(firestore, initialSync: initialSync),
      ]).then((_) {
        if (initialSync) themeProvider.markInitialSyncDone();
      }),
    );

    // When the user signs in after app startup (e.g. from the login screen),
    // run bootstrap and re-attach services if the authoritative boatId differs.
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) return;
      try {
        final newBoatId = await BootstrapService.ensureUserAndBoat(
          uid: user.uid,
          email: user.email ?? '',
          fallbackBoatId: themeProvider.installationId,
        );
        if (newBoatId == boatId) return; // nothing changed

        boatId = newBoatId;
        themeProvider.reconcileBoatId(newBoatId);

        // Re-attach services with the correct boatId (incremental sync only —
        // the initial full sync already ran for the local logbook code).
        firestore = FirestoreService(boatId: newBoatId);
        storage = StorageService(boatId: newBoatId);
        await Future.wait([
          repo.attachFirestore(firestore, initialSync: false),
          repo.attachStorage(storage, initialSync: false),
          themeProvider.attachFirestore(firestore, initialSync: false),
          emergencyRepo.attachFirestore(firestore, initialSync: false),
        ]);
      } catch (_) {
        // Bootstrap failed (offline) — retry on next launch.
      }
    });
  } catch (_) {
    // Firebase unavailable — continue offline.
  }

  final router = buildRouter(themeProvider.lastRouteToday);
  router.routerDelegate.addListener(() {
    final location =
        router.routerDelegate.currentConfiguration.uri.toString();
    themeProvider.saveLastRoute(location);
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: repo),
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: emergencyRepo),
        ChangeNotifierProvider(create: (_) => app_auth.AuthProvider()),
      ],
      child: Logbook(router: router),
    ),
  );
}

void unawaited(Future<void> future) => future.catchError((_) {});
