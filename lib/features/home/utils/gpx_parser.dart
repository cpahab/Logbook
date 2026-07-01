import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:gpx/gpx.dart';
import '../domain/track_point.dart';

enum GpxParseError { invalidEncoding, invalidXml, noSupportedContent }

class GpxParseResult {
  final List<TrackPoint> points;
  final GpxParseError? error;
  final int sourceTrackCount;
  final bool hasRoutesOnly;
  final bool hasWaypointsOnly;
  // True when track points have lat/lon but no parseable timestamps.
  final bool hasPointsWithoutTimestamps;

  const GpxParseResult({
    required this.points,
    this.error,
    this.sourceTrackCount = 0,
    this.hasRoutesOnly = false,
    this.hasWaypointsOnly = false,
    this.hasPointsWithoutTimestamps = false,
  });
}

class GpxParser {
  // Native platforms: read from File
  Future<GpxParseResult> parse(File file) async {
    try {
      final bytes = await file.readAsBytes();
      return parseBytes(bytes);
    } catch (_) {
      return const GpxParseResult(
          points: [], error: GpxParseError.invalidEncoding);
    }
  }

  // Web / share-intent: receive raw bytes
  GpxParseResult parseBytes(Uint8List bytes) {
    final String xml;
    try {
      xml = _decodeBytes(bytes);
    } catch (_) {
      return const GpxParseResult(
          points: [], error: GpxParseError.invalidEncoding);
    }
    return _parseXml(xml);
  }

  String _decodeBytes(Uint8List bytes) {
    if (bytes.length >= 2) {
      // UTF-16 LE BOM
      if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
        final content = bytes.sublist(2);
        final codeUnits = List<int>.generate(
          content.length ~/ 2,
          (i) => content[i * 2] | (content[i * 2 + 1] << 8),
        );
        return String.fromCharCodes(codeUnits);
      }
      // UTF-16 BE BOM
      if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
        final content = bytes.sublist(2);
        final codeUnits = List<int>.generate(
          content.length ~/ 2,
          (i) => (content[i * 2] << 8) | content[i * 2 + 1],
        );
        return String.fromCharCodes(codeUnits);
      }
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  GpxParseResult _parseXml(String xml) {
    // Fix HH:mm timestamps (no seconds) emitted by some Navionics exports.
    final fixed = xml.replaceAllMapped(
      RegExp(
          r'(<time>)(\d{4}-\d{2}-\d{2}T\d{2}:\d{2})(Z|[+-]\d{2}:\d{2})(</time>)'),
      (m) => '${m[1]}${m[2]}:00${m[3]}${m[4]}',
    );

    final Gpx gpx;
    try {
      gpx = GpxReader().fromString(fixed);
    } catch (_) {
      return const GpxParseResult(
          points: [], error: GpxParseError.invalidXml);
    }

    final hasTracks = gpx.trks.isNotEmpty;
    final hasRoutes = gpx.rtes.isNotEmpty;
    final hasWaypoints = gpx.wpts.isNotEmpty;

    if (!hasTracks) {
      if (hasRoutes) {
        return const GpxParseResult(
            points: [], sourceTrackCount: 0, hasRoutesOnly: true);
      }
      if (hasWaypoints) {
        return const GpxParseResult(
            points: [], sourceTrackCount: 0, hasWaypointsOnly: true);
      }
      return const GpxParseResult(
          points: [], error: GpxParseError.noSupportedContent);
    }

    final points = <TrackPoint>[];
    int coordsWithoutTime = 0;

    for (final trk in gpx.trks) {
      for (final seg in trk.trksegs) {
        for (final pt in seg.trkpts) {
          if (pt.lat == null || pt.lon == null) continue;
          if (pt.lat == 0.0 && pt.lon == 0.0) continue;
          if (pt.time == null) {
            coordsWithoutTime++;
            continue;
          }
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

    if (unique.isEmpty) {
      final noTimestamps = coordsWithoutTime > 0;
      return GpxParseResult(
        points: [],
        sourceTrackCount: gpx.trks.length,
        hasPointsWithoutTimestamps: noTimestamps,
        error: noTimestamps ? null : GpxParseError.noSupportedContent,
      );
    }

    return GpxParseResult(
      points: unique,
      sourceTrackCount: gpx.trks.length,
    );
  }
}
