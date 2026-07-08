import 'package:hive/hive.dart';

part 'crew_member.g.dart';

/// A crew member, either aboard for a specific day (copied into that
/// [DayEntry]'s `crew` list) or in the persistent roster
/// (features/home/screens/crew_roster_screen.dart). Includes medical fields
/// shown on the Emergency Manifest screen (blood type, allergies, conditions,
/// personal EPIRB). [id] links a per-day copy back to its roster record so
/// roster edits can be reflected without mutating history.
@HiveType(typeId: 12)
class CrewMember extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  String? bloodType;

  @HiveField(2)
  String? allergies;

  @HiveField(3)
  String? conditions;

  @HiveField(4)
  String? remarks;

  @HiveField(5)
  String? id;

  @HiveField(6)
  String? personalEpirb;

  CrewMember({
    required this.name,
    this.bloodType,
    this.allergies,
    this.conditions,
    this.remarks,
    this.id,
    this.personalEpirb,
  });
}
