// Regression coverage for the median-speed/median-step acceptance path in
// _findStationarySegments (trim_track.dart): a stop candidate that lasted
// long enough but whose GPS spread exceeds FilterSettings.maxStopSpreadM
// (slow drift/orbit under wide scatter, not genuine movement) is still
// accepted as a real stop when its median windowed speed and median step
// distance between consecutive fixes are both near zero. Confirms both the
// positive cases (26 Sep/26 Jul/27 Jul 2024, previously missed) and that an
// already-tight stop's behaviour is unaffected (departure_arrival_time_test
// covers the exact time values for those files already).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logbook/features/home/utils/gpx_parser.dart';
import 'package:logbook/features/home/utils/trim_track.dart';

DisplayModel _displayFor(String fixtureName) {
  final points = GpxParser()
      .parseBytes(File('test/fixtures/gpx/Logbook-Idefix-$fixtureName.gpx')
          .readAsBytesSync())
      .points;
  return buildDisplayModel(points);
}

void main() {
  group('wide-scatter stop acceptance', () {
    test('26 Sep 2024 — end stop with 108.9 m max spread is accepted', () {
      final display = _displayFor('26 Sep 2024');
      expect(display.endPositionReliable, isTrue);
      final end = display.endStop;
      expect(end, isNotNull);
      // r95 (95th-percentile radius) exceeds the 30 m default spread gate —
      // the point of this fix is that a single wide outlier no longer
      // rejects an otherwise clearly genuine, many-fix, many-hour stop.
      expect(end!.r95M, greaterThan(30));
      expect(end.minutes, greaterThan(60),
          reason: 'a multi-hour stop, not a brief transient slowdown');
    });

    test('26 Jul 2024 — both start and end stops accepted despite wide spread', () {
      final display = _displayFor('26 Jul 2024');
      expect(display.startStop, isNotNull);
      expect(display.endStop, isNotNull);
      expect(display.endPositionReliable, isTrue);
    });

    test('27 Jul 2024 — both start and end stops accepted despite wide spread', () {
      final display = _displayFor('27 Jul 2024');
      expect(display.startStop, isNotNull);
      expect(display.endStop, isNotNull);
      expect(display.endPositionReliable, isTrue);
    });

    test('03 May 2026 — a genuine ~5 h stop (33.6 m max spread, just over '
        'the gate) is now caught, plus a shorter one', () {
      final display = _displayFor('03 May 2026');
      // The ~5 h stop now starts the track (a brief GPS cold-start drift
      // prefix before it is trimmed by _trimColdStartDriftPrefix — see
      // departure_arrival_time_test.dart), so it's classified "start", not
      // "mid" — this is the SAME wide-scatter acceptance this test was
      // written for, just now correctly attributed to the right stop kind.
      expect(display.startStop, isNotNull);
      expect(display.startStop!.minutes, greaterThan(200),
          reason: 'the long (~5h) genuine stop should be the start stop');
      final mids = display.stops.where((s) => s.kind == AnchorKind.mid).toList();
      expect(mids.length, 1);
      // Still no confirmed *end* stop for this file — the fix only expands
      // what counts as a stop candidate, it doesn't fabricate one where the
      // boat genuinely never settled at the very end of the log.
      expect(display.endPositionReliable, isFalse);
    });
  });
}
