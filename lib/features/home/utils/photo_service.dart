import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

class PhotoService {
  static Future<Directory> _cacheDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/photo_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // The storage path is "photos/YYYY-MM-DD/<id>.jpg" — the last segment
  // uniquely identifies the local cache file.
  static String _cacheFilename(String storagePath) =>
      storagePath.split('/').last;

  /// Presents the system image picker, copies chosen files to local cache and
  /// uploads them to Firebase Storage.  Returns the list of Storage paths for
  /// successfully uploaded images.
  static Future<List<String>> pickAndUpload(DateTime day) async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return [];

    final dateStr = DateFormat('yyyy-MM-dd').format(day);
    final uploaded = <String>[];

    for (final f in result.files) {
      if (f.path == null) continue;
      final id = '${DateTime.now().millisecondsSinceEpoch}';
      final storagePath = 'photos/$dateStr/$id.jpg';
      try {
        final src = File(f.path!);
        final cache = await _cacheDir();
        final local = File('${cache.path}/$id.jpg');
        await src.copy(local.path);
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
