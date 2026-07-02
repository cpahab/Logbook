// Regression test for DisplayModel.departureTime/arrivalTime and their
// TimePrecision, backed by real GPX tracks whose correct times were
// established against the original reference implementation (see the
// "departure & arrival time" spec). Values below are cross-checked against
// that spec's own validated-results table for these files.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logbook/features/home/utils/gpx_parser.dart';
import 'package:logbook/features/home/utils/trim_track.dart';

/// Truncates to whole seconds so comparisons don't depend on the GPX file's
/// sub-second timestamp precision.
DateTime _toSecond(DateTime t) =>
    DateTime.utc(t.year, t.month, t.day, t.hour, t.minute, t.second);

void main() {
  group('departure/arrival time (real-track regression)', () {
    test('26 Sep 2024 — precise departure, estimated arrival', () {
      final points = GpxParser()
          .parseBytes(File('test/fixtures/gpx/Logbook-Idefix-26 Sep 2024.gpx')
              .readAsBytesSync())
          .points;
      final display = buildDisplayModel(points);

      expect(display.departurePrecision, TimePrecision.precise,
          reason: 'a start stop was detected, so departure is bounded by it');
      expect(_toSecond(display.departureTime!.toUtc()),
          DateTime.utc(2024, 9, 26, 6, 32, 10));

      expect(display.arrivalPrecision, TimePrecision.estimated);
      expect(display.endPositionReliable, isFalse,
          reason: 'end-of-day GPS scatter is too wide to validate as a stop');
      expect(_toSecond(display.arrivalTime!.toUtc()),
          DateTime.utc(2024, 9, 26, 13, 24, 8));

      // The bug this fixes: the raw last fix / old lastMovingPoint fallback
      // was hours later than the real arrival.
      final rawLast = _toSecond(points.last.time.toUtc());
      expect(rawLast, DateTime.utc(2024, 9, 26, 21, 58, 57));
      expect(rawLast.difference(display.arrivalTime!).inMinutes,
          greaterThan(8 * 60));
    });

    test('03 May 2026 — estimated departure and arrival', () {
      final points = GpxParser()
          .parseBytes(File('test/fixtures/gpx/Logbook-Idefix-03 May 2026.gpx')
              .readAsBytesSync())
          .points;
      final display = buildDisplayModel(points);

      expect(display.departurePrecision, TimePrecision.estimated,
          reason: 'no start stop was detected');
      expect(_toSecond(display.departureTime!.toUtc()),
          DateTime.utc(2026, 5, 3, 10, 15, 21));

      expect(display.arrivalPrecision, TimePrecision.estimated);
      expect(display.endPositionReliable, isFalse);
      final rawLast = _toSecond(points.last.time.toUtc());
      final arrival = _toSecond(display.arrivalTime!.toUtc());
      // No fix past the search window exceeds the underway threshold after
      // the scan starts, so this correctly falls back to the last raw fix
      // rather than fabricating an earlier arrival.
      expect(arrival, rawLast);
      expect(arrival, DateTime.utc(2026, 5, 3, 14, 4, 5));
    });

    test('26 Jul 2024 — estimated departure and arrival', () {
      final points = GpxParser()
          .parseBytes(File('test/fixtures/gpx/Logbook-Idefix-26 Jul 2024.gpx')
              .readAsBytesSync())
          .points;
      final display = buildDisplayModel(points);

      expect(display.departurePrecision, TimePrecision.estimated);
      expect(_toSecond(display.departureTime!.toUtc()),
          DateTime.utc(2024, 7, 26, 6, 53, 22));

      expect(display.arrivalPrecision, TimePrecision.estimated);
      expect(_toSecond(display.arrivalTime!.toUtc()),
          DateTime.utc(2024, 7, 26, 14, 21, 27));
    });

    test('27 Jul 2024 — estimated departure and arrival', () {
      final points = GpxParser()
          .parseBytes(File('test/fixtures/gpx/Logbook-Idefix-27 Jul 2024.gpx')
              .readAsBytesSync())
          .points;
      final display = buildDisplayModel(points);

      expect(display.departurePrecision, TimePrecision.estimated);
      expect(_toSecond(display.departureTime!.toUtc()),
          DateTime.utc(2024, 7, 27, 8, 7, 25));

      expect(display.arrivalPrecision, TimePrecision.estimated);
      expect(_toSecond(display.arrivalTime!.toUtc()),
          DateTime.utc(2024, 7, 27, 14, 23, 24));
    });
  });
}
