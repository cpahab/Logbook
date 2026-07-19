import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

/// Stores raw GPX files in Firebase Storage.
///
/// Path layout:
///   logbooks/{logbookId}/tracks/{yyyy-MM-dd}.gpx
class StorageService {
  final FirebaseStorage _storage;
  final String logbookId;

  StorageService({required this.logbookId})
      : _storage = FirebaseStorage.instance;

  Reference _ref(DateTime date) => _storage
      .ref('logbooks/$logbookId/tracks/${_dateKey(date)}.gpx');

  // ------------------------------------------------------------------
  // Write
  // ------------------------------------------------------------------

  /// Uploads (or overwrites) the raw GPX file for [date].
  ///
  /// Previously gzip-compressed with a `contentEncoding: 'gzip'` metadata
  /// tag to shrink upload/download size, but that silently broke sync
  /// entirely: newly imported tracks never reached Storage (uploads failed
  /// quietly — every call site swallows errors via `.catchError`) and so
  /// never appeared on other devices or survived a local reinstall. Reverted
  /// to plain uploads until compression can be re-validated against a real
  /// device/backend rather than reasoned about from code alone.
  Future<void> uploadTrack(DateTime date, Uint8List bytes) =>
      _ref(date).putData(
        bytes,
        SettableMetadata(contentType: 'application/gpx+xml'),
      );

  /// Deletes the GPX file for [date].
  Future<void> deleteTrack(DateTime date) => _ref(date).delete();

  // ------------------------------------------------------------------
  // Read
  // ------------------------------------------------------------------

  /// Returns dates that have a GPX file in Storage.
  Future<List<DateTime>> listTrackDates() async {
    final result = await _storage
        .ref('logbooks/$logbookId/tracks')
        .listAll();
    return result.items
        .map((r) => DateTime.tryParse(r.name.replaceFirst('.gpx', '')))
        .whereType<DateTime>()
        .toList();
  }

  /// Downloads GPX bytes for [date]. Max 10 MB. Tries gunzipping first and
  /// falls back to the raw bytes if that fails — uploads are plain again
  /// (see [uploadTrack]), but this keeps reading correctly for any track
  /// that was gzip-uploaded during the brief window compression was live.
  Future<Uint8List?> downloadTrack(DateTime date) async {
    final raw = await _ref(date).getData(10 * 1024 * 1024);
    if (raw == null) return null;
    try {
      return Uint8List.fromList(gzip.decode(raw));
    } catch (_) {
      return raw;
    }
  }

  // ------------------------------------------------------------------
  // Bulk delete
  // ------------------------------------------------------------------

  /// Deletes every file under `logbooks/{logbookId}/` (tracks + photos).
  /// Safe to call even if the folder is empty or doesn't exist.
  static Future<void> deleteLogbookFolder(String logbookId) =>
      _deleteRef(FirebaseStorage.instance.ref('logbooks/$logbookId'));

  /// Recursively deletes every file and sub-folder under [ref].
  static Future<void> _deleteRef(Reference ref) async {
    final result = await ref.listAll();
    await Future.wait([
      for (final item in result.items) item.delete(),
      for (final prefix in result.prefixes) _deleteRef(prefix),
    ]);
  }

  // ------------------------------------------------------------------

  /// Storage filename stem for a track: `yyyy-MM-dd`.
  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
