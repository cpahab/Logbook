# Logbook

A cross-platform sailing logbook app built with Flutter. Track your GPS route, log daily entries (crew, weather, course, notes), keep an emergency manifest and radio (MAYDAY) protocol on hand, and sync everything across devices.

Runs on Android, iOS, macOS, and Web.

---

## ✨ Features

- **Daily journal** — log entries per day (crew, weather, course, sail state, remarks), with a full amendment history for past-day edits
- **GPS tracks** — import/export GPX, view routes on the map, computed stats (distance, duration, speed)
- **Emergency manifest** — crew medical info, vessel safety equipment, VHF frequencies
- **Radio protocol (MAYDAY)** — step-by-step distress-call guide with live position lookup
- **PDF export** — generate a printable logbook record
- **Multi-device sync** — Firebase Auth + Firestore, with offline support
- **Light/dark themes** — a shared design system (see [Theming](#-theming))

---

## 📁 Project Structure

```text
lib/
├── app/                  # Global app configuration
│   ├── router.dart       # GoRouter setup
│   ├── route_names.dart  # Named-route constants
│   └── theme/            # Light/dark themes + shared extensions
│
├── core/                 # Shared utilities & services
│   ├── config/           # Environment/build configuration
│   ├── constants/        # App-wide constants (map config, etc.)
│   ├── errors/           # Exceptions & failures
│   └── services/         # Auth, Firestore, storage, GPS consent, ...
│
├── features/             # Feature-first modules
│   ├── auth/             # Sign in / register / email verification
│   ├── emergency/        # Emergency manifest + MAYDAY radio protocol
│   ├── home/              # Daily journal, timeline entries, crew roster
│   ├── settings/          # Vessel info, VHF channels, app preferences
│   └── tracks/             # GPX tracks, map view, track stats
│
└── l10n/                 # Localized strings (English + German)
```

Each feature generally follows:

```text
data/          → repositories, data sources
domain/        → models
presentation/  → screens
widgets/       → feature-local widgets
```

---

## 🚀 Getting Started

### 1. Install dependencies

```bash
flutter pub get
```

### 2. Run the app

```bash
flutter run
```

### 3. Run on a specific platform

```bash
flutter run -d chrome
flutter run -d macos
flutter run -d ios
flutter run -d android
```

> **Note (Xcode/iOS 26 simulators):** launching via Xcode's debugger can trigger a SIGKILL on some iOS 26 simulators. Use `flutter run` directly if that happens.

---

## 🧭 Routing

Routing is handled by **GoRouter**, configured in `lib/app/router.dart` with named routes declared in `lib/app/route_names.dart`. Add new screens by extending the `routes:` list and giving them a name in `AppRoute`.

---

## 🎨 Theming

Themes live in `lib/app/theme/`:

- `light_theme.dart` / `dark_theme.dart` — color scheme + `TextTheme` definitions
- `theme_extensions.dart` — shared `ColorScheme`/`TextTheme` extension getters for roles that don't map to a stock Material role (e.g. section-header colors, compact/prose field text styles)

Screens and widgets should always pull colors and text styles from the theme rather than hardcoding them — add a new extension getter here if an existing role doesn't fit.

---

## 🧪 Testing

Unit tests live in `test/` (with fixtures in `test/fixtures/`). Run them with:

```bash
flutter test
```

---

## 🤖 CI & Crash Reporting

Every push/PR to `main` runs `flutter analyze` + `flutter test` via
[GitHub Actions](.github/workflows/ci.yml). Real-device errors (uncaught
Dart exceptions, native crashes) are reported to Firebase Crashlytics —
disabled in debug builds, so a normal `flutter run` session stays quiet.
See [`docs/ci_and_crashlytics.md`](docs/ci_and_crashlytics.md) for what
each one catches, how to view a Crashlytics report, and how to reproduce
a CI failure locally.

---

## 📦 Building Release Versions

### Android

```bash
flutter build apk --release
flutter build appbundle --release
```

### iOS (requires macOS)

```bash
flutter build ios --release
```

### macOS

```bash
flutter build macos --release
```

### Web

```bash
flutter build web
```

---

## 🔄 Branching

This repo works directly off `main` — no `develop`/`release`/`hotfix` branches. Cut a short-lived `feature/*` branch for larger changes if you want review before merging, otherwise commit straight to `main`.

---

## 📄 License

Private project — not published to pub.dev (`publish_to: 'none'` in `pubspec.yaml`). No open-source license is currently granted.
