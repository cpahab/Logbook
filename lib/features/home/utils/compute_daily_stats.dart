import 'package:latlong2/latlong.dart';
import '../domain/track_point.dart';

class DailyStats {
  final double distanceNm;     // Nautical miles
  final Duration duration;     // Total duration
  final double avgSpeed;       // Knots
  final double maxSpeed;       // km/h

  DailyStats({
    required this.distanceNm,
    required this.duration,
    required this.avgSpeed,
    required this.maxSpeed,
  });
}

DailyStats computeDailyStats(List<TrackPoint> points) {
  if (points.length < 2) {
    return DailyStats(
      distanceNm: 0,
      duration: Duration.zero,
      avgSpeed: 0,
      maxSpeed: 0,
    );
  }

  final distance = Distance();
  double totalMeters = 0;
  double maxSpeed = 0;

  for (int i = 1; i < points.length; i++) {
    final p1 = points[i - 1];
    final p2 = points[i];

    final d = distance(
      LatLng(p1.lat, p1.lon),
      LatLng(p2.lat, p2.lon),
    );

    totalMeters += d;

    final dt = p2.time.difference(p1.time).inSeconds;
    if (dt > 0) {
      final speedMps = d / dt;                 // m/s
      final speedKn = speedMps * 1.943844;     // kn

      // Filter: ignore speeds below 0.2 kn
      if (speedKn >= 0.2) {
        totalMeters += d;
      }

      // Max speed in kn
      if (speedKn > maxSpeed) maxSpeed = speedKn;
    }


  }

  final totalDuration =
      points.last.time.difference(points.first.time).abs();

  final distanceNm = totalMeters / 1852.0; // meters → nautical miles

  final avgSpeed = totalDuration.inSeconds > 0
      ? (distanceNm / (totalDuration.inSeconds / 3600.0))
      : 0;

  return DailyStats(
    distanceNm: distanceNm.toDouble(),
    duration: totalDuration,
    avgSpeed: avgSpeed.toDouble(),
    maxSpeed: maxSpeed.toDouble(),
  );
}

