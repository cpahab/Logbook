import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:gpx/gpx.dart';
import '../domain/track_point.dart';

class GpxParser {
  // Native platforms: read from File
  Future<List<TrackPoint>> parse(File file) async {
    return _parseXml(await file.readAsString());
  }

  // Web: receive bytes from FilePicker
  List<TrackPoint> parseBytes(Uint8List bytes) {
    return _parseXml(utf8.decode(bytes));
  }

  List<TrackPoint> _parseXml(String xml) {
    final gpx = GpxReader().fromString(xml);
    final points = <TrackPoint>[];

    for (final trk in gpx.trks) {
      for (final seg in trk.trksegs) {
        for (final pt in seg.trkpts) {
          if (pt.lat == null || pt.lon == null) continue;
          if (pt.time == null) continue;
          if (pt.lat == 0.0 && pt.lon == 0.0) continue;

          points.add(TrackPoint(
            lat: pt.lat!.toDouble(),
            lon: pt.lon!.toDouble(),
            time: pt.time!.toLocal(),
          ));
        }
      }
    }

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
