# 1. Current State of the App

The Logbook app is an offline-first Flutter sailing logbook for iOS, macOS, and Android.
Multiple people can share one logbook (auth-gated, membership-based) via an 8-character
share code or QR code. Data is stored locally in Hive and synced to Cloud Firestore.

For what each source file does, see [Code Map](Code-Map). For the Firestore/Hive schema,
see [Data Model](Data-Model). For a walkthrough of each screen's behavior, see
[Features](Features).

---

## Technology stack

| Layer | Technology | Notes |
|-------|-----------|-------|
| Local storage | Hive (typed adapters) | DayEntry, TimelineEntry, TimelineAmendment, CrewMember, DailyTrack, TrackPoint, EmergencyContact |
| Cloud sync | Firebase Firestore + Storage | Auth-gated, keyed by `logbookId`; membership enforced by Firestore/Storage security rules |
| Auth | firebase_auth + google_sign_in + sign_in_with_apple | Email/password, Google, Apple — all three wired up and working |
| State management | provider (`ChangeNotifier`) | `HomeRepository`, `ThemeProvider`, `EmergencyRepository`, `AuthService` |
| Navigation | go_router | Flat route list, single auth-gating `redirect` |
| Maps | flutter_map + MapTiler | Nautical/satellite tiles via MapTiler API key — no policy-violating demo tile servers |
| Platform targets | iOS ✓ macOS ✓ Android ✓ | Android Firebase registered (`google-services.json` present, real appId) |
| Localization | flutter_localizations + intl, ARB-based | German (default) + English; `flutter gen-l10n` from `lib/l10n/app_{de,en}.arb` |
| Billing / IAP | None (deliberate) | See [Billing & Cost](Billing-and-Cost) — absorbing Firebase costs at current scale |

---

## Maturity notes

- **Localization** is complete for the main app. The Emergency Manifest's MAYDAY radio
  script is *deliberately* kept in English (SOLAS/IMO convention for maritime distress
  calls) — this is a permanent decision, not a gap. Locale-sensitive data (sail state,
  vessel status, keel position) is stored as language-neutral sentinel strings
  (`sail:full`, `vs:oil=75,fuel=60`, `vs:keel=down`) and rendered through `l10n` at
  display time — see `sail_state_utils.dart` — so switching languages doesn't leave
  stale text baked into old entries.
- **Testing** is thin: unit tests cover sentinel parsing and PDF string construction
  (`test/sail_state_utils_test.dart`), but there are no widget tests for core flows
  (add timeline entry, PDF export, account deletion) and no Crashlytics or equivalent
  crash reporting. See [Roadmap](Roadmap).
- **GPS track storage has no size cap** — every raw GPS fix is uploaded to Firebase
  Storage as-is. A long offshore passage can accumulate thousands of points; no
  decimation (e.g. Ramer–Douglas–Peucker) is applied before upload. See [Roadmap](Roadmap).

---

## Known platform issue

**iOS 26 + Xcode debug launch crashes (SIGKILL / signal 9).** Launching the app from
Xcode on iOS 26 kills the process before it reaches `main()`. Likely a Flutter/Xcode 26
JIT-debugging incompatibility, no upstream fix confirmed yet.

**Workaround:** use `flutter run -d {device_id}` from the terminal instead of the Xcode
"Run" button. This does not affect release builds or `flutter build`.
