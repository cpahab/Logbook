// Regression coverage for a reported bug: a freshly imported GPX track
// rendered fine but disappeared after restarting the app (and never
// appeared on other devices). Simulates a restart by dropping the
// HomeRepository instance that performed the import and creating a brand
// new one against the SAME on-disk Hive boxes, exactly like a real app
// relaunch would.

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
}
