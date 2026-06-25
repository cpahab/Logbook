# App Status & Next Steps — 2026-06-25

## What is in good shape

- **Localisation architecture** — sentinel/l10n separation is solid. Adding a new
  language only requires a new ARB file; no Dart changes needed.
- **Offline handling** — Firestore bootstrap-from-cache and the amber offline
  banner work correctly.
- **Firestore / Storage rules** — `isMember()` cross-service check is in place.
- **PDF export** — cleanly separated from the UI via `PdfStrings`; pure Dart,
  no `BuildContext` dependency.
- **Unit tests** — 20 tests cover all sentinel parsing and `PdfStrings`
  construction without requiring a device or network.

---

## Known blocker: iOS 26 + Xcode launch crash

Launching the app from Xcode on iOS 26 causes a SIGKILL (signal 9) before the
app reaches `main()`. Workaround: use `flutter run` from the terminal instead.

This must be resolved before you can archive for distribution or use Xcode
Instruments for profiling. Likely cause: a Flutter / Xcode 26 incompatibility.
Check for a newer Flutter SDK release or open Flutter GitHub issues for
"iOS 26 SIGKILL" before investing time debugging.

---

## Before App Store submission

1. **Apple Sign-In** — the entitlement was removed because a paid Apple Developer
   account is not yet active. Re-add `com.apple.developer.applesignin` and test
   the full Sign-In with Apple auth flow before submitting.
2. **Privacy policy** — App Store requires a publicly accessible privacy policy
   URL for any app using Firebase Auth or collecting user data.
3. **Store assets** — screenshots in all required sizes, an app description, age
   rating, and support URL must be prepared before first submission.

---

## Meaningful gaps to address

### 1. No widget tests

The 20 unit tests cover pure logic only. The critical user flows — add timeline
entry, export PDF, delete account — have no automated test coverage. A basic
widget test for the timeline entry dialog would catch the most common
regressions.

Suggested starting point:
```
test/widgets/add_timeline_entry_dialog_test.dart
```

### 2. Hive schema migration is fragile

The tombstone comment convention (never reuse a `@HiveField` index) is
documented in `day_entry.dart` and works for additive changes. However, if a
field type ever needs to change — not just adding a nullable field — the adapter
will silently deserialise garbage without crashing. There is no runtime
migration guard.

Keep this in mind if the data model ever needs a non-additive change. The safe
path is always: add a new field at the next index, migrate data on first read,
retire the old index as a tombstone.

### 3. GPS track storage has no size cap

Each track writes every raw GPS coordinate to Firestore. A long offshore passage
can accumulate thousands of points per day. At scale this increases read costs
and slows the track map.

Consider applying Ramer-Douglas-Peucker decimation before writing to Firestore,
keeping only enough points to faithfully represent the route. The raw data can
still be kept locally in Hive if full fidelity is ever needed.

### 4. PDF export silently drops failed photos

If a photo fails to load during export, the PDF is generated without it and the
user sees no warning. A counter of failed loads with a brief snackbar or dialog
("2 photos could not be loaded") would make failures visible.

### 5. No crash reporting

There is no Crashlytics or equivalent in place. Any crash in production will be
invisible unless the user reports it manually.

Firebase Crashlytics is a one-afternoon addition:
- Add `firebase_crashlytics` to `pubspec.yaml`
- Wire `FlutterError.onError` and `PlatformDispatcher.instance.onError` in
  `main.dart`
- Optionally add breadcrumbs at key navigation points

This will give immediate visibility into real-world failures that are impossible
to reproduce locally.

---

## Suggested order of next steps

| # | Task | Effort |
|---|---|---|
| 1 | Merge `claude/version-tag-status-94c3n6` → `main` | 5 min |
| 2 | Investigate iOS 26 / Xcode SIGKILL crash | Unknown — check Flutter issues first |
| 3 | Add Firebase Crashlytics | ~2 hours |
| 4 | Write widget test for timeline entry dialog | ~half day |
| 5 | Activate Apple Developer account, re-add Sign-In with Apple entitlement | Depends on account |
| 6 | Prepare App Store assets and submit | ~1 day |
