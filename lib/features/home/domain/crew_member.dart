import 'package:hive/hive.dart';

part 'crew_member.g.dart';

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

  CrewMember({
    required this.name,
    this.bloodType,
    this.allergies,
    this.conditions,
    this.remarks,
  });
}
