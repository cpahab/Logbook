import 'package:hive/hive.dart';

part 'timeline_amendment.g.dart';

// MIGRATION INVARIANT: Never change an existing @HiveField index or typeId.
// Retired indices must stay as tombstone comments so they are never reused.
// New fields must get the next unused index and be nullable.
/// A snapshot of a timeline entry's prior state, recorded whenever a past
/// day's log entry is edited — the audit trail shown on that entry, not a
/// live editable record itself.
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

  // @HiveField(9)  grossState — retired (replaced by slot1State)
  // @HiveField(10) fockState  — retired (replaced by slot2State)
  // @HiveField(11) motorOn    — retired (replaced by slot11State)
  // @HiveField(12) keelDown   — retired (replaced by slot12State)

  // Slots 1–10: sails; slot 11: motor; slot 12: keel. Mirrors
  // TimelineEntry.slot1State..slot12State — see that class for details.
  @HiveField(13) String? slot1State;
  @HiveField(14) String? slot2State;
  @HiveField(15) String? slot3State;
  @HiveField(16) String? slot4State;
  @HiveField(17) String? slot5State;
  @HiveField(18) String? slot6State;
  @HiveField(19) String? slot7State;
  @HiveField(20) String? slot8State;
  @HiveField(21) String? slot9State;
  @HiveField(22) String? slot10State;
  @HiveField(23) String? slot11State;
  @HiveField(24) String? slot12State;

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
  });

  /// Creates a snapshot from an existing TimelineEntry's field values,
  /// taken just before those values are overwritten by an edit.
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
    String? slot1State,
    String? slot2State,
    String? slot3State,
    String? slot4State,
    String? slot5State,
    String? slot6State,
    String? slot7State,
    String? slot8State,
    String? slot9State,
    String? slot10State,
    String? slot11State,
    String? slot12State,
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
        slot1State: slot1State,
        slot2State: slot2State,
        slot3State: slot3State,
        slot4State: slot4State,
        slot5State: slot5State,
        slot6State: slot6State,
        slot7State: slot7State,
        slot8State: slot8State,
        slot9State: slot9State,
        slot10State: slot10State,
        slot11State: slot11State,
        slot12State: slot12State,
      );
}
