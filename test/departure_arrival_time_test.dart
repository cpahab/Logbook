// Regression test for DisplayModel.departureTime/arrivalTime and their
// TimePrecision, backed by real GPX tracks whose correct times were
// established against the original reference implementation (see the
// "departure & arrival time" spec). Values below are cross-checked against
// that spec's own validated-results table for these files.
//
// 26 Sep/26 Jul/27 Jul 2024 were originally "estimated" for one or both ends
// because their stop's GPS scatter (slow drift/orbit at a wide-open
// mooring) exceeded FilterSettings.maxStopSpreadM. _findStationarySegments
// now also accepts a candidate on median windowed speed + median step
// distance (see its doc comment) when spread alone would reject it — these
// files' stops pass that check, so they're now correctly "precise" instead
// of falling back to an estimated, less trustworthy time. The exact time
// *values* are unchanged (the windowed-speed scan already found the right
// moment; only the confidence label and the position's reliability change).

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
    test('26 Sep 2024 — precise departure and arrival (wide-scatter end stop '
        'validated via median speed/step)', () {
      final points = GpxParser()
          .parseBytes(File('test/fixtures/gpx/Logbook-Idefix-26 Sep 2024.gpx')
              .readAsBytesSync())
          .points;
      final display = buildDisplayModel(points);

      expect(display.departurePrecision, TimePrecision.precise,
          reason: 'a start stop was detected, so departure is bounded by it');
      expect(_toSecond(display.departureTime!.toUtc()),
          DateTime.utc(2024, 9, 26, 6, 32, 10));

      expect(display.arrivalPrecision, TimePrecision.precise,
          reason: 'end-of-day GPS scatter exceeds maxStopSpreadM, but median '
              'windowed speed/step distance confirm the boat genuinely '
              'stopped there');
      expect(display.endPositionReliable, isTrue);
      expect(_toSecond(display.arrivalTime!.toUtc()),
          DateTime.utc(2024, 9, 26, 13, 24, 8));

      // The bug an earlier fix addressed: the raw last fix / old
      // lastMovingPoint fallback was hours later than the real arrival.
      final rawLast = _toSecond(points.last.time.toUtc());
      expect(rawLast, DateTime.utc(2024, 9, 26, 21, 58, 57));
      expect(rawLast.difference(display.arrivalTime!).inMinutes,
          greaterThan(8 * 60));
    });

    test('03 May 2026 — precise departure (GPS cold-start drift prefix '
        'trimmed), estimated arrival', () {
      final points = GpxParser()
          .parseBytes(File('test/fixtures/gpx/Logbook-Idefix-03 May 2026.gpx')
              .readAsBytesSync())
          .points;
      final display = buildDisplayModel(points);

      // The raw track's first ~2-3 min (07:12-07:15) is GPS cold-start
      // convergence drift from the boat-mounted receiver, not real vessel
      // motion — _trimColdStartDriftPrefix removes it, so the ~4.9 h stop that
      // follows now correctly starts the track and is classified as a
      // genuine "start" stop rather than "mid". Same departure moment as
      // before, just correctly validated instead of a speed-signal estimate.
      expect(display.departurePrecision, TimePrecision.precise,
          reason: 'a start stop is now detected after trimming the '
              'cold-start drift prefix');
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

    test('26 Jul 2024 — precise departure and arrival (both wide-scatter '
        'stops validated via median speed/step)', () {
      final points = GpxParser()
          .parseBytes(File('test/fixtures/gpx/Logbook-Idefix-26 Jul 2024.gpx')
              .readAsBytesSync())
          .points;
      final display = buildDisplayModel(points);

      expect(display.departurePrecision, TimePrecision.precise);
      expect(_toSecond(display.departureTime!.toUtc()),
          DateTime.utc(2024, 7, 26, 6, 53, 22));

      expect(display.arrivalPrecision, TimePrecision.precise);
      expect(display.endPositionReliable, isTrue);
      expect(_toSecond(display.arrivalTime!.toUtc()),
          DateTime.utc(2024, 7, 26, 14, 21, 27));
    });

    test('27 Jul 2024 — precise departure and arrival (both wide-scatter '
        'stops validated via median speed/step)', () {
      final points = GpxParser()
          .parseBytes(File('test/fixtures/gpx/Logbook-Idefix-27 Jul 2024.gpx')
              .readAsBytesSync())
          .points;
      final display = buildDisplayModel(points);

      expect(display.departurePrecision, TimePrecision.precise);
      expect(_toSecond(display.departureTime!.toUtc()),
          DateTime.utc(2024, 7, 27, 8, 7, 25));

      expect(display.arrivalPrecision, TimePrecision.precise);
      expect(display.endPositionReliable, isTrue);
      expect(_toSecond(display.arrivalTime!.toUtc()),
          DateTime.utc(2024, 7, 27, 14, 23, 24));
    });
  });
}
