import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

class PhotoService {
  // Max long-side dimension for uploaded photos.
  // Covers Retina screen display and 4-up PDF thumbnails at 300 dpi.
  static const int _maxSide = 1920;
  static const int _jpegQuality = 85;

  static Future<Directory> _cacheDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/photo_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _cacheFilename(String storagePath) =>
      storagePath.split('/').last;

  /// Picks images, compresses them (max 1920 px, JPEG 85 %), caches locally
  /// and uploads to Firebase Storage under the boat's namespace.
  /// Returns the Storage paths of successes.
  ///
  /// Uses [withData: true] so that [f.bytes] is always populated — this is the
  /// only reliable path on iOS where PHAsset-backed picks may have no [f.path].
  static Future<List<String>> pickAndUpload(DateTime day, String boatId) async {
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
      final storagePath = 'boats/$boatId/photos/$dateStr/$id.jpg';
      try {
        final compressed = await FlutterImageCompress.compressWithList(
          srcBytes,
          minWidth: _maxSide,
          minHeight: _maxSide,
          quality: _jpegQuality,
          format: CompressFormat.jpeg,
          keepExif: false,
        );
        final cache = await _cacheDir();
        final local = File('${cache.path}/$id.jpg');
        await local.writeAsBytes(compressed.isNotEmpty ? compressed : srcBytes);
        await FirebaseStorage.instance.ref(storagePath).putFile(local);
        uploaded.add(storagePath);
      } catch (_) {}
    }
    return uploaded;
  }

  /// Returns the locally cached [File] for [storagePath], downloading from
  /// Firebase Storage if not yet cached.  Returns null on failure.
  static Future<File?> localFile(String storagePath) async {
    final cache = await _cacheDir();
    final local = File('${cache.path}/${_cacheFilename(storagePath)}');
    if (await local.exists()) return local;
    try {
      await FirebaseStorage.instance.ref(storagePath).writeToFile(local);
      return local;
    } catch (_) {
      return null;
    }
  }

  /// Deletes the photo from Firebase Storage and removes the local cache file.
  static Future<void> delete(String storagePath) async {
    try {
      await FirebaseStorage.instance.ref(storagePath).delete();
    } catch (_) {}
    final cache = await _cacheDir();
    final local = File('${cache.path}/${_cacheFilename(storagePath)}');
    if (await local.exists()) await local.delete();
  }

}
