import 'package:hive/hive.dart';

part 'emergency_contact.g.dart';

/// A single next-of-kin/emergency contact shown on the Emergency Manifest
/// screen — distinct from crew members and vessel safety equipment, which
/// live in their own models.
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
