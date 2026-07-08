import 'package:gpx/gpx.dart';
import 'package:intl/intl.dart';

import '../domain/track_point.dart';
import 'trim_track.dart';

/// Builds a GPX XML string from a filtered [DisplayModel] and the raw point
/// list for the same day.
///
/// The output contains two `trk` elements:
///   1. "Gefilterte Spur"  — cleaned, segmented track (respects teleport gaps)
///   2. "Rohe GPS-Spur"    — unprocessed points straight from the GPX file
///
/// Either track is omitted if it has no usable points.
String buildGpxExport({
  required List<TrackPoint> rawPoints,
  required DisplayModel display,
  required DateTime date,
  String vesselName = '',
}) {
  final gpx = Gpx();
  gpx.creator = 'Logbuch';
  gpx.metadata = Metadata(
    name: 'Logbuch ${DateFormat('yyyy-MM-dd').format(date)}',
    time: date,
    desc: vesselName.isNotEmpty ? vesselName : null,
  );

  // Filtered track — split into separate Trkseg objects at teleport breaks so
  // receivers see a gap rather than a straight jump across the ocean.
  final filteredSegs = <Trkseg>[];
  var current = <Wpt>[];
  for (final seg in display.segments) {
    if (seg.kind == SegmentKind.teleportBreak) {
      if (current.length >= 2) filteredSegs.add(Trkseg(trkpts: current));
      current = [];
    } else {
      current.addAll(seg.points.map(_toWpt));
    }
  }
  if (current.length >= 2) filteredSegs.add(Trkseg(trkpts: current));

  if (filteredSegs.isNotEmpty) {
    gpx.trks.add(Trk(name: 'Gefilterte Spur', trksegs: filteredSegs));
  }

  // Raw track — single segment, all original fixes.
  if (rawPoints.isNotEmpty) {
    gpx.trks.add(Trk(
      name: 'Rohe GPS-Spur',
      trksegs: [Trkseg(trkpts: rawPoints.map(_toWpt).toList())],
    ));
  }

  return GpxWriter().asString(gpx, pretty: true);
}

/// Converts a [TrackPoint] to the `gpx` package's waypoint type.
Wpt _toWpt(TrackPoint p) => Wpt(lat: p.lat, lon: p.lon, time: p.time);
