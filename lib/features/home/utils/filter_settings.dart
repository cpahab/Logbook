/// User preferences for the GPX track filter.
/// Stored locally (Hive settings box) and synced via [ThemeProvider] to the
/// active logbook's Firestore settings doc, so the tuning is shared across
/// everyone on the logbook and roams between one user's own devices.
library;

enum StationaryMode {
  /// A fix is stationary when the centred window speed is below
  /// [FilterSettings.speedThresholdKn].  A boat swinging at anchor (≈0 speed
  /// but wide arc) still collapses to a single position marker.
  speed,

  /// Stricter: a fix is stationary only when BOTH window speed AND window
  /// positional spread are below their thresholds.  A wide anchor swing is NOT
  /// collapsed to one marker.  Use for anchor-watch / "held position" display.
  both,
}

class FilterSettings {
  /// Which stationary-detection mode to apply.
  final StationaryMode stationaryMode;

  /// Centred window speed (knots) below which the boat is "not making way".
  final double speedThresholdKn;

  /// Mean positional spread (metres) below which the boat is "holding position"
  /// — only consulted in [StationaryMode.both].
  final double spreadThresholdM;

  /// Half-width in *fixes* of the centred window used for the speed and spread
  /// signals.
  final int window;

  /// Sliding-median window for the kept moving track.  1 = off, 3 = light
  /// smoothing (default), 5 = heavier.
  final int smoothWindow;

  /// Minimum duration (minutes) a stationary run must last to be treated as a
  /// genuine stop rather than a transient slowdown (tacking, lull).
  final double minStopMinutes;

  /// Maximum radius (metres) of the whole stationary cluster.  Rejects slow
  /// drifting-in-light-air which crosses below the speed threshold while still
  /// covering hundreds of metres.  Wide overnight anchor swings may exceed this
  /// (see settings UI note).
  final double maxStopSpreadM;

  /// Whether to detect and strip GPS cold-start convergence fixes at the track
  /// start (coarse positions before the receiver has a solid satellite lock).
  final bool detectColdStart;

  /// How far (in settled-cloud std-devs) a leading fix must be from the settled
  /// berth position to count as a cold-start fix.  Lower = more aggressive.
  final double coldStartSettleFactor;

  /// Whether to detect and flag a single wrong GPS position at fix[0] that sits
  /// far from where the receiver settled immediately after.  Observed in 3 of 9
  /// real logs (28 Jun 256 m off, 18 Apr 89 m, 02 May 75 m).  Distinct from
  /// cold-start: this is one outlier that snaps to the correct position at fix[1],
  /// not a gradual convergence over several fixes.
  final bool detectBadFirstFix;

  /// Minimum speed (knots) for a fix to count toward the "making-way" average.
  /// Drifting / motoring slowly below this threshold is excluded.
  final double makingWayThresholdKn;

  /// Percentile (0–1) of instantaneous moving speeds used as the reported
  /// "max speed".  1.0 = true maximum; 0.99 = p99 (suppresses lone GPS spikes).
  final double topSpeedPercentile;

  /// Hard speed ceiling (knots) for spike detection: any moving fix faster
  /// than this is always flagged as an implausible GPS glitch, regardless of
  /// the boat's own recent speed distribution. Default (12 kn) suits typical
  /// cruising sailboats; racing yachts / foilers / powerboats need a higher
  /// value or spikes will be false-flagged during genuinely fast runs.
  final double maxSpeedKn;

  const FilterSettings({
    this.stationaryMode        = StationaryMode.speed,
    this.speedThresholdKn      = 0.5,
    this.spreadThresholdM      = 6.0,
    this.window                = 5,
    this.smoothWindow          = 3,
    this.minStopMinutes        = 5.0,
    this.maxStopSpreadM        = 30.0,
    this.detectColdStart       = true,
    this.coldStartSettleFactor = 3.0,
    this.detectBadFirstFix     = true,
    this.makingWayThresholdKn  = 1.0,
    this.topSpeedPercentile    = 0.99,
    this.maxSpeedKn            = 12.0,
  });

  // Value equality — the settings live behind a getter that constructs a new
  // instance on every access, so callers that want to detect "did this
  // actually change" (e.g. to invalidate a cache) need this instead of
  // identity.
  @override
  bool operator ==(Object other) =>
      other is FilterSettings &&
      stationaryMode == other.stationaryMode &&
      speedThresholdKn == other.speedThresholdKn &&
      spreadThresholdM == other.spreadThresholdM &&
      window == other.window &&
      smoothWindow == other.smoothWindow &&
      minStopMinutes == other.minStopMinutes &&
      maxStopSpreadM == other.maxStopSpreadM &&
      detectColdStart == other.detectColdStart &&
      coldStartSettleFactor == other.coldStartSettleFactor &&
      detectBadFirstFix == other.detectBadFirstFix &&
      makingWayThresholdKn == other.makingWayThresholdKn &&
      topSpeedPercentile == other.topSpeedPercentile &&
      maxSpeedKn == other.maxSpeedKn;

  @override
  int get hashCode => Object.hash(
        stationaryMode,
        speedThresholdKn,
        spreadThresholdM,
        window,
        smoothWindow,
        minStopMinutes,
        maxStopSpreadM,
        detectColdStart,
        coldStartSettleFactor,
        detectBadFirstFix,
        makingWayThresholdKn,
        topSpeedPercentile,
        maxSpeedKn,
      );
}
