/// Retries [attempt] on failure with backoff, then makes one final
/// unguarded attempt (whose exception propagates if it also fails).
///
/// Exists for the "right after joining/creating a logbook" race: Firestore
/// security rules aren't always evaluated with the same immediacy as the
/// write they check (e.g. a membership doc just created by [joinLogbook]),
/// so a server read attempted the instant after can transiently fail with
/// no real, lasting cause. Delays: 500ms, 1s, 2s, 4s, 7s — ~15s worst case.
Future<T> retryWithBackoff<T>(Future<T> Function() attempt) async {
  const delays = [
    Duration(milliseconds: 500),
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 7),
  ];
  for (final delay in delays) {
    try {
      return await attempt();
    } catch (_) {
      await Future.delayed(delay);
    }
  }
  return await attempt();
}
