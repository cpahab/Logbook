import 'package:hive/hive.dart';
import 'timeline_amendment.dart';

part 'timeline_entry.g.dart';

/// One logged moment within a [DayEntry]'s timeline (e.g. departure,
/// arrival, an in-transit update): course/speed/wind/sea/weather/sail state
/// at that time, plus an ordered history of prior-state snapshots in
/// [amendments] whenever a past entry is edited.
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
  // @HiveField(13) motorOn     — retired (replaced by slot11State)
  // @HiveField(14) grossState  — retired (replaced by slot1State)
  // @HiveField(15) fockState   — retired (replaced by slot2State)

  /// Auto-populated when a system event (e.g. vessel status change) generates
  /// this entry. Shown as clear text below the regular remarks.
  @HiveField(16)
  String? vesselStatusNote;

  // @HiveField(17) keelDown    — retired (replaced by slot12State)

  /// Set once when the entry is first created. Never overwritten.
  @HiveField(18)
  DateTime? createdAt;

  /// Updated on every subsequent edit. Null until the first edit after creation.
  @HiveField(19)
  DateTime? updatedAt;

  /// Ordered list of snapshots, oldest first. Each snapshot captures the full
  /// state of this entry immediately before an amendment was applied.
  @HiveField(20)
  List<TimelineAmendment> amendments;

  // Slots 1–10: sails (user-defined names and states).
  // Stores the user-defined state label chosen at entry time; null if not recorded.
  @HiveField(21) String? slot1State;   // typically main sail
  @HiveField(22) String? slot2State;   // typically jib / foresail
  @HiveField(23) String? slot3State;
  @HiveField(24) String? slot4State;
  @HiveField(25) String? slot5State;
  @HiveField(26) String? slot6State;
  @HiveField(27) String? slot7State;
  @HiveField(28) String? slot8State;
  @HiveField(29) String? slot9State;
  @HiveField(30) String? slot10State;

  // Slot 11: motor / engine.
  @HiveField(31) String? slot11State;

  // Slot 12: keel.
  @HiveField(32) String? slot12State;

  TimelineEntry({
    required this.time,
    this.course,
    this.speed,
    this.wind,
    this.sea,
    this.weather,
    this.remarks,
    this.vesselStatusNote,
    this.createdAt,
    this.updatedAt,
    List<TimelineAmendment>? amendments,
    this.slot1State,
    this.slot2State,
    this.slot3State,
    this.slot4State,
    this.slot5State,
    this.slot6State,
    this.slot7State,
    this.slot8State,
    this.slot9State,
    this.slot10State,
    this.slot11State,
    this.slot12State,
  }) : amendments = amendments ?? [];
}
