# Roadmap — Remaining Work

Auth, multilingual support (German/English), Android Firebase registration, and the
MapTiler migration are all **done** — see [Architectural Decisions](Architectural-Decisions)
for what shipped vs. the original plan. What's left, roughly in priority order:

---

## Before App Store submission

1. **Privacy policy.** App Store requires a publicly accessible privacy policy URL for
   any app using Firebase Auth or collecting user data. Not yet published.
2. **Store assets.** Screenshots (all required sizes), app description, age rating,
   support URL.
3. **Verify Sign-In with Apple end-to-end.** The `com.apple.developer.applesignin`
   entitlement is present in `Runner.entitlements`, but do a full manual test of the
   Apple sign-in flow before submitting — entitlement presence alone doesn't confirm the
   provisioning profile / Apple Developer account state is fully correct.
4. **Resolve the iOS 26 + Xcode debug crash** (see [Current State](Current-State)) if it
   still blocks Xcode-based Instruments profiling or archiving — `flutter run` from the
   terminal is unaffected.

## Meaningful gaps

1. **No widget tests.** Existing tests (`test/sail_state_utils_test.dart`) cover pure
   sentinel/PDF-string logic only. The critical user flows — add timeline entry, export
   PDF, delete account — have no automated coverage. A widget test for the timeline entry
   dialog would catch the most common regressions.
2. **No crash reporting.** No Crashlytics or equivalent. A production crash is invisible
   unless the user reports it manually. Roughly a one-afternoon addition: add
   `firebase_crashlytics`, wire `FlutterError.onError` and
   `PlatformDispatcher.instance.onError` in `main.dart`.
3. **GPS track storage has no size cap.** Every raw GPS fix is uploaded as-is; a long
   offshore passage can accumulate thousands of points/day. Consider Ramer–Douglas–Peucker
   decimation before upload (keep full-fidelity data in Hive locally if ever needed) — see
   the GPX storage note in [Billing & Cost](Billing-and-Cost).
4. **PDF export silently drops failed photos.** If a photo fails to load during export,
   the PDF generates without it and the user gets no warning. A failure counter with a
   brief snackbar would surface this.

## Later, if/when needed

- Web subscription + token billing — only if Firebase cost recovery becomes necessary.
  See [Billing & Cost](Billing-and-Cost).
- Additional languages beyond German/English — the ARB infrastructure makes each new
  language mostly a translation task.
- Nautical chart enhancements — MapTiler's nautical style is already in use; an
  OpenSeaMap overlay for chart markers/buoys would build on it.
