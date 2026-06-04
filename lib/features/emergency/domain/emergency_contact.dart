import 'package:hive/hive.dart';

part 'emergency_contact.g.dart';

@HiveType(typeId: 13)
class EmergencyContact extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  String role; // e.g. "Ehefrau", "Arzt"

  @HiveField(2)
  String phone;

  EmergencyContact({
    required this.name,
    required this.role,
    required this.phone,
  });
}
