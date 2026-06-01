import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

/// Stores raw GPX files in Firebase Storage.
///
/// Path layout:
///   logbooks/{installationId}/tracks/{yyyy-MM-dd}.gpx
class StorageService {
  final FirebaseStorage _storage;
  final String installationId;

  StorageService({required this.installationId})
      : _storage = FirebaseStorage.instance;

  Reference _ref(DateTime date) => _storage
      .ref('logbooks/$installationId/tracks/${_dateKey(date)}.gpx');

  // ------------------------------------------------------------------
  // Write
  // ------------------------------------------------------------------

  Future<void> uploadTrack(DateTime date, Uint8List bytes) =>
      _ref(date).putData(
        bytes,
        SettableMetadata(contentType: 'application/gpx+xml'),
      );

  Future<void> deleteTrack(DateTime date) => _ref(date).delete();

  // ------------------------------------------------------------------
  // Read
  // ------------------------------------------------------------------

  /// Returns dates that have a GPX file in Storage.
  Future<List<DateTime>> listTrackDates() async {
    final result = await _storage
        .ref('logbooks/$installationId/tracks')
        .listAll();
    return result.items
        .map((r) => DateTime.tryParse(r.name.replaceFirst('.gpx', '')))
        .whereType<DateTime>()
        .toList();
  }

  /// Downloads raw GPX bytes for [date]. Max 10 MB.
  Future<Uint8List?> downloadTrack(DateTime date) =>
      _ref(date).getData(10 * 1024 * 1024);

  // ------------------------------------------------------------------

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
