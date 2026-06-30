import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

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

    // Pull any file that arrived during cold start before the engine was ready.
    if (Platform.isIOS || Platform.isAndroid) {
      try {
        final result =
            await _channel.invokeMethod<String>('getPendingGpxPath');
        if (result != null && result.isNotEmpty) {
          _controller.add(result);
        }
      } catch (_) {
        // Native side may not have a pending file — ignore.
      }
    }
  }

  void dispose() {
    _controller.close();
  }
}
