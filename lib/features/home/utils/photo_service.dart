import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/services/logbook_key_store.dart';

/// Picks, compresses, uploads, and locally caches day-entry photos, backed
/// by Firebase Storage with a documents-directory disk cache so a photo
/// already downloaded once doesn't need re-fetching.
///
/// Bytes are AES-256-GCM encrypted before every Storage upload and decrypted
/// after every download, using the owning logbook's shared key (see
/// `CryptoService`/`LogbookKeyStore`) — extracted from [storagePath] itself
/// (its first segment, `logbooks/{logbookId}/...`) rather than threaded
/// through every caller's signature. The local disk cache deliberately
/// stays plaintext after that first decrypt (matches the app's existing
/// cache behavior) — only the Storage-side blob and in-transit bytes are
/// encrypted.
class PhotoService {
  // Max long-side dimension for uploaded photos.
  // Covers Retina screen display and 4-up PDF thumbnails at 300 dpi.
  static const int _maxSide = 1920;
  static const int _jpegQuality = 85;

  /// The local disk-cache directory for downloaded/uploaded photos, creating
  /// it if it doesn't exist yet.
  static Future<Directory> _cacheDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/photo_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// The logbook id embedded as [storagePath]'s second segment
  /// (`logbooks/{logbookId}/photos/...`), for resolving that logbook's
  /// encryption key without requiring every caller to pass it separately.
  static String _logbookIdFromPath(String storagePath) =>
      storagePath.split('/')[1];

  /// The local cache filename for a Firebase Storage [storagePath] — just
  /// its last path segment.
  static String _cacheFilename(String storagePath) =>
      storagePath.split('/').last;

  /// Decodes just enough of [bytes] to read its pixel dimensions, without
  /// pulling in a whole extra image-processing dependency for it.
  static Future<(int width, int height)> _decodeDimensions(
      Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size = (frame.image.width, frame.image.height);
    frame.image.dispose();
    codec.dispose();
    return size;
  }

  /// [flutter_image_compress]'s `minWidth`/`minHeight` aren't a "max long
  /// side" cap on their own: it scales down by
  /// `max(1, min(srcW/minWidth, srcH/minHeight))`, so passing the same
  /// value for both (as this used to) only bounds whichever side is
  /// relatively shorter — for a 4:3 landscape photo, the long side actually
  /// overshoots to ~1.33x [_maxSide] (~1.8x the intended pixel count).
  /// Scaling [minWidth]/[minHeight] here to [srcW]/[srcH]'s own aspect
  /// ratio makes both scale factors equal, so the long side lands on
  /// exactly [_maxSide] and the short side scales proportionally — while
  /// still leaving already-smaller images untouched, since the package
  /// clamps to `max(1, ...)` regardless.
  static (int minWidth, int minHeight) _targetSize(int srcW, int srcH) {
    if (srcW >= srcH) {
      return (_maxSide, (_maxSide * srcH / srcW).round());
    }
    return ((_maxSide * srcW / srcH).round(), _maxSide);
  }

  /// Picks images, compresses them (max 1920 px, JPEG 85 %), caches locally
  /// and uploads to Firebase Storage under the logbook's namespace.
  /// Returns the Storage paths of successes.
  ///
  /// Uses [withData: true] so that [f.bytes] is always populated — this is the
  /// only reliable path on iOS where PHAsset-backed picks may have no [f.path].
  static Future<List<String>> pickAndUpload(DateTime day, String logbookId) async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return [];

    final dateStr = DateFormat('yyyy-MM-dd').format(day);
    final uploaded = <String>[];

