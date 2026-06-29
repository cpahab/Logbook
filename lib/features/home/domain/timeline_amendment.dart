import 'package:hive/hive.dart';

part 'timeline_amendment.g.dart';

// MIGRATION INVARIANT: Never change an existing @HiveField index or typeId.
// Retired indices must stay as tombstone comments so they are never reused.
// New fields must get the next unused index and be nullable.
@HiveType(typeId: 14)
class TimelineAmendment extends HiveObject {
  /// When the amendment was recorded.
  @HiveField(0)
  DateTime amendedAt;

  /// Optional explanation entered by the user.
  @HiveField(1)
  String? reason;

  // ── Snapshot of the entry BEFORE this amendment ───────────────────
  @HiveField(2)
  DateTime time;

  @HiveField(3)
  double? course;

  @HiveField(4)
  double? speed;

  @HiveField(5)
  String? wind;

  @HiveField(6)
  String? sea;

  @HiveField(7)
  String? weather;

  @HiveField(8)
  String? remarks;

  @HiveField(9)
  String? grossState;

  @HiveField(10)
  String? fockState;

  @HiveField(11)
  bool? motorOn;

  @HiveField(12)
  bool? keelDown;

  TimelineAmendment({
    required this.amendedAt,
    this.reason,
    required this.time,
    this.course,
    this.speed,
    this.wind,
    this.sea,
    this.weather,
    this.remarks,
    this.grossState,
    this.fockState,
    this.motorOn,
    this.keelDown,
  });

  /// Creates a snapshot from an existing [TimelineEntry]-like set of fields.
  factory TimelineAmendment.fromSnapshot({
    required DateTime amendedAt,
    String? reason,
    required DateTime time,
    double? course,
    double? speed,
    String? wind,
    String? sea,
    String? weather,
    String? remarks,
    String? grossState,
    String? fockState,
    bool? motorOn,
    bool? keelDown,
  }) =>
      TimelineAmendment(
        amendedAt: amendedAt,
        reason: reason,
        time: time,
        course: course,
        speed: speed,
        wind: wind,
        sea: sea,
        weather: weather,
        remarks: remarks,
        grossState: grossState,
        fockState: fockState,
        motorOn: motorOn,
        keelDown: keelDown,
      );
}
