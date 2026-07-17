// Regression coverage for DisplayModel.uncertainAreas, backed by real GPX
// fixtures — several already validated by departure_arrival_time_test.dart
// for their departure/arrival precision. No external reference for the
// clouds themselves exists (see the "Track Fade Zone" design docs, written
// for a different tool), so these assertions are sanity bounds on the real
// data rather than exact-value checks.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logbook/features/home/utils/filter_settings.dart';
import 'package:logbook/features/home/utils/gpx_parser.dart';
import 'package:logbook/features/home/utils/trim_track.dart';

DisplayModel _displayFor(String fixtureName, {FilterSettings settings = const FilterSettings()}) {
  final points = GpxParser()
      .parseBytes(File('test/fixtures/gpx/Logbook-Idefix-$fixtureName.gpx')
          .readAsBytesSync())
      .points;
  return buildDisplayModel(points, settings: settings);
}

void main() {
  group('uncertainAreas', () {
    test('26 Sep 2024 — unreliable arrival with a wide trailing scatter gets a cloud', () {
      final display = _displayFor('26 Sep 2024');
      expect(display.endPositionReliable, isFalse,
          reason: 'already confirmed by departure_arrival_time_test.dart');

      expect(display.uncertainAreas, isNotEmpty);
      final cloud = display.uncertainAreas.first;
      expect(cloud.nFixes, greaterThanOrEqualTo(5));
      expect(cloud.cep50M, greaterThan(0));
      expect(cloud.r95M, greaterThanOrEqualTo(cloud.cep50M));
      expect(cloud.lat, isNot(0));
      expect(cloud.lon, isNot(0));
    });

    test('26 Jul 2024 — unreliable arrival gets a cloud', () {
      final areas = _displayFor('26 Jul 2024').uncertainAreas;
      expect(areas, isNotEmpty);
      expect(areas.first.nFixes, greaterThanOrEqualTo(5));
      expect(areas.first.r95M, greaterThanOrEqualTo(areas.first.cep50M));
    });

    test('27 Jul 2024 — unreliable arrival gets a cloud', () {
      final areas = _displayFor('27 Jul 2024').uncertainAreas;
      expect(areas, isNotEmpty);
      expect(areas.first.nFixes, greaterThanOrEqualTo(5));
      expect(areas.first.r95M, greaterThanOrEqualTo(areas.first.cep50M));
    });

    test('04 Jul 2026 — a confirmed, reliable end stop gets no uncertain area', () {
      final display = _displayFor('04 Jul 2026');
      expect(display.endPositionReliable, isTrue,
          reason: 'a validated end stop exists for this trip');
      expect(display.uncertainAreas, isEmpty,
          reason: 'a real berth halo already covers this — no cloud needed');
    });
  });

  group('maneuvering detection (experimental, opt-in)', () {
    test('off by default — 05 Jul 2026 gets no uncertain area from a fast '
        'berthing maneuver that never drops below the stationary speed '
        'threshold (no rejected-width stop candidate exists there either)', () {
      final display = _displayFor('05 Jul 2026');
      expect(display.uncertainAreas, isEmpty);
    });

    test('opted in — 05 Jul 2026\'s berthing maneuver is detected', () {
      final display = _displayFor('05 Jul 2026',
          settings: const FilterSettings(detectManeuvering: true));
      expect(display.uncertainAreas, isNotEmpty);
      for (final cloud in display.uncertainAreas) {
        expect(cloud.nFixes, greaterThanOrEqualTo(5));
        expect(cloud.r95M, greaterThanOrEqualTo(cloud.cep50M));
      }
    });
  });
}
