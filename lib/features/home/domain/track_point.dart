import 'package:hive/hive.dart';

part 'track_point.g.dart';

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
