# 1. Current State of the App

The Logbook app is a Flutter-based sailing logbook for iOS, macOS, and Android
(Android partially configured). It is currently used only by the developer.

The app stores data locally using Hive and optionally syncs to Firebase Firestore
using an installation-code model — two devices share a logbook by exchanging an
eight-character code. There is no user authentication.

---

## Technology Stack

| Layer | Technology | Notes |
|-------|-----------|-------|
| Local storage | Hive (typed adapters) | DayEntry, TimelineEntry, CrewMember, DailyTrack, EmergencyContact |
| Cloud sync | Firebase Firestore + Storage | Keyed by installationId — no auth required today |
| State management | provider 6.1.2 (ChangeNotifier) | 3 providers: HomeRepository, ThemeProvider, EmergencyRepository |
| Navigation | go_router 17.2.3 | Declarative routes, GoRouter redirect hooks available |
| Maps | flutter_map 8.0.0 | OSM tiles + Esri satellite — both require tile provider change before App Store |
| Auth package | firebase_auth (in pubspec) | Present but never wired up — zero auth code exists |
| Platform targets | iOS ✓  macOS ✓  Android ⚠ | Android Firebase not yet configured (placeholder appId) |
| Localization | flutter_localizations + intl | Hardcoded to de_CH — no ARB files, no l10n.yaml |
| Billing / IAP | None | Zero billing code exists |

---

## Key structural facts

- **Firestore path today:** `logbooks/{installationId}/entries/…`
- **Auth:** None — anyone who knows the installationId can read the logbook
- **Android:** `firebase_options.dart` contains a placeholder `appId`; `google-services.json` is missing
- **Maps:** OSM demo tile server is policy-prohibited for published apps; Esri satellite used without an API key
- **Sentinel issue:** The string `"Besatzung: "` is used both as display text and as a detection marker in code logic — must be split before any i18n work
