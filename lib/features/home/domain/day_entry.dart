import 'package:hive/hive.dart';
import 'timeline_entry.dart';
import 'track_point.dart';
import 'crew_member.dart';

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

  @HiveField(11)
  String? participants;

  @HiveField(12)
  String? controlled;

  @HiveField(13)
  List<String> participantsList;

  @HiveField(14)
  List<String> checkedItems;

  @HiveField(15)
  String? notes;

  @HiveField(16)
  int? oilLevel; // 0–100

  @HiveField(17)
  int? fuelLevel; // 0–100

  @HiveField(18)
  List<CrewMember> crew;

  @HiveField(19)
  String? freeText;

  /// Retractable keel position. true = keel down (sailing), false = keel up
  /// (shallow water / harbour). null = not yet recorded.
  @HiveField(20)
  bool? keelDown;

  /// Firebase Storage paths for photos attached to this day (e.g.
  /// "photos/2026-06-16/1718440000000.jpg"). Local cache is managed by
  /// PhotoService.
  @HiveField(21)
  List<String> photos;

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
    this.participants,
    this.controlled,
    List<String>? participantsList,
    List<String>? checkedItems,
    this.notes,
    this.oilLevel,
    this.fuelLevel,
    List<CrewMember>? crew,
    this.freeText,
    this.keelDown,
    List<String>? photos,
  })  : participantsList = participantsList ?? <String>[],
        checkedItems = checkedItems ?? <String>[],
        crew = crew ?? <CrewMember>[],
        photos = photos ?? <String>[];

  // Convenience getters
  Duration get totalDuration => Duration(seconds: totalDurationSeconds);
  Duration get movingDuration => Duration(seconds: movingDurationSeconds);

  set totalDuration(Duration d) => totalDurationSeconds = d.inSeconds;
  set movingDuration(Duration d) => movingDurationSeconds = d.inSeconds;
}
