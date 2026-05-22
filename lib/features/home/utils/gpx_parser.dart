import 'dart:io';
import 'package:gpx/gpx.dart';
import '../domain/track_point.dart';

class GpxParser {
  static Future<List<TrackPoint>> parse(File file) async {
    final xml = await file.readAsString();
    final gpx = GpxReader().fromString(xml);

    final List<TrackPoint> points = [];

    // TRACKPOINTS (trk → trkseg → trkpt)
    for (final trk in gpx.trks) {
      for (final seg in trk.trksegs) {
        for (final pt in seg.trkpts) {
          if (pt.lat != null && pt.lon != null) {
            points.add(
              TrackPoint(
                lat: pt.lat!.toDouble(),
                lon: pt.lon!.toDouble(),
                time: pt.time ?? DateTime.now(),
              ),
            );
          }
        }
      }
    }

    // ROUTE POINTS (rte → rtept)
    for (final rte in gpx.rtes) {
      for (final pt in rte.rtepts) {
        if (pt.lat != null && pt.lon != null) {
          points.add(
            TrackPoint(
              lat: pt.lat!.toDouble(),
              lon: pt.lon!.toDouble(),
              time: pt.time ?? DateTime.now(),
            ),
          );
        }
      }
    }

    // WAYPOINTS (wpt)
    for (final pt in gpx.wpts) {
      if (pt.lat != null && pt.lon != null) {
        points.add(
          TrackPoint(
            lat: pt.lat!.toDouble(),
            lon: pt.lon!.toDouble(),
            time: pt.time ?? DateTime.now(),
          ),
        );
      }
    }

    points.sort((a, b) => a.time.compareTo(b.time));
    return points;
  }
}
