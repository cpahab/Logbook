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

  /// Uploads (or overwrites) the GPX file for [date], gzip-compressed —
  /// GPX's per-point XML tags are verbose relative to the actual lat/lon/
  /// time payload, so this meaningfully shrinks upload size (and every
  /// subsequent download) for longer tracks.
  ///
  /// This was briefly reverted to plain uploads on suspicion of breaking
  /// sync entirely, but that turned out to be a different bug: removeGpx()
  /// sets a trackDeletedAt tombstone on the entry that no import path ever
  /// cleared, so a re-imported track got deleted again by the very next
  /// sync regardless of upload compression (see home_repository.dart's
  /// _saveTrack). With that fixed and covered by a regression test,
  /// compression is safe to restore.
  Future<void> uploadTrack(DateTime date, Uint8List bytes) =>
      _ref(date).putData(
        Uint8List.fromList(gzip.encode(bytes)),
        SettableMetadata(
          contentType: 'application/gpx+xml',
          contentEncoding: 'gzip',
        ),
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

  /// Downloads GPX bytes for [date] and gunzips them. Max 10 MB compressed.
  /// Falls back to the raw bytes if they aren't valid gzip — either an
  /// older track uploaded before compression was (re-)added, or a download
  /// path that already decoded the Content-Encoding transparently — so
  /// this reads correctly regardless of how the bytes arrived.
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
