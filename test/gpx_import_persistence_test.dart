// Regression coverage for a reported bug: a freshly imported GPX track
// rendered fine but disappeared minutes later (noticed on the next app
// restart), and never appeared on other devices. Two things are covered:
//
// 1. Plain local persistence survives a simulated restart (dropping the
//    HomeRepository instance and opening a fresh one against the same
//    on-disk Hive boxes) — ruling out a plain storage bug.
// 2. The actual root cause: removeGpx() sets the entry's trackDeletedAt
//    tombstone, but no import path ever cleared it back. Re-importing a
//    track for a day whose track was previously removed rendered fine
//    immediately, but the next sync (the live entry listener, or a routine
//    incremental refresh on screen navigation) pulled the entry back down,
//    saw the still-set tombstone, and applyIncomingEntry unconditionally
//    deleted the track again — both locally and in Storage. _saveTrack now
//    clears trackDeletedAt whenever a track is (re)saved.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:logbook/features/home/data/home_repository.dart';
import 'package:logbook/features/home/domain/crew_member.dart';
import 'package:logbook/features/home/domain/daily_track.dart';
import 'package:logbook/features/home/domain/day_entry.dart';
import 'package:logbook/features/home/domain/timeline_amendment.dart';
import 'package:logbook/features/home/domain/timeline_entry.dart';
import 'package:logbook/features/home/domain/track_point.dart';

const _sampleGpx = '''
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="test">
  <trk><name>test</name><trkseg>
    <trkpt lat="47.1" lon="9.1"><time>2026-08-01T09:00:00Z</time></trkpt>
    <trkpt lat="47.2" lon="9.2"><time>2026-08-01T09:01:00Z</time></trkpt>
    <trkpt lat="47.3" lon="9.3"><time>2026-08-01T09:02:00Z</time></trkpt>
  </trkseg></trk>
</gpx>
''';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gpx_import_persistence_test_');
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

  test('an imported GPX track survives a simulated app restart', () async {
    final date = DateTime(2026, 8, 1);

    final first = HomeRepository();
    await first.init();
    await first.importGpxFromBytes(
      date,
      Uint8List.fromList(_sampleGpx.codeUnits),
      'test.gpx',
    );

    expect(first.dailyTracks[date], isNotNull);
    expect(first.dailyTracks[date]!.points.length, 3);

    // Simulate an app restart: drop this instance, open a fresh one against
    // the same on-disk Hive boxes (Hive.init already points at tempDir).
    final second = HomeRepository();
    await second.init();

    expect(second.dailyTracks[date], isNotNull,
        reason: 'the imported track must survive a restart');
    expect(second.dailyTracks[date]!.points.length, 3);
  });

  test('a realistically large (1000-fix) imported track also survives a '
      'simulated app restart', () async {
    final date = DateTime(2026, 8, 2);
    final start = DateTime.utc(2026, 8, 2, 9, 0, 0);
    final trkpts = StringBuffer();
    for (var i = 0; i < 1000; i++) {
      final lat = 47.1 + i * 0.0001;
      final lon = 9.1 + i * 0.0001;
      final time = start.add(Duration(seconds: i * 20));
      trkpts.writeln(
          '<trkpt lat="${lat.toStringAsFixed(6)}" lon="${lon.toStringAsFixed(6)}">'
          '<time>${time.toIso8601String()}</time></trkpt>');
    }
    final gpx = '<?xml version="1.0" encoding="UTF-8"?>'
        '<gpx version="1.1" creator="test"><trk><name>big</name><trkseg>'
        '$trkpts</trkseg></trk></gpx>';

    final first = HomeRepository();
    await first.init();
    await first.importGpxFromBytes(
      date,
      Uint8List.fromList(gpx.codeUnits),
      'big.gpx',
    );

    expect(first.dailyTracks[date], isNotNull);
    expect(first.dailyTracks[date]!.points.length, 1000);

    final second = HomeRepository();
    await second.init();

    expect(second.dailyTracks[date], isNotNull,
        reason: 'a realistically large imported track must survive a restart');
    expect(second.dailyTracks[date]!.points.length, 1000);
  });

  test('re-importing a track after removeGpx clears the stale '
      'trackDeletedAt tombstone, so the next sync does not delete it again',
      () async {
    final date = DateTime(2026, 8, 3);
    final repo = HomeRepository();
    await repo.init();
    repo.addEntry(date);

    await repo.importGpxFromBytes(
      date,
      Uint8List.fromList(_sampleGpx.codeUnits),
      'test.gpx',
    );
    expect(repo.dailyTracks[date], isNotNull);

    // Mirrors what the user actually did: remove the track, then re-import it.
    await repo.removeGpx(date);
    expect(repo.dailyTracks[date], isNull);
    expect(repo.getEntry(date)!.trackDeletedAt, isNotNull);

    await repo.importGpxFromBytes(
      date,
      Uint8List.fromList(_sampleGpx.codeUnits),
      'test.gpx',
    );
    expect(repo.dailyTracks[date], isNotNull);
    expect(repo.getEntry(date)!.trackDeletedAt, isNull,
        reason: 're-saving a track must clear the stale tombstone, or the '
            'next sync will delete the track right back out again');

    // Simulate the next sync (live listener / incremental refresh) pulling
    // this same entry back down — before the fix, its still-set
    // trackDeletedAt would make this delete the just-restored track again.
    await repo.applyIncomingEntry(repo.getEntry(date)!, respectLocalEdit: false);
    expect(repo.dailyTracks[date], isNotNull,
        reason: 'a sync applying the (now-cleared) entry must not delete '
            'the freshly re-imported track');
  });
}
