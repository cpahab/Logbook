// Regression coverage for the cold-start GPX share import fix: the native
// side's pending-path buffer (AppDelegate.pendingGpxPath /
// MainActivity.pendingGpxPath) clears itself atomically on its *first* read,
// so anything that might need to ask twice — the router resolving a bare
// /gpx-import, an auth-settle retry — has to go through GpxShareService's
// own sticky layer instead of re-querying native.
//
// GpxShareService._pull() (native getPendingGpxPath call) is guarded by
// `Platform.isIOS || Platform.isAndroid`, which is always false when
// `flutter test` runs on this desktop host — so that specific path, and the
// memoization around it, can only be exercised on-device (see the plan's
// manual verification checklist). What's tested here is everything that
// *isn't* platform-gated: the sticky path set by the warm-start push
// (onGpxFile), resolvePendingPath's fast path once sticky, and
// clearPending's match/no-match contract.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logbook/core/services/gpx_share_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.ziegler.logbook/gpx_share');

  Future<void> pushGpxFile(String path) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
        MethodCall('onGpxFile', {'path': path}),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('a warm-start push (onGpxFile) sets the sticky path and emits on the stream',
      () async {
    final service = GpxShareService();
    await service.init();

    final events = <String>[];
    service.gpxFilePaths.listen(events.add);

    await pushGpxFile('/inbox/warm.gpx');

    expect(events, ['/inbox/warm.gpx']);
    expect(service.lastKnownPendingPath, '/inbox/warm.gpx');
  });

  test('resolvePendingPath returns the sticky path immediately, without '
      'awaiting a native pull, once one is already known', () async {
    final service = GpxShareService();
    await service.init();
    await pushGpxFile('/inbox/warm.gpx');

    final resolved = await service.resolvePendingPath();

    expect(resolved, '/inbox/warm.gpx');
  });

  test('clearPending only clears when the path still matches', () async {
    final service = GpxShareService();
    await service.init();
    await pushGpxFile('/inbox/track.gpx');
    expect(service.lastKnownPendingPath, '/inbox/track.gpx');

    service.clearPending('/inbox/some-other-file.gpx');
    expect(service.lastKnownPendingPath, '/inbox/track.gpx',
        reason: 'clearing a different path must not clobber a still-pending one');

    service.clearPending('/inbox/track.gpx');
    expect(service.lastKnownPendingPath, isNull);
  });

  test('a second push after clearPending replaces the sticky path', () async {
    final service = GpxShareService();
    await service.init();
    await pushGpxFile('/inbox/first.gpx');
    service.clearPending('/inbox/first.gpx');
    expect(service.lastKnownPendingPath, isNull);

    await pushGpxFile('/inbox/second.gpx');

    expect(service.lastKnownPendingPath, '/inbox/second.gpx');
  });
}
