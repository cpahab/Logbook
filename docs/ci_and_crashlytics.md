# CI and crash reporting

Two independent pieces of "catch problems automatically" infrastructure,
added together but unrelated to each other:

- **CI** (`.github/workflows/ci.yml`) catches issues *before* a bad change
  ships — static analysis errors and failing tests, on every push.
- **Crashlytics** (`firebase_crashlytics`) catches issues *after* a build is
  running on a real device — uncaught errors that only show up with real
  data, real connectivity, or a real crew member's phone.

Neither replaces the other. CI can't catch a bug that only reproduces with
real GPS drift or a flaky marine connection; Crashlytics can't catch a bug
before it ships.

## CI (GitHub Actions)

`.github/workflows/ci.yml` runs on every push to `main` and every pull
request targeting `main`:

1. `flutter pub get`
2. `flutter analyze`
3. `flutter test`

### Where to see results

github.com/cpahab/Logbook → **Actions** tab — every run, its logs, and
pass/fail status. On a pull request, the same result also shows inline as
a check at the bottom of the PR. (Only pushed commits trigger a run — a
local, uncommitted, or unpushed branch has nothing to show yet.)

No secrets or `--dart-define` values are needed for this — `analyze` and
`test` never touch the MapTiler API key or any other build-time constant
(`kMapTilerApiKey` in `lib/core/constants/map_config.dart` defaults to an
empty string when the define is absent, and no test depends on real tiles
loading).

**If a CI run fails**, the failure is real — reproduce it locally with the
exact same commands:

```bash
flutter pub get
flutter analyze
flutter test
```

**The Flutter version is pinned** (currently `3.44.1`, matching whichever
version was used for local development when this was set up) rather than
tracking `stable` automatically. This is deliberate: a moving target would
mean CI could start failing from a Flutter upgrade with no code change at
all, on a schedule nobody controls. Bump the pin in `ci.yml` deliberately,
in the same commit as (or right after) upgrading Flutter locally — check
`flutter --version` for the version to use.

**What this doesn't check**: it doesn't build the app for any platform
(no `flutter build ios`/`apk`/etc.), since that needs platform-specific
runners, signing, and takes much longer. A green CI run means the Dart
code is sound and every existing test still passes — it does not mean the
app actually builds and launches on a device. Still do that manually (or
ask for it) before a release.

## Crashlytics

`firebase_crashlytics` reports two kinds of problems to the Firebase
console, wired up in `lib/main.dart` right after `Firebase.initializeApp()`:

- **`FlutterError.onError`** — fatal errors inside the Flutter framework
  itself (a widget that throws during build/layout/paint).
- **`PlatformDispatcher.instance.onError`** — uncaught errors anywhere else
  in Dart code (e.g. an unhandled exception in an unawaited `Future`).

Both existed as silent failures before this: an error thrown outside of
Flutter's own error boundary would previously just vanish into the void
(or print to a console nobody's watching on a real user's phone) instead
of showing up anywhere.

It also automatically captures **native crashes** (a Swift/Kotlin-level
crash, not a Dart exception) via the underlying platform SDK — no extra
Dart code needed for that part.

### Where to see reports

console.firebase.google.com → project **`logbook-b19ed`** (the production
project every real Android/iOS/macos/Windows build uses —
see `lib/firebase_options.dart`) → **Crashlytics** in the left sidebar.
Android and iOS reports land in the same dashboard, grouped by crash
signature, with device/OS/app-version breakdowns.

Nothing appears there until two things are both true: a **release or
profile build** has run (debug builds don't report — see below), and that
build has actually hit an error. A fresh Crashlytics setup with no crashes
yet just shows an empty dashboard, not an error.

### Disabled in debug builds, on purpose

`FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode)`
means a normal `flutter run` session — including bugs you're actively
introducing and fixing while developing — never reaches the dashboard.
Only release/profile builds report. This keeps the console signal
representative of what's actually shipped, not noise from in-progress work.

**To verify it's working**, you need a non-debug build (collection is
disabled otherwise):

```bash
flutter run --release
```

Then trigger a real crash (e.g. temporarily add a button that calls
`FirebaseCrashlytics.instance.crash()`) and confirm it appears in the
Firebase console within a few minutes — remove the test button afterward.

### iOS native-crash symbolication (dSYM upload)

The Xcode project (`ios/Runner.xcodeproj`) has a "Crashlytics" Run Script
build phase (added via the `xcodeproj` Ruby gem, not by hand — the
`.pbxproj` format is fragile to edit as text) that uploads debug symbols
after each build:

```
"${PODS_ROOT}/FirebaseCrashlytics/run"
```

This needs the `FirebaseCrashlytics` CocoaPod present, which `pod install`
(run automatically by `flutter build ios`/`flutter run` on iOS) provides.
Without this phase, native (Swift-level) crashes would still be reported,
just unsymbolicated — raw memory addresses instead of file/line/function
names. Dart-level errors (the two handlers above) don't need this at all;
they already carry a readable Dart stack trace.

No equivalent manual step exists for Android — the Gradle plugin
(`com.google.firebase.crashlytics`, wired into `android/app/build.gradle.kts`
and declared in `android/settings.gradle.kts`) handles symbol upload as
part of the normal Gradle build.
