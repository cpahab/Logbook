/// User preferences for the GPX track filter.
/// Stored locally (Hive settings box); not cloud-synced since it is a
/// per-device display preference.
///
/// Only [stationaryMode] is exposed in the settings UI; the other knobs are
/// "advanced" defaults that were validated against the six real Idefix trips in
/// the Python reference implementation and should rarely need changing.
library;

enum StationaryMode {
  /// A fix is stationary when the centred window speed is below
  /// [FilterSettings.speedThresholdKn].  A boat swinging at anchor (≈0 speed
  /// but wide arc) still collapses to a single position marker — this is the
  /// "berth / anchor" intent.
  speed,

  /// Stricter: a fix is stationary only when BOTH window speed AND window
  /// positional spread are below their thresholds.  A wide anchor swing is NOT
  /// collapsed to one marker; the cluster is trimmed only for truly tight holds.
  /// Use for anchor-watch / "held position" style display.
  both,
}

class FilterSettings {
  /// Which stationary-detection mode to apply at the track ends.
  final StationaryMode stationaryMode;

  /// Centred window speed (knots) below which the boat is "not making way".
  final double speedThresholdKn;

  /// Mean positional spread (metres) below which the boat is "holding position"
  /// — only consulted in [StationaryMode.both].
  final double spreadThresholdM;

  /// Half-width in *fixes* of the centred window used for the speed and spread
  /// signals.  With a typical 20-second fix interval, window = 5 covers ±100 s;
  /// at 60-second intervals it covers ±300 s.
  final int window;

  /// Sliding-median window for the kept moving track.  1 = off, 3 = light
  /// smoothing (default), 5 = heavier.
  final int smoothWindow;

  const FilterSettings({
    this.stationaryMode   = StationaryMode.speed,
    this.speedThresholdKn = 0.5,
    this.spreadThresholdM = 6.0,
    this.window           = 5,
    this.smoothWindow     = 3,
  });
}
