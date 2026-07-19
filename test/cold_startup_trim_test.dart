// Regression coverage for _trimColdStartupPrefix (trim_track.dart): a day's
// track starting anywhere other than right around local midnight means the
// device/app was freshly started partway through the day, so its first few
// fixes (often imprecise, cold GPS) are trimmed before the rest of the
// pipeline sees them. A track starting at local midnight is a continuation
// of an overnight passage — never trimmed.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logbook/features/home/utils/gpx_parser.dart';
import 'package:logbook/features/home/utils/trim_track.dart';

List<TrackPointRaw> _rawPoints(String fixtureName) {
  final points = GpxParser()
      .parseBytes(File('test/fixtures/gpx/Logbook-Idefix-$fixtureName.gpx')
          .readAsBytesSync())
      .points;
  return points.map((p) => TrackPointRaw(p.lat, p.lon, p.time)).toList();
}

class TrackPointRaw {
  final double lat;
  final double lon;
  final DateTime time;
  TrackPointRaw(this.lat, this.lon, this.time);
}

void main() {
  group('cold-startup prefix trim', () {
    test('18 Jul 2026 — same-day start: first 3 fixes (near-dock dwell + '
        'the jump that follows it) are trimmed from the render', () {
      final raw = _rawPoints('18 Jul 2026');
      final points = GpxParser()
          .parseBytes(File('test/fixtures/gpx/Logbook-Idefix-18 Jul 2026.gpx')
              .readAsBytesSync())
          .points;
      final display = buildDisplayModel(points);

      final firstRendered = display.allPoints().first;
      // raw[3] is the fix right after the jump — raw[0..2] (the berth dwell
      // and the jump itself) must not appear anywhere in the render.
      expect(firstRendered.lat, closeTo(raw[3].lat, 1e-9));
      expect(firstRendered.lon, closeTo(raw[3].lon, 1e-9));
      expect(firstRendered.time, raw[3].time);
    });

    // For these three, allPoints().first is the start stop's own anchor/
    // connector synthetic point (existing DisplayModel behavior, unrelated
    // to this trim), not literally raw fix 0 — so the meaningful signal that
    // nothing was trimmed is the exact departure time, which departs from a
    // multi-hour overnight stop and would be unaffected even if a handful of
    // fixes deep inside that stop's cluster were removed. Values match
    // departure_arrival_time_test.dart's already-validated results exactly.
    test('26 Sep 2024 — overnight continuation (starts at local midnight): '
        'not trimmed at all', () {
      final points = GpxParser()
          .parseBytes(File('test/fixtures/gpx/Logbook-Idefix-26 Sep 2024.gpx')
              .readAsBytesSync())
          .points;
      final display = buildDisplayModel(points);
      expect(display.departureTime!.toUtc(),
          DateTime.utc(2024, 9, 26, 6, 32, 10, 123));
    });

    test('26 Jul 2024 — overnight continuation: not trimmed', () {
      final points = GpxParser()
          .parseBytes(File('test/fixtures/gpx/Logbook-Idefix-26 Jul 2024.gpx')
              .readAsBytesSync())
          .points;
      final display = buildDisplayModel(points);
      expect(display.departureTime!.toUtc(),
          DateTime.utc(2024, 7, 26, 6, 53, 22, 200));
    });

    test('27 Jul 2024 — overnight continuation: not trimmed', () {
      final points = GpxParser()
          .parseBytes(File('test/fixtures/gpx/Logbook-Idefix-27 Jul 2024.gpx')
              .readAsBytesSync())
          .points;
      final display = buildDisplayModel(points);
      expect(display.departureTime!.toUtc(),
          DateTime.utc(2024, 7, 27, 8, 7, 25, 233));
    });

    test('03 May 2026 — same-day start: first 3 fixes trimmed, but '
        'departure/arrival times are unaffected (covered exactly by '
        'departure_arrival_time_test.dart)', () {
      final raw = _rawPoints('03 May 2026');
      final points = GpxParser()
          .parseBytes(File('test/fixtures/gpx/Logbook-Idefix-03 May 2026.gpx')
              .readAsBytesSync())
          .points;
      final display = buildDisplayModel(points);

      final firstRendered = display.allPoints().first;
      expect(firstRendered.time, raw[3].time);
    });
  });
}
