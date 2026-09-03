import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Reports [error] to Crashlytics as a non-fatal issue, if Firebase is
/// available. Never throws itself — several call sites (local-only mode,
/// or a device that's never signed in) run with Firebase never
/// initialized at all, and this must not turn a "log this and move on"
/// error site into a new crash.
void reportNonFatal(Object error, StackTrace stack, {String? reason}) {
  if (Firebase.apps.isEmpty) return;
  FirebaseCrashlytics.instance
      .recordError(error, stack, reason: reason, fatal: false);
}

/// Logs [message] as a Crashlytics breadcrumb, if Firebase is available.
/// Same no-op-when-unavailable guarantee as [reportNonFatal].
void logBreadcrumb(String message) {
  if (Firebase.apps.isEmpty) return;
  FirebaseCrashlytics.instance.log(message);
}
