import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/services/auth_service.dart';
import 'features/home/data/home_repository.dart';
import 'features/home/domain/day_entry.dart';
import 'features/home/domain/timeline_entry.dart';
import 'features/home/domain/daily_track.dart';
import 'features/home/domain/track_point.dart';
import 'features/home/domain/crew_member.dart';
import 'features/emergency/domain/emergency_contact.dart';
import 'features/emergency/data/emergency_repository.dart';
import 'features/settings/domain/theme_provider.dart';
import 'core/services/logbook_service.dart';
import 'core/services/firestore_service.dart';
import 'core/services/storage_service.dart';
import 'firebase_options.dart';

import 'app/router.dart';
import 'app.dart';

Future<void> _initFirestore(
    User user,
    ThemeProvider themeProvider,
    HomeRepository repo,
    EmergencyRepository emergencyRepo,
    ValueNotifier<String?> logbookIdNotifier) async {
  try {
    // Detect account switch: a different UID signed in while local Hive data
    // from the previous account is still cached. Wipe everything so we never
    // push the old account's data to the new account's Firestore.
    final previousUid = themeProvider.lastKnownUid;
    if (previousUid != null && previousUid != user.uid) {
      await repo.clearLocalData();
      await emergencyRepo.clearLocalData();
      await themeProvider.clearVesselSettings();
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
    logbookIdNotifier.value = logbookId;
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

  final repo = HomeRepository();
  await repo.init();

  final emergencyRepo = EmergencyRepository();
  await emergencyRepo.init();

  final themeProvider = ThemeProvider();
  await themeProvider.init();

  final authService = AuthService();

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
      ],
      child: Logbook(router: router),
    ),
  );
}

void unawaited(Future<void> future) => future.catchError((_) {});
