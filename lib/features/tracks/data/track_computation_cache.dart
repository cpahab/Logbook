import '../../home/domain/track_point.dart';
import '../../home/utils/compute_daily_stats.dart';
import '../../home/utils/filter_settings.dart';
import '../../home/utils/trim_track.dart';

/// Caches the two expensive per-day computations — buildDisplayModel() does
/// trimming/segmentation/smoothing, computeDailyStats() derives distance/
/// speed stats — keyed by day, source-points identity, and filter settings.
/// [HomeRepository] always replaces a day's points list wholesale on edit
/// (never mutates in place), so `identical()` reliably detects "unchanged."
///
/// A process-wide cache, not scoped to any screen, so it can be warmed in
/// the background before the tracks screen is ever visited (see
/// warm_tracks_cache.dart) and survives that screen being recreated on
/// every bottom-nav visit.
class TrackComputationCache {
  TrackComputationCache._();

  static final Map<DateTime, _Entry> _cache = {};

  /// Returns the cached (display, stats) pair for [day] if [sourcePoints]
  /// and [settings] match what's cached; computes and caches it otherwise.
  static ({DisplayModel display, DailyStats stats}) get({
    required DateTime day,
    required List<TrackPoint> sourcePoints,
    required FilterSettings settings,
  }) {
    final cached = _cache[day];
    if (cached != null &&
        identical(cached.sourcePoints, sourcePoints) &&
        cached.settings == settings) {
      return (display: cached.display, stats: cached.stats);
    }
    final display = buildDisplayModel(sourcePoints, settings: settings);
    final stats = computeDailyStats(sourcePoints, settings: settings);
    _cache[day] = _Entry(
      sourcePoints: sourcePoints,
      settings: settings,
      display: display,
      stats: stats,
    );
    return (display: display, stats: stats);
  }
}

/// One cached (display, stats) pair plus the inputs that produced it, so a
/// cache hit can be validated by identity/equality before reuse.
class _Entry {
  final List<TrackPoint> sourcePoints;
  final FilterSettings settings;
  final DisplayModel display;
  final DailyStats stats;

  const _Entry({
    required this.sourcePoints,
    required this.settings,
    required this.display,
    required this.stats,
  });
}
