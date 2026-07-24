import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show BuiltInMapCachingProvider;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/services/auth_service.dart';
import 'core/services/crash_reporter.dart';
import 'core/services/gpx_share_service.dart';
import 'core/utils/retry_with_backoff.dart';
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
import 'core/services/local_logbook_service.dart';
import 'core/services/logbook_service.dart';
import 'core/services/firestore_service.dart';
import 'core/services/storage_service.dart';
import 'features/tracks/utils/warm_tracks_cache.dart';
import 'firebase_options.dart';

import 'app/route_names.dart';
import 'app/router.dart';
import 'app.dart';

/// Re-checks for a pending "open with Logbook" GPX file whenever the app
/// returns to the foreground, since iOS/Android can deliver the file while
/// the app was backgrounded and [GpxShareService] only queues it.
class _GpxResumeObserver extends WidgetsBindingObserver {
  final GpxShareService _service;
  _GpxResumeObserver(this._service);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _service.checkPendingFile();
  }
}

/// Attaches the signed-in [user]'s Firestore/Storage backends to every repo
/// that needs cloud sync, resolving (or creating) their active logbook first.
/// Called on app start (if already signed in), on sign-in, and again on
/// reconnect if the earlier attempt never completed.
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
    // Retried: this read happens the instant after an auth state transition
    // (fresh sign-in, or right after switching accounts), when the ID token
    // backing it can still be settling — the same class of transient
    // failure retryWithBackoff already guards elsewhere in this app right
    // after an auth/logbook change (see LogbookService.listLogbooks and
    // logbook_switch.dart's reinitFirestore). Without this, a single
    // transient failure here aborts _initFirestore before anything is
    // attached, and since this function is fire-and-forget with no
    // user-facing error and no retry trigger other than a genuine
    // connectivity *change* event, the account can be left indefinitely
    // with no active logbook set — even though it was online the whole time.
    String? logbookId =
        await retryWithBackoff(() => logbookService.getActiveLogbookId(user.uid));
    if (logbookId == null) {
      logbookId = await logbookService.createLogbook(user.uid, 'My Logbook',
          displayName: user.displayName, email: user.email);
      // createLogbook deliberately never marks itself active (see its own
      // doc comment) — every other caller sets it explicitly only after
      // confirming a local switch succeeded. This *is* that confirmation:
      // this whole logbook was just created for this account, so there's
      // nothing to lose by making it active immediately. Skipping this
      // would leave the server thinking the account still has no active
      // logbook, so the next fresh sign-in (new device, reinstall) would
      // hit this same branch again and create yet another blank logbook.
      await logbookService.setActiveLogbook(user.uid, logbookId);
    }
    final firestore = await FirestoreService.create(logbookId);
    final storage = await StorageService.create(logbookId);
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
    // A local-mode user who just registered/signed in has fully upgraded
    // to cloud sync at this point — their local data was already pushed
    // above via initialSync.
    if (themeProvider.localModeEnabled) themeProvider.disableLocalMode();
  } catch (e, st) {
    reportNonFatal(e, st, reason: '_initFirestore failed');
  }
}

