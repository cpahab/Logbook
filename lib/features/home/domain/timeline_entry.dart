import 'package:hive/hive.dart';

part 'timeline_entry.g.dart';

@HiveType(typeId: 2)
class TimelineEntry extends HiveObject {
  @HiveField(0)
  DateTime time;

  @HiveField(1)
  double? course; // degrees

  @HiveField(2)
  double? speed; // knots

  @HiveField(3)
  String? wind; // e.g. "SW 12kt"

  @HiveField(4)
  String? sea; // e.g. "Calm", "Moderate"

  @HiveField(5)
  String? weather; // e.g. "Sunny", "Rain", "Overcast"

  @HiveField(6)
  String? remarks;

  // @HiveField(7)  fockUp      — retired (replaced by fockState)
  // @HiveField(8)  grossUp     — retired (replaced by grossState)
  // @HiveField(9)  reff1Fock   — retired
  // @HiveField(10) reff1Gross  — retired
  // @HiveField(11) reff2Fock   — retired
  // @HiveField(12) reff2Gross  — retired

  @HiveField(13)
  bool? motorOn; // true = an, false = aus

  @HiveField(14)
  String? grossState;

  @HiveField(15)
  String? fockState;

  /// Auto-populated when a system event (e.g. vessel status change) generates
  /// this entry. Shown as clear text below the regular remarks.
  @HiveField(16)
  String? vesselStatusNote;

  /// Keel position at the time of this log entry.
  /// true = keel down (sailing), false = keel up (shoal), null = not recorded.
  @HiveField(17)
  bool? keelDown;

  TimelineEntry({
    required this.time,
    this.course,
    this.speed,
    this.wind,
    this.sea,
    this.weather,
    this.remarks,
    this.motorOn,
    this.grossState,
    this.fockState,
    this.vesselStatusNote,
    this.keelDown,
  });
}
