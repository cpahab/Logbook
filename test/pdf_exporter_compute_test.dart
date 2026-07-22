import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:logbook/core/services/backup_mapper.dart';
import 'package:logbook/features/home/data/home_repository.dart';
import 'package:logbook/features/home/domain/crew_member.dart';
import 'package:logbook/features/home/domain/daily_track.dart';
import 'package:logbook/features/home/domain/day_entry.dart';
import 'package:logbook/features/home/domain/timeline_amendment.dart';
import 'package:logbook/features/home/domain/timeline_entry.dart';
import 'package:logbook/features/home/domain/track_point.dart';
import 'package:logbook/features/home/domain/vessel_equipment.dart';
import 'package:logbook/features/home/utils/pdf_exporter.dart';

import 'test_helpers/secure_storage_mock.dart';

// Regression coverage for two bugs where PDF export silently failed after
// moving PDF generation into compute():
//   1. A DayEntry loaded from HomeRepository is a live HiveObject bound to
//      its Hive box (which holds a StreamController with listener closures),
//      and closures can never cross an isolate boundary — so handing that
//      entry straight to compute() throws. pdf_exporter.dart now round-trips
//      through dayEntryToJson/dayEntryFromJson first to strip the box
//      attachment.
//   2. compute() runs in a fresh isolate that doesn't share the main
//      isolate's intl locale data (initialized once in main.dart), so any
//      DateFormat call with a non-default locale (e.g. 'de_CH') threw
//      LocaleDataException. pdf_exporter.dart now calls
//      initializeDateFormatting() inside the isolate entry point.
void main() {
  late Directory tempDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() async {
    mockSecureStorage();
    tempDir = await Directory.systemTemp.createTemp('pdf_exporter_compute_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(11)) Hive.registerAdapter(DayEntryAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(TimelineEntryAdapter());
    if (!Hive.isAdapterRegistered(14)) Hive.registerAdapter(TimelineAmendmentAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(DailyTrackAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(TrackPointAdapter());
    if (!Hive.isAdapterRegistered(12)) Hive.registerAdapter(CrewMemberAdapter());
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('a live, box-attached DayEntry cannot cross compute()\'s isolate boundary', () async {
    final home = HomeRepository();
    await home.init();
    final date = DateTime(2024, 1, 1);
    home.addEntry(date);
    final liveEntry = home.getEntry(date)!;
    expect(liveEntry.box, isNotNull,
        reason: 'entry must actually be box-attached for this test to be meaningful');

    await expectLater(
      compute((DayEntry e) => e.date, liveEntry),
      throwsA(anything),
    );
  });

  test('dayEntryFromJson(dayEntryToJson(...)) detaches the entry so it can cross compute()',
      () async {
    final home = HomeRepository();
    await home.init();
    final date = DateTime(2024, 1, 1);
    home.addEntry(date);
    final liveEntry = home.getEntry(date)!;

    final detached = dayEntryFromJson(dayEntryToJson(liveEntry)).entry;
    expect(detached.box, isNull);

    final result = await compute((DayEntry e) => e.date, detached);
    expect(result, date);
  });

  test('buildVoyagePdf with a non-default locale succeeds (regression: '
      'DateFormat inside compute() needs its own intl locale init)', () async {
    final home = HomeRepository();
    await home.init();
    final date = DateTime(2024, 1, 1);
    home.addEntry(date);
    final entry = home.getEntry(date)!;
    // fromHarbor/toHarbor is what makes _buildRoute call DateFormat(...,
    // strings.locale) — the exact call site that threw LocaleDataException.
    entry.fromHarbor = 'Palma';
    entry.toHarbor = 'Ibiza';
    home.saveEntry(entry, changedFields: {'fromHarbor', 'toHarbor'});
    final liveEntry = home.getEntry(date)!;

    const strings = PdfStrings(
      voyageLog: 'VOYAGE LOG', notes: 'NOTES', date: 'DATE',
      distance: 'DISTANCE', avgSpeedUnderway: 'AVG UNDERWAY',
      max: 'MAX', duration: 'DURATION', statistics: 'STATS',
      crew: 'CREW', skipper: 'SKIPPER', crewMember: 'CREW', logEntries: 'LOG',
      timeCol: 'Time', courseCol: 'Hdg', windCol: 'Wind', seaCol: 'Sea',
      positionCol: 'Position',
      remarksCol: 'Remarks', trackMap: 'MAP', locale: 'de_CH', generatedOn: 'GEN',
      crewNoteLabel: 'Crew', skipperLabel: 'Skipper',
      oilLabel: 'Engine oil', fuelLabel: 'Fuel',
      keelLabel: 'Keel', keelDownLabel: 'Down', keelUpLabel: 'Up',
      passageToTemplate: 'Fahrt nach \u0000',
      departureFromTemplate: 'Abfahrt von \u0000',
      departureFromAtTemplate: 'Abfahrt von \u0000 um \u0000',
      arrivalAtTemplate: 'Ankunft um \u0000',
      pageOfTemplate: 'Seite -1 von -2',
    );

    final bytes = await buildVoyagePdf(
      entry: liveEntry,
      stats: null,
      vesselName: 'Test Vessel',
      strings: strings,
      equipment: VesselEquipmentConfig.defaultForLocale('de'),
    );

    expect(bytes, isNotEmpty);
  });

  // The two tests below used to go all the way through buildVoyagePdf and
  // compare embedded-map PDF byte sizes, back when buildVoyagePdf rendered
  // the map tiles itself. Map rendering has since moved to the caller (see
  // captureTrackMapImage/capturePositionsMapImage in map_capture.dart, which
  // need a live, mounted BuildContext and so aren't reachable from this
  // isolate-only test harness) — buildVoyagePdf now just embeds whatever
  // trackImageBytes it's handed. What's still worth covering at this level
  // is the pure data-shaping those render calls are built on: positionedFixes
  // (which days get a fallback map at all) and entryMarkerPositions (which
  // positions get marked on it) — both still plain, widget-free functions.

  test('positionedFixes returns a day\'s logged GPS fixes, empty when there are none',
      () async {
    final home = HomeRepository();
    await home.init();
    final date = DateTime(2024, 1, 1);
    home.addEntry(date);
    final entry = home.getEntry(date)!;
    entry.timeline = [
      TimelineEntry(
        time: DateTime(2024, 1, 1, 10, 0),
        latitude: 39.5696,
        longitude: 2.6502,
      ),
    ];
    home.saveEntry(entry, changedFields: {'timeline'});
    final withPosition = home.getEntry(date)!;

    expect(positionedFixes(withPosition), [(39.5696, 2.6502)]);

    final date2 = DateTime(2024, 1, 2);
    home.addEntry(date2);
    final withoutPosition = home.getEntry(date2)!;

    expect(positionedFixes(withoutPosition), isEmpty);
  });

  test('entryMarkerPositions includes a timeline entry\'s own position even '
      'when it falls outside the day\'s GPS track bounds', () async {
    final home = HomeRepository();
    await home.init();
    final date = DateTime(2024, 1, 1);
    home.addEntry(date);

    // A real track the entry's own position could be checked against.
    await home.replaceTrackPoints(date, [
      TrackPoint(lat: 39.50, lon: 2.60, time: DateTime(2024, 1, 1, 9, 0)),
      TrackPoint(lat: 39.55, lon: 2.63, time: DateTime(2024, 1, 1, 10, 0)),
      TrackPoint(lat: 39.60, lon: 2.66, time: DateTime(2024, 1, 1, 11, 0)),
    ]);

    final entry = home.getEntry(date)!;
    // Deliberately outside the track's own bounds, to exercise the fallback
    // to the entry's own logged position rather than only ever correlating
    // onto the nearest track point.
    entry.timeline = [
      TimelineEntry(
        time: DateTime(2024, 1, 1, 9, 30),
        latitude: 39.80,
        longitude: 2.80,
      ),
    ];
    home.saveEntry(entry, changedFields: {'timeline'});
    final liveEntry = home.getEntry(date)!;
    final track = home.dailyTracks[date]!;

    expect(entryMarkerPositions(liveEntry, track.points), [(39.80, 2.80)]);
  });
}
