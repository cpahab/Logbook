// Regression coverage for _trimPreBoardingPrefix (trim_track.dart): a day's
// track that starts moving immediately and only settles into its first stop
// a few minutes in is very likely recording the user's approach to the boat
// (walking from a car park/station, or driving there), not the vessel's own
// motion. That lead-in is trimmed whenever the first stop begins within
// _preBoardingWindowMinutes of the track's first raw fix — turning what
// would otherwise render as a long, nonsensical straight line cutting across
// land into a properly classified "start" stop. A stop hours into a track
// (a mid-voyage anchorage) is real sailing data and is never trimmed just
// for being the first stop found — see the 03 May 2026 case below.
//
// An overnight continuation (starts at local midnight, already sitting at
// anchor) needs no trimming at all: its first stop already begins at index
// 0, so _trimPreBoardingPrefix is a no-op for it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logbook/features/home/utils/gpx_parser.dart';
import 'package:logbook/features/home/utils/trim_track.dart';

void main() {
  group('pre-boarding prefix trim', () {
    test('18 Jul 2026 — same-day start: ~2 min walk-to-boat prefix trimmed, '
        'the ~31 min dock stop that follows is now a validated start stop', () {
      final points = GpxParser()
          .parseBytes(File('test/fixtures/gpx/Logbook-Idefix-18 Jul 2026.gpx')
              .readAsBytesSync())
          .points;
      final display = buildDisplayModel(points);

      expect(display.startStop, isNotNull);
      expect(display.startStop!.minutes, closeTo(30.9, 0.1));
      expect(display.departurePrecision, TimePrecision.precise);
      expect(display.endPositionReliable, isTrue,
          reason: 'a validated end stop is also found once the prefix no '
              "longer masks the day's real shape");
    });

    test('03 May 2026 — same-day start: ~2-3 min walk-to-boat prefix '
        'trimmed, the ~4.9 h stop that follows is now the start stop '
        '(was misclassified "mid" before this fix)', () {
      final points = GpxParser()
          .parseBytes(File('test/fixtures/gpx/Logbook-Idefix-03 May 2026.gpx')
              .readAsBytesSync())
          .points;
      final display = buildDisplayModel(points);

      expect(display.startStop, isNotNull);
      expect(display.startStop!.minutes, greaterThan(200));
      expect(display.departurePrecision, TimePrecision.precise);
      // Exact departure moment is unchanged from before this fix — see
      // departure_arrival_time_test.dart — only the classification improved.
      expect(display.departureTime!.toUtc(),
          DateTime.utc(2026, 5, 3, 10, 15, 21, 170));
    });

    // For these three, the meaningful signal that nothing was trimmed is the
    // exact departure time, unchanged from departure_arrival_time_test.dart's
    // already-validated results — their first stop already begins at index
    // 0 (starts at local midnight), so _trimPreBoardingPrefix never engages.
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
  });
}
