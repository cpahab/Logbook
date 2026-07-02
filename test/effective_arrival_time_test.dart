// Regression test for DisplayModel.effectiveArrivalTime, backed by two real
// GPX tracks whose correct arrival times were established by hand against
// the original reference implementation (see the "effective arrival time"
// spec). Both tracks have an end-of-day GPS scatter too wide to pass stop
// validation, so DisplayModel.endStop is null and the old lastMovingPoint
// fallback read hours late — the exact bug this logic fixes.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logbook/features/home/utils/gpx_parser.dart';
import 'package:logbook/features/home/utils/trim_track.dart';

/// Truncates to whole seconds so comparisons don't depend on the GPX file's
/// sub-second timestamp precision.
DateTime _toSecond(DateTime t) =>
    DateTime.utc(t.year, t.month, t.day, t.hour, t.minute, t.second);

void main() {
  group('effectiveArrivalTime (real-track regression)', () {
    test('26 Sep 2024 — corrects an ~8.5h late raw-last-fix reading', () {
      final points = GpxParser()
          .parseBytes(File('test/fixtures/gpx/Logbook-Idefix-26 Sep 2024.gpx')
              .readAsBytesSync())
          .points;
      final display = buildDisplayModel(points);

      expect(display.endPositionReliable, isFalse,
          reason: 'end-of-day GPS scatter is too wide to validate as a stop');

      final rawLast = _toSecond(points.last.time.toUtc());
      final effective = _toSecond(display.effectiveArrivalTime!.toUtc());

      expect(rawLast, DateTime.utc(2024, 9, 26, 21, 58, 57));
      expect(effective, DateTime.utc(2024, 9, 26, 13, 24, 8));
      expect(rawLast.difference(effective).inMinutes, greaterThan(8 * 60));
    });

    test('03 May 2026 — track ends while still under way (no correction)', () {
      final points = GpxParser()
          .parseBytes(File('test/fixtures/gpx/Logbook-Idefix-03 May 2026.gpx')
              .readAsBytesSync())
          .points;
      final display = buildDisplayModel(points);

      expect(display.endPositionReliable, isFalse);

      final rawLast = _toSecond(points.last.time.toUtc());
      final effective = _toSecond(display.effectiveArrivalTime!.toUtc());

      // No fix past the search window exceeds the underway threshold after
      // the scan starts, so this correctly falls back to the last raw fix
      // rather than fabricating an earlier arrival.
      expect(effective, rawLast);
      expect(effective, DateTime.utc(2026, 5, 3, 14, 4, 5));
    });
  });
}
