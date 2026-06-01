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

  // Sailing state — null means not recorded
  @HiveField(7)
  bool? fockUp;     // true = auf, false = unten

  @HiveField(8)
  bool? grossUp;    // true = auf, false = unten

  @HiveField(9)
  bool? reff1Fock;

  @HiveField(10)
  bool? reff1Gross;

  @HiveField(11)
  bool? reff2Fock;

  @HiveField(12)
  bool? reff2Gross;

  @HiveField(13)
  bool? motorOn;    // true = an, false = aus

  // Replaces the old bool fockUp/grossUp + reff fields.
  // Values: 'Voll Gesetzt' | '1. Reff' | '2. Reff' | 'Niedergeholt'/'Eingerollt' | null
  @HiveField(14)
  String? grossState;

  @HiveField(15)
  String? fockState;

  TimelineEntry({
    required this.time,
    this.course,
    this.speed,
    this.wind,
    this.sea,
    this.weather,
    this.remarks,
    this.fockUp,
    this.grossUp,
    this.reff1Fock,
    this.reff1Gross,
    this.reff2Fock,
    this.reff2Gross,
    this.motorOn,
    this.grossState,
    this.fockState,
  });
}
