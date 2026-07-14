import 'dart:math';

import 'package:hive/hive.dart';

/// Manages the on-device registry of local (device-only, no cloud) logbooks
/// — the local-mode analogue of [LogbookService], but Hive-based since local
/// logbooks have no Firestore document.
///
/// Registry layout: a single `Box<String>` named [_registryBoxName], keyed
/// by logbook id, valued by logbook name. The empty-string id is a reserved
/// sentinel for the first/default local logbook a device ever gets — it
/// resolves to the same unsuffixed Hive box names a cloud user's single
/// dataset already uses (see [HomeRepository.init]/[EmergencyRepository.init]/
/// [ThemeProvider.init]'s `datasetSuffix` convention), so creating it never
/// requires renaming or copying any data. Every other logbook gets a real
/// generated id and genuinely suffixed boxes.
class LocalLogbookService {
  static const _registryBoxName = 'local_logbooks_registry';

  Future<Box<String>> _registry() => Hive.openBox<String>(_registryBoxName);

  /// Every local logbook on this device as (id, name) pairs.
  Future<List<(String id, String name)>> listLogbooks() async {
    final box = await _registry();
    return box.keys
        .map((k) => (k as String, box.get(k)!))
        .toList();
  }

  /// Creates a new local logbook with a freshly generated id. Returns the id.
  Future<String> createLogbook(String name) async {
    final box = await _registry();
    final id = _generateId();
    await box.put(id, name);
    return id;
  }

  /// Registers a logbook under an explicit [id] — used only to seed the
  /// reserved empty-string sentinel logbook (see the class doc). Not for
  /// general use; regular logbook creation always goes through
  /// [createLogbook] so it gets a real generated id.
  Future<void> createLogbookWithId(String id, String name) async {
    final box = await _registry();
    await box.put(id, name);
  }

  Future<void> renameLogbook(String id, String name) async {
    final box = await _registry();
    await box.put(id, name);
  }

  /// Deletes [id]'s registry entry and all 7 Hive boxes associated with it
  /// (4 from `HomeRepository`, 2 from `EmergencyRepository`, 1 settings box)
  /// — never just clears them, so nothing lingers as an orphaned empty file.
  ///
  /// The caller must ensure [id] is not the currently-active local logbook
  /// before calling this — deleting a logbook whose boxes are open elsewhere
  /// in the process is undefined.
  Future<void> deleteLogbook(String id) async {
    final box = await _registry();
    await box.delete(id);

    final s = id.isEmpty ? '' : '_$id';
    for (final name in [
      'daily_entries$s',
      'daily_tracks$s',
      'crew_roster$s',
      'entry_sync_state$s',
      'emergency_contacts$s',
      'emergency_contacts_meta$s',
      id.isEmpty ? 'settings' : 'settings_local_$id',
    ]) {
      await Hive.deleteBoxFromDisk(name);
    }
  }

  /// Generates a collision-resistant, filesystem/Hive-box-name-safe id —
  /// same pattern as `HomeRepository._newId()`.
  static String _generateId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
