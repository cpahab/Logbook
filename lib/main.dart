import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/services/auth_service.dart';
import 'core/services/gpx_share_service.dart';
import 'features/home/data/home_repository.dart';
import 'features/home/domain/day_entry.dart';
import 'features/home/domain/timeline_entry.dart';
import 'features/home/domain/daily_track.dart';
import 'features/home/domain/track_point.dart';
import 'features/home/domain/crew_member.dart';
import 'features/home/domain/timeline_amendment.dart';
import 'features/emergency/domain/emergency_contact.dart';
import 'features/emergency/data/emergency_repository.dart';
import 'features/settings/domain/theme_provider.dart';
import 'core/services/logbook_service.dart';
import 'core/services/firestore_service.dart';
import 'core/services/storage_service.dart';
import 'firebase_options.dart';

import 'app/router.dart';
import 'app.dart';

class _GpxResumeObserver extends WidgetsBindingObserver {
  final GpxShareService _service;
  _GpxResumeObserver(this._service);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _service.checkPendingFile();
  }
}

Future<void> _initFirestore(
    User user,
    ThemeProvider themeProvider,
    HomeRepository repo,
    EmergencyRepository emergencyRepo,
    ValueNotifier<String?> logbookIdNotifier) async {
  try {
    // Only wipe local data when we are CERTAIN a different person signed in:
    // same Firebase project, different UID. If the project changed (dev→prod
    // migration) or we have no prior project on record, keep the local data and
    // let the initial-sync push it to the new project.
    final previousUid = themeProvider.lastKnownUid;
    final previousProjectId = themeProvider.lastKnownProjectId;
    final currentProjectId = DefaultFirebaseOptions.currentPlatform.projectId;
    if (previousUid != null && previousUid != user.uid) {
      final knownSameProject = previousProjectId != null &&
          previousProjectId == currentProjectId;
      if (knownSameProject) {
        await repo.clearLocalData();
        await emergencyRepo.clearLocalData();
        await themeProvider.clearVesselSettings();
      }
      // Force a full push so local data reaches the (possibly new) project.
      themeProvider.resetInitialSync();
    }

    final logbookService = LogbookService();
    String? logbookId = await logbookService.getActiveLogbookId(user.uid);
    logbookId ??= await logbookService.createLogbook(user.uid, 'My Logbook');
    final firestore = FirestoreService(logbookId: logbookId);
    final storage = StorageService(logbookId: logbookId);
    final initialSync = themeProvider.needsInitialSync;
    await Future.wait([
      repo.attachFirestore(firestore, initialSync: initialSync),
      repo.attachStorage(storage, initialSync: initialSync),
      themeProvider.attachFirestore(firestore, initialSync: initialSync),
      emergencyRepo.attachFirestore(firestore, initialSync: initialSync),
    ]);
    if (initialSync) themeProvider.markInitialSyncDone();
    themeProvider.setLastKnownUid(user.uid);
    themeProvider.setLastKnownProjectId(currentProjectId);
    logbookIdNotifier.value = logbookId;
  } catch (e, st) {
    // ignore: avoid_print
    print('[initFirestore] failed: $e\n$st');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de_CH');
  await initializeDateFormatting('en_GB');

  await Hive.initFlutter();

  Hive.registerAdapter(DayEntryAdapter());
  Hive.registerAdapter(TimelineEntryAdapter());
  Hive.registerAdapter(TimelineAmendmentAdapter());
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

  final authService = AuthService();

  final gpxShareService = GpxShareService();
  await gpxShareService.init();
  WidgetsBinding.instance.addObserver(_GpxResumeObserver(gpxShareService));

  final logbookIdNotifier = ValueNotifier<String?>(null);

  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);

    // Configure offline persistence immediately after init, before any reads.
    FirestoreService.configure();

    final initialUser = FirebaseAuth.instance.currentUser;
    if (initialUser != null) {
      unawaited(_initFirestore(
          initialUser, themeProvider, repo, emergencyRepo, logbookIdNotifier));
    }

    // Trigger Firestore init on null → User transitions only.
    User? lastAuthUser = initialUser;
    authService.authStateChanges.listen((user) {
      if (lastAuthUser == null && user != null) {
        unawaited(_initFirestore(
            user, themeProvider, repo, emergencyRepo, logbookIdNotifier));
      }
      lastAuthUser = user;
    });

    // Retry Firestore init when connectivity is restored after an offline start.
    Connectivity().onConnectivityChanged.listen((results) {
      final hasConnection =
          results.any((r) => r != ConnectivityResult.none);
      final user = FirebaseAuth.instance.currentUser;
      if (hasConnection && logbookIdNotifier.value == null && user != null) {
        unawaited(_initFirestore(
            user, themeProvider, repo, emergencyRepo, logbookIdNotifier));
      }
    });
  } catch (_) {
    // Firebase unavailable — continue offline.
  }

  final router = buildRouter(themeProvider.lastRouteToday, authService);

  // Navigate to the import screen from anywhere in the app — using the router
  // directly avoids the issue of calling context.go from a non-top-level screen.
  gpxShareService.gpxFilePaths.listen((path) {
    router.go('/gpx-import', extra: path);
  });

  // Check for a GPX file that arrived before the engine was ready. Done here
  // (rather than in HomeScreen.initState()) so it still fires when the app
  // boots directly into a restored deep link like a day view, where
  // HomeScreen never mounts.
  unawaited(gpxShareService.checkPendingFile());

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
        ChangeNotifierProvider.value(value: authService),
        ChangeNotifierProvider.value(value: logbookIdNotifier),
        Provider.value(value: gpxShareService),
      ],
      child: Logbook(router: router),
    ),
  );
}

void unawaited(Future<void> future) => future.catchError((_) {});
