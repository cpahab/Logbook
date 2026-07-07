import 'package:flutter/scheduler.dart';

import '../../home/data/home_repository.dart';
import '../../home/utils/filter_settings.dart';
import 'track_computation_cache.dart';

/// Pre-computes and caches display models/stats for the tracks screen's
/// default view (its `month1` filter preset) so that, if and when the user
/// opens it, the data is already warm instead of computing cold on first
/// visit. Call once at startup, after the app's first frame.
///
/// Each day's computation runs as its own idle-priority scheduler task
/// rather than in one batch, so this never competes with real UI work —
/// it only runs between frames, and yields immediately if the user
/// navigates to the tracks screen before it's done (that visit just
/// computes normally, same as before this existed).
void warmTracksCache(HomeRepository repo, FilterSettings settings) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month - 1, now.day);

  final days = repo.dailyTracks.entries
      .where((e) => !e.key.isBefore(start) && e.value.points.isNotEmpty)
      .map((e) => e.key)
      .toList();

  for (final day in days) {
    SchedulerBinding.instance.scheduleTask<void>(
      () {
        final track = repo.dailyTracks[day];
        if (track == null || track.points.isEmpty) return;
        TrackComputationCache.get(
          day: day,
          sourcePoints: track.points,
          settings: settings,
        );
      },
      Priority.idle,
    );
  }
}
