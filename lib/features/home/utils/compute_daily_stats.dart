import 'package:latlong2/latlong.dart';
import '../domain/track_point.dart';

class DailyStats {
  final double distanceNm;     // Nautical miles
  final Duration duration;     // Total duration
  final Duration movingDuration;
  final double avgSpeed;       // Knots
  final double maxSpeed;       // Knots
  final double? elevationGainMeters;
  final int stopCount;

  DailyStats({
    required this.distanceNm,
    required this.duration,
    required this.movingDuration,
    required this.avgSpeed,
    required this.maxSpeed,
    this.elevationGainMeters,
    required this.stopCount,
  });
}

DailyStats computeDailyStats(List<TrackPoint> points) {
  if (points.length < 2) {
    return DailyStats(
      distanceNm: 0,
      duration: Duration.zero,
      movingDuration: Duration.zero,
      avgSpeed: 0,
      maxSpeed: 0,
      stopCount: 0,
    );
  }

  final distance = Distance();
  double totalMeters = 0;
  double maxSpeed = 0;
  int movingSeconds = 0;
  int stopCount = 0;
  bool wasMoving = false;

  for (int i = 1; i < points.length; i++) {
    final p1 = points[i - 1];
    final p2 = points[i];

    final d = distance(
      LatLng(p1.lat, p1.lon),
      LatLng(p2.lat, p2.lon),
    );

    final dt = p2.time.difference(p1.time).inSeconds;
    final movingSegment = dt > 0 && d > 0 && (d / dt * 1.943844) >= 0.2;

    if (movingSegment) {
      totalMeters += d;
      movingSeconds += dt;
    }

    if (dt > 0) {
      final speedMps = d / dt;                 // m/s
      final speedKn = speedMps * 1.943844;     // kn
      if (speedKn > maxSpeed) maxSpeed = speedKn;

      if (!movingSegment && wasMoving) {
        stopCount += 1;
      }
    }

    wasMoving = movingSegment;
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
    movingDuration: Duration(seconds: movingSeconds),
    avgSpeed: avgSpeed.toDouble(),
    maxSpeed: maxSpeed.toDouble(),
    elevationGainMeters: null,
    stopCount: stopCount,
  );
}

