import 'dart:math';

import 'package:latlong2/latlong.dart';

/// Initial compass bearing (radians) from [from] to [to], for rotating the
/// departure/arrival direction-arrow markers.
double trackBearing(LatLng from, LatLng to) {
  final lat1 = from.latitude  * pi / 180;
  final lat2 = to.latitude    * pi / 180;
  final dLon = (to.longitude - from.longitude) * pi / 180;
  final y = sin(dLon) * cos(lat2);
  final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
  return atan2(y, x);
}

/// Great-circle distance in metres between two map coordinates.
double distM(LatLng a, LatLng b) {
  const r   = 6371000.0;
  final lat1 = a.latitude  * pi / 180;
  final lat2 = b.latitude  * pi / 180;
  final dLat = (b.latitude  - a.latitude)  * pi / 180;
  final dLon = (b.longitude - a.longitude) * pi / 180;
  final s = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
  return r * 2 * atan2(sqrt(s), sqrt(1 - s));
}

/// Direction the boat headed away from [origin]: bearing toward the point
/// ~500m along the track (or the single farthest point, if the whole track
/// is shorter than that), so a short initial wobble doesn't skew the arrow.
double dayDetailDepartureBearing(List<LatLng> pts, LatLng origin) {
  if (pts.length < 2) return 0;
  const targetM = 500.0;
  double cum = 0;
  for (int i = 1; i < pts.length; i++) {
    cum += distM(pts[i - 1], pts[i]);
    if (cum >= targetM) return trackBearing(origin, pts[i]);
  }
  double maxD = 0; int farIdx = 1;
  for (int i = 1; i < pts.length; i++) {
    final d = distM(origin, pts[i]);
    if (d > maxD) { maxD = d; farIdx = i; }
  }
  return trackBearing(origin, pts[farIdx]);
}

/// Direction the boat was heading into [destination]: bearing from the point
/// ~500m before it along the track (mirrors [dayDetailDepartureBearing]).
double dayDetailArrivalBearing(List<LatLng> pts, LatLng destination) {
  if (pts.length < 2) return 0;
  const targetM = 500.0;
  double cum = 0;
  for (int i = pts.length - 2; i >= 0; i--) {
    cum += distM(pts[i], pts[i + 1]);
    if (cum >= targetM) return trackBearing(pts[i], destination);
  }
  double maxD = 0; int farIdx = 0;
  for (int i = 0; i < pts.length - 1; i++) {
    final d = distM(pts[i], destination);
    if (d > maxD) { maxD = d; farIdx = i; }
  }
  return trackBearing(pts[farIdx], destination);
}
