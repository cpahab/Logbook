class TimelineEntry {
  final DateTime time;

  final String? remarks;
  final double? course;   // degrees
  final double? speed;    // knots
  final String? wind;     // e.g. "NW 12kt" or "Bft 4"
  final String? sea;      // e.g. "Calm", "1m waves"
  final String? weather;  // e.g. "Sunny", "Rainy"

  TimelineEntry({
    required this.time,
    this.remarks,
    this.course,
    this.speed,
    this.wind,
    this.sea,
    this.weather,
  });
}
