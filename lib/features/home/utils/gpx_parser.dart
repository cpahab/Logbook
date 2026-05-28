import 'dart:io';
import 'package:gpx/gpx.dart';
import '../domain/track_point.dart';

class GpxParser {
  Future<List<TrackPoint>> parse(File file) async {
    final xml = await file.readAsString();
    final gpx = GpxReader().fromString(xml);

    final List<TrackPoint> points = [];

    // --- TRACKPOINTS ONLY (trk → trkseg → trkpt) ---
    for (final trk in gpx.trks) {
      for (final seg in trk.trksegs) {
        for (final pt in seg.trkpts) {
          if (pt.lat == null || pt.lon == null) continue;
          if (pt.time == null) continue; // MUST have timestamp
          if (pt.lat == 0.0 && pt.lon == 0.0) continue; // GPS lost

          points.add(
            TrackPoint(
              lat: pt.lat!.toDouble(),
              lon: pt.lon!.toDouble(),
              time: pt.time!.toLocal(),
            ),
          );
        }
      }
    }

    // --- Ignore rte and wpt completely ---
    // They are NOT part of the sailed track.

    // --- Remove duplicates ---
    points.sort((a, b) => a.time.compareTo(b.time));
    final unique = <TrackPoint>[];
    TrackPoint? last;

    for (final p in points) {
      if (last == null ||
          last.lat != p.lat ||
          last.lon != p.lon ||
          last.time != p.time) {
        unique.add(p);
      }
      last = p;
    }

    return unique;
  }
}