/// App entry point. Bootstraps, in order: date formatting locales, the map
/// tile cache, local Hive storage + adapters, the in-memory repositories,
/// Firebase (best-effort — the app must still run fully offline if this
/// fails), the router, and finally the widget tree itself.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Needed before any DateFormat/NumberFormat call using these locales.
  await initializeDateFormatting('de_CH');
  await initializeDateFormatting('en_GB');

  // Configure flutter_map's built-in disk tile cache before any tile is
  // fetched (by a map screen or the PDF exporter) — first caller otherwise
  // locks in the library defaults. 14 days is generous for coastlines/roads,
  // which change slowly; try/catch so a fresh install with no storage access
  // yet still starts with network-only tiles.
  try {
    BuiltInMapCachingProvider.getOrCreateInstance(
      overrideFreshAge: const Duration(days: 14),
    );
  } catch (_) {
    // Tile caching unavailable — tiles will still load, just uncached.
  }

  // --- Local storage: open Hive and register every model's typed adapter ---
  await Hive.initFlutter();

  Hive.registerAdapter(DayEntryAdapter());
  Hive.registerAdapter(TimelineEntryAdapter());
  Hive.registerAdapter(TimelineAmendmentAdapter());
  Hive.registerAdapter(DailyTrackAdapter());
  Hive.registerAdapter(TrackPointAdapter());
  Hive.registerAdapter(CrewMemberAdapter());
  Hive.registerAdapter(EmergencyContactAdapter());

  // --- Providers: local-only until Firebase attaches below. ThemeProvider
  // goes first so its localModeEnabled/activeLocalLogbookId are known before
  // deciding what (if any) local-logbook box suffix the other two repos
  // should open — see local_logbook_service.dart for the empty-string
  // sentinel convention. ---
  final themeProvider = ThemeProvider();
  await themeProvider.init();

  // A device with localModeEnabled=true but no activeLocalLogbookId predates
  // local multi-logbook support (or is mid-first-run, handled by
  // login_screen.dart's _continueOffline instead) — adopt today's base boxes
  // as the sentinel '' logbook. No data movement: '' already means "use the
  // unsuffixed boxes."
  if (themeProvider.localModeEnabled && themeProvider.activeLocalLogbookId == null) {
    final localLogbookService = LocalLogbookService();
    final logbooks = await localLogbookService.listLogbooks();
    final String id;
    if (logbooks.isEmpty) {
      await localLogbookService.createLogbookWithId('', 'My Logbook');
      id = '';
    } else {
      id = logbooks.first.$1;
    }
    await themeProvider.adoptActiveLocalLogbookId(id);
  }

  final localSuffix = themeProvider.localModeEnabled
      ? (themeProvider.activeLocalLogbookId!.isEmpty
          ? null
          : themeProvider.activeLocalLogbookId)
      : null;

  final repo = HomeRepository();
  await repo.init(datasetSuffix: localSuffix);

  final emergencyRepo = EmergencyRepository();
  await emergencyRepo.init(datasetSuffix: localSuffix);

  final authService = AuthService();

  final gpxShareService = GpxShareService();
  await gpxShareService.init();
  WidgetsBinding.instance.addObserver(_GpxResumeObserver(gpxShareService));

  final logbookIdNotifier = ValueNotifier<String?>(null);
  // True while reinitFirestore (logbook_switch.dart) is downloading a new
  // logbook's data — read by AppBottomNav to block navigating to another
  // tab mid-switch, since that tab's screen would otherwise render against
  // repositories that are mid-reattach (subscriptions cancelled, local
  // state not yet replaced).
  final logbookSwitchInProgressNotifier = ValueNotifier<bool>(false);

  // --- Firebase: best-effort. Any failure here leaves the app in offline
  // (Hive-only) mode rather than crashing, per the "must work with unstable
  // marine connectivity" requirement. ---
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);

    // Configure offline persistence immediately after init, before any reads.
    FirestoreService.configure();

    // Crash/error reporting — see docs/ci_and_crashlytics.md. Disabled in
    // debug builds so routine `flutter run` sessions and testing don't
    // pollute the Firebase console with noise from in-progress work.
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);

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

  // --- Router and root widget ---
  final router = buildRouter(themeProvider.lastRouteToday, authService, themeProvider);

  // Navigate to the import screen from anywhere in the app — using the router
  // directly avoids the issue of calling context.go from a non-top-level screen.
  gpxShareService.gpxFilePaths.listen((path) {
    router.goNamed(AppRoute.gpxImport, extra: path);
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
        ChangeNotifierProvider.value(value: logbookSwitchInProgressNotifier),
        Provider.value(value: gpxShareService),
        Provider(create: (_) => LocalLogbookService()),
      ],
      child: Logbook(router: router),
    ),
  );

  // Warm the tracks screen's computation cache in the background, after the
  // first frame, so it's already computed if/when the user opens it —
  // scheduled as idle-priority tasks so it never competes with real UI work.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    warmTracksCache(repo, themeProvider.filterSettings);
  });
}

/// Explicitly discards a fire-and-forget [Future], swallowing errors so an
/// unhandled-rejection warning doesn't fire for calls we intentionally don't
/// await (background init/retry tasks kicked off from `main()`).
void unawaited(Future<void> future) => future.catchError((_) {});
