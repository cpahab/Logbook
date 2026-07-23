import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

import 'crash_reporter.dart';

/// Bridges the native "Open with Logbook" GPX file association (registered
/// on iOS/Android for `.gpx` files) into a Dart stream, so the app can react
/// to a shared file the same way whether it arrived at cold start, while
/// backgrounded, or while already running in the foreground.
class GpxShareService {
  static const _channel = MethodChannel('com.ziegler.logbook/gpx_share');

  final _controller = StreamController<String>.broadcast();

  Stream<String> get gpxFilePaths => _controller.stream;

  Future<void> init() async {
    // Handle files pushed while the engine is running (warm start / foreground).
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onGpxFile') {
        final path = (call.arguments as Map)['path'] as String?;
        if (path != null) _controller.add(path);
      }
    });
    // getPendingGpxPath is NOT called here — the caller checks it AFTER
    // subscribing to the stream so the cold-start event is not missed.
  }

  /// Call this AFTER subscribing to [gpxFilePaths], so the cold-start pending
  /// path is emitted to an active listener.
  Future<void> checkPendingFile() async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    try {
      final result = await _channel.invokeMethod<String>('getPendingGpxPath');
      if (result != null && result.isNotEmpty) _controller.add(result);
    } catch (e, st) {
      reportNonFatal(e, st, reason: 'GpxShareService.checkPendingFile failed');
    }
  }

  void dispose() {
    _controller.close();
  }
}
