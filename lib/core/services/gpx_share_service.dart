import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

import 'crash_reporter.dart';

/// Bridges the native "Open with Logbook" GPX file association (registered
/// on iOS/Android for `.gpx` files) into a Dart stream, so the app can react
/// to a shared file the same way whether it arrived at cold start, while
/// backgrounded, or while already running in the foreground.
///
/// Also the durable, re-askable source of truth for "is a GPX import
/// pending, and what's its path" — the native side's own buffer
/// (`AppDelegate.pendingGpxPath` / `MainActivity.pendingGpxPath`) clears
/// itself on the very first pull, so anything that might need to ask again
/// (the router resolving a bare `/gpx-import`, an auth-settle retry) has to
/// go through [_stickyPath] here instead of re-querying native.
class GpxShareService {
  static const _channel = MethodChannel('com.ziegler.logbook/gpx_share');

  final _controller = StreamController<String>.broadcast();

  Stream<String> get gpxFilePaths => _controller.stream;

  String? _stickyPath;
  Future<String?>? _inFlight;

  /// The last path resolved (from either the warm-start push or a native
  /// pull) that hasn't been [clearPending]'d yet, without awaiting anything.
  String? get lastKnownPendingPath => _stickyPath;

  Future<void> init() async {
    // Handle files pushed while the engine is running (warm start / foreground).
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onGpxFile') {
        final path = (call.arguments as Map)['path'] as String?;
        if (path != null) {
          _stickyPath = path;
          _controller.add(path);
        }
      }
    });
    // getPendingGpxPath is NOT called here — the caller checks it AFTER
    // subscribing to the stream so the cold-start event is not missed.
  }

  /// Pulls the native cold-start buffer, memoized so concurrent callers
  /// share one native call instead of racing each other for the native
  /// side's one-shot buffer (which clears itself on the first read).
  Future<String?> _pull() {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;

    final future = () async {
      if (!Platform.isIOS && !Platform.isAndroid && !Platform.isMacOS) {
        return null;
      }
      try {
        final result =
            await _channel.invokeMethod<String>('getPendingGpxPath');
        if (result != null && result.isNotEmpty) {
          _stickyPath = result;
          return result;
        }
        return null;
      } catch (e, st) {
        reportNonFatal(e, st,
            reason: 'GpxShareService.checkPendingFile failed');
        return null;
      }
    }();
    _inFlight = future.whenComplete(() => _inFlight = null);
    return _inFlight!;
  }

  /// Call this AFTER subscribing to [gpxFilePaths], so the cold-start pending
  /// path is emitted to an active listener.
  Future<void> checkPendingFile() async {
    final result = await _pull();
    if (result != null) _controller.add(result);
  }

  /// Returns the pending GPX path, if any — [_stickyPath] immediately if
  /// already known, otherwise awaits a native pull. Used by the router to
  /// resolve a bare `/gpx-import` request (e.g. one forwarded by iOS as a
  /// `file://` route) into a concrete path.
  Future<String?> resolvePendingPath() async {
    if (_stickyPath != null) return _stickyPath;
    return _pull();
  }

  /// Marks [path] as consumed — called once [GpxImportScreen] has actually
  /// mounted with it. Only clears if [path] is still the current pending
  /// path, so a newer share that arrived in the meantime isn't clobbered.
  void clearPending(String path) {
    if (_stickyPath == path) _stickyPath = null;
  }

  void dispose() {
    _controller.close();
  }
}
