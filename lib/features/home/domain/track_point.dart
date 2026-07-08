import 'package:hive/hive.dart';

part 'track_point.g.dart';

/// A single raw GPS fix (one trackpoint from a GPX file): latitude,
/// longitude, and timestamp. No decimation/filtering is applied — see
/// docs/GPS-Track-Filtering-Pipeline.docx for how a track built from these
/// points gets cleaned for display/stats.
@HiveType(typeId: 4)
class TrackPoint extends HiveObject {
  @HiveField(0)
  double lat;

  @HiveField(1)
  double lon;

  @HiveField(2)
  DateTime time;

  TrackPoint({
    required this.lat,
    required this.lon,
    required this.time,
  });
}
