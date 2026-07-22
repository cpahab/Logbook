import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

import 'crypto_service.dart';
import 'logbook_key_store.dart';

/// Stores raw GPX files in Firebase Storage.
///
/// Path layout:
///   logbooks/{logbookId}/tracks/{yyyy-MM-dd}.gpx
///
/// Each day's track is gzip-compressed, then encrypted as a single AES-256-GCM
/// blob with the logbook's shared key (see [CryptoService]/[LogbookKeyStore])
/// before upload — a GPS track is exactly the kind of data this app's
/// encryption exists to protect, and treating it as one opaque blob (rather
/// than field-by-field, as Firestore's DayEntry fields are) is simplest since
/// it's already handled as a single upload/download unit.
class StorageService {
  final FirebaseStorage _storage;
  final String logbookId;
  final CryptoService _crypto;

  StorageService({required this.logbookId, required CryptoService crypto})
      : _storage = FirebaseStorage.instance,
        _crypto = crypto;

  /// Resolves (or creates) [logbookId]'s shared encryption key via
  /// [LogbookKeyStore] and constructs the service — the standard way to get
  /// a [StorageService] instance; the raw constructor above exists mainly
  /// for tests that supply their own [CryptoService].
  static Future<StorageService> create(String logbookId) async {
    final key = await LogbookKeyStore.getOrCreateKey(logbookId);
    return StorageService(logbookId: logbookId, crypto: CryptoService(key));
  }

  Reference _ref(DateTime date) => _storage
      .ref('logbooks/$logbookId/tracks/${_dateKey(date)}.gpx');

  // ------------------------------------------------------------------
  // Write
  // ------------------------------------------------------------------

  /// Uploads (or overwrites) the GPX file for [date]: gzip-compressed (GPX's
  /// per-point XML tags are verbose relative to the actual lat/lon/time
  /// payload, so this meaningfully shrinks upload size for longer tracks),
  /// then encrypted as one opaque blob. Content type is deliberately generic
  /// binary, not GPX/XML — the stored bytes are ciphertext, and no
  /// `contentEncoding: gzip` metadata is set either, since that would tell
  /// an HTTP layer to auto-decompress bytes that are no longer valid gzip
  /// once encrypted (the compression is application-level, applied before
  /// encryption, not a transport-level encoding of the stored object).
  Future<void> uploadTrack(DateTime date, Uint8List bytes) async {
    final gzipped = Uint8List.fromList(gzip.encode(bytes));
    final encrypted = await _crypto.encryptBytes(gzipped);
    await _ref(date).putData(
      encrypted,
      SettableMetadata(contentType: 'application/octet-stream'),
    );
  }

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

  /// Downloads GPX bytes for [date], decrypts, and gunzips them. Max 10 MB
  /// compressed+encrypted.
  Future<Uint8List?> downloadTrack(DateTime date) async {
    final raw = await _ref(date).getData(10 * 1024 * 1024);
    if (raw == null) return null;
    final decrypted = await _crypto.decryptBytes(raw);
    return Uint8List.fromList(gzip.decode(decrypted));
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
