import 'gpx_parser.dart';

class GpxDateResolution {
  final DateTime? resolvedDate;
  final bool isMultiDay;
  final List<DateTime> spannedDays;
  final int trackCount;
  // Mirrors GpxParseResult flags so the handler only needs one object.
  final bool hasRoutesOnly;
  final bool hasWaypointsOnly;
  final bool hasPointsWithoutTimestamps;

  const GpxDateResolution({
    required this.resolvedDate,
    required this.isMultiDay,
    required this.spannedDays,
    required this.trackCount,
    this.hasRoutesOnly = false,
    this.hasWaypointsOnly = false,
    this.hasPointsWithoutTimestamps = false,
  });
}

class GpxDateResolver {
  static GpxDateResolution resolve(GpxParseResult result) {
    if (result.hasRoutesOnly) {
      return GpxDateResolution(
        resolvedDate: null,
        isMultiDay: false,
        spannedDays: [],
        trackCount: result.sourceTrackCount,
        hasRoutesOnly: true,
      );
    }

    if (result.hasWaypointsOnly) {
      return GpxDateResolution(
        resolvedDate: null,
        isMultiDay: false,
        spannedDays: [],
        trackCount: result.sourceTrackCount,
        hasWaypointsOnly: true,
      );
    }

    if (result.hasPointsWithoutTimestamps) {
      return GpxDateResolution(
        resolvedDate: null,
        isMultiDay: false,
        spannedDays: [],
        trackCount: result.sourceTrackCount,
        hasPointsWithoutTimestamps: true,
      );
    }

    if (result.points.isEmpty) {
      return GpxDateResolution(
        resolvedDate: null,
        isMultiDay: false,
        spannedDays: [],
        trackCount: result.sourceTrackCount,
      );
    }

    // Collect distinct calendar dates in local time.
    final daySet = <DateTime>{};
    for (final p in result.points) {
      final local = p.time.toLocal();
      daySet.add(DateTime(local.year, local.month, local.day));
    }
    final days = daySet.toList()..sort();

    if (days.length == 1) {
      return GpxDateResolution(
        resolvedDate: days.first,
        isMultiDay: false,
        spannedDays: days,
        trackCount: result.sourceTrackCount,
      );
    }

    return GpxDateResolution(
      resolvedDate: days.first,
      isMultiDay: true,
      spannedDays: days,
      trackCount: result.sourceTrackCount,
    );
  }
}
