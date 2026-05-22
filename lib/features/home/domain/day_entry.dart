import 'package:hive/hive.dart';
import 'timeline_entry.dart';
import 'track_point.dart';

part 'day_entry.g.dart';

@HiveType(typeId: 11)
class DayEntry extends HiveObject {
  @HiveField(0)
  DateTime date;

  @HiveField(1)
  List<TimelineEntry> timeline;

  @HiveField(2)
  List<TrackPoint> track;

  @HiveField(3)
  bool hasGpx;

  @HiveField(4)
  String? fromHarbor;

  @HiveField(5)
  String? toHarbor;

  // Statistics
  @HiveField(6)
  double distanceNm;

  @HiveField(7)
  int totalDurationSeconds;

  @HiveField(8)
  int movingDurationSeconds;

  @HiveField(9)
  double avgSpeedKnots;

  @HiveField(10)
  double maxSpeedKnots;
  

  DayEntry({
    required this.date,
    this.timeline = const [],
    this.track = const [],
    this.hasGpx = false,
    this.fromHarbor,
    this.toHarbor,
    this.distanceNm = 0.0,
    this.totalDurationSeconds = 0,
    this.movingDurationSeconds = 0,
    this.avgSpeedKnots = 0.0,
    this.maxSpeedKnots = 0.0,
  });

  // Convenience getters
  Duration get totalDuration => Duration(seconds: totalDurationSeconds);
  Duration get movingDuration => Duration(seconds: movingDurationSeconds);

  set totalDuration(Duration d) => totalDurationSeconds = d.inSeconds;
  set movingDuration(Duration d) => movingDurationSeconds = d.inSeconds;
}
