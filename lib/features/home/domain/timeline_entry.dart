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
  String? remarks; // optional, last field in UI

  TimelineEntry({
    required this.time,
    this.course,
    this.speed,
    this.wind,
    this.sea,
    this.weather,
    this.remarks,
  });
}