    for (final f in result.files) {
      // Prefer in-memory bytes (always present when withData:true); fall back
      // to reading from path in case the platform only fills one of them.
      final srcBytes = f.bytes?.isNotEmpty == true
          ? f.bytes!
          : (f.path != null ? await File(f.path!).readAsBytes() : null);
      if (srcBytes == null || srcBytes.isEmpty) continue;

      final id = '${DateTime.now().millisecondsSinceEpoch}';
      final storagePath = 'logbooks/$logbookId/photos/$dateStr/$id.jpg';
      try {
        // Falls back to capping both dimensions at _maxSide directly (the
        // previous, imprecise behavior) if the source can't be decoded for
        // its dimensions — still produces a usable, just not perfectly
        // long-side-capped, photo rather than losing it entirely.
        var minWidth = _maxSide;
        var minHeight = _maxSide;
        try {
          final (srcW, srcH) = await _decodeDimensions(srcBytes);
          (minWidth, minHeight) = _targetSize(srcW, srcH);
        } catch (_) {}

        final compressed = await FlutterImageCompress.compressWithList(
          srcBytes,
          minWidth: minWidth,
          minHeight: minHeight,
          quality: _jpegQuality,
          format: CompressFormat.jpeg,
          keepExif: false,
        );
        final plainBytes = compressed.isNotEmpty ? compressed : srcBytes;
        final cache = await _cacheDir();
        final local = File('${cache.path}/$id.jpg');
        // Cache stays plaintext — only the Storage-side copy is encrypted.
        await local.writeAsBytes(plainBytes);
        // The local cache write above is what makes the photo usable (see
        // localFile, which checks the cache before ever touching Storage),
        // so it counts as success on its own — the Storage upload is
        // best-effort, same as restorePhoto's treatment of it, so a local-mode
        // or offline user (no authenticated Storage access) doesn't silently
        // lose every photo they add.
        uploaded.add(storagePath);
        try {
          final crypto = await LogbookKeyStore.getCryptoService(logbookId);
          final encrypted = await crypto.encryptBytes(Uint8List.fromList(plainBytes));
          await FirebaseStorage.instance.ref(storagePath).putData(
                encrypted,
                SettableMetadata(contentType: 'application/octet-stream'),
              );
        } catch (_) {
          // Expected for local-mode/offline users (no authenticated Storage
          // access) — same silent, best-effort treatment as restorePhoto.
        }
      } catch (e, st) {
        if (kDebugMode) debugPrint('[PhotoService] photo processing failed: $e\n$st');
      }
    }
    return uploaded;
  }

  /// Writes [bytes] (plaintext, from a backup archive — backups themselves
  /// stay unencrypted by design) to the local cache for [storagePath] and
  /// re-uploads them, encrypted, to Firebase Storage at that exact path —
  /// used when restoring a photo from a backup, where both the cache and
  /// the remote blob need to exist again after a wipe.
  static Future<void> restorePhoto(String storagePath, List<int> bytes) async {
    final cache = await _cacheDir();
    final local = File('${cache.path}/${_cacheFilename(storagePath)}');
    await local.writeAsBytes(bytes);
    try {
      final crypto = await LogbookKeyStore.getCryptoService(_logbookIdFromPath(storagePath));
      final encrypted = await crypto.encryptBytes(Uint8List.fromList(bytes));
      await FirebaseStorage.instance.ref(storagePath).putData(
            encrypted,
            SettableMetadata(contentType: 'application/octet-stream'),
          );
    } catch (_) {
      // Best-effort: the local cache is restored either way, so the photo
      // still displays even if the Storage re-upload fails (e.g. offline).
    }
  }

  /// Returns the locally cached [File] for [storagePath], downloading and
  /// decrypting from Firebase Storage if not yet cached (the cache itself
  /// stays plaintext once written). Returns null on failure.
  static Future<File?> localFile(String storagePath) async {
    final cache = await _cacheDir();
    final local = File('${cache.path}/${_cacheFilename(storagePath)}');
    if (await local.exists()) return local;
    try {
      final encrypted = await FirebaseStorage.instance.ref(storagePath).getData(
            10 * 1024 * 1024, // 10 MB — generous for a single compressed photo.
          );
      if (encrypted == null) return null;
      final crypto = await LogbookKeyStore.getCryptoService(_logbookIdFromPath(storagePath));
      final decrypted = await crypto.decryptBytes(encrypted);
      await local.writeAsBytes(decrypted);
      return local;
    } catch (_) {
      return null;
    }
  }

  /// Deletes the photo from Firebase Storage and removes the local cache
  /// file. Returns true if the Storage object is confirmed gone — deleted
  /// just now, or already absent — false if the attempt should be retried
  /// later (mirrors StorageService.deleteTrack's same distinction, used by
  /// HomeRepository's pending-delete retry mechanism so a failed/offline
  /// delete doesn't silently leave the blob orphaned in Storage forever).
  static Future<bool> delete(String storagePath) async {
    var storageOk = false;
    try {
      await FirebaseStorage.instance.ref(storagePath).delete();
      storageOk = true;
    } on FirebaseException catch (e) {
      storageOk = e.code == 'object-not-found';
    } catch (_) {}
    final cache = await _cacheDir();
    final local = File('${cache.path}/${_cacheFilename(storagePath)}');
    if (await local.exists()) await local.delete();
    return storageOk;
  }

}
