import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../../../core/services/firestore_service.dart';
import '../domain/emergency_contact.dart';

class EmergencyRepository extends ChangeNotifier {
  late Box<EmergencyContact> _box;

  /// Stores a single key `'modified_at'` (epoch-ms int) marking when contacts
  /// were last changed locally.
  late Box<int> _metaBox;

  FirestoreService? _firestore;
  StreamSubscription<List<Map<String, String>>?>? _contactsSub;

  List<EmergencyContact> get contacts => _box.values.toList();

  // ── Init ───────────────────────────────────────────────────────────────────

  Future<void> init() async {
    _box     = await Hive.openBox<EmergencyContact>('emergency_contacts');
    _metaBox = await Hive.openBox<int>('emergency_contacts_meta');
    notifyListeners();
  }

  // ── Local modification timestamp ───────────────────────────────────────────

  DateTime? get _localModifiedAt {
    final ms = _metaBox.get('modified_at');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  void _markModified() =>
      _metaBox.put('modified_at', DateTime.now().millisecondsSinceEpoch);

  // ── Firestore attachment ───────────────────────────────────────────────────

  /// Attaches Firestore and starts syncing emergency contacts.
  ///
  /// Conflict resolution mirrors [ThemeProvider.attachFirestore]:
  ///   • If no remote data exists → push local.
  ///   • If [initialSync] → push local first (migration), then pull remote.
  ///   • Otherwise: compare server `updatedAt` against local modification time;
  ///     whichever is newer wins.
  ///
  /// A real-time stream listener keeps contacts in sync while the app runs.
  Future<void> attachFirestore(FirestoreService service,
      {bool initialSync = false}) async {
    _firestore = service;

    await _contactsSub?.cancel();
    _contactsSub = null;

    try {
      if (initialSync) {
        // Only push if this device has locally modified contacts.
        // After clearLocalData() the meta box is empty (_localModifiedAt == null),
        // so we skip the push and let remoteIsNewer win below.
        if (_localModifiedAt != null) {
          await _pushToFirestore(service);
          _markModified();
        }
      }

      final (:contacts, :updatedAt) = await service.fetchContactsWithMeta();

      if (contacts == null) {
        // Nothing on the server yet — push local.
        await _pushToFirestore(service);
        _markModified();
      } else {
        final localMod = _localModifiedAt;
        final remoteIsNewer = localMod == null ||
            (updatedAt != null && updatedAt.isAfter(localMod));

        if (remoteIsNewer) {
          await _replaceLocalContacts(contacts);
        } else {
          // Local is newer — push it.
          await _pushToFirestore(service);
        }
      }
    } catch (_) {
      // Offline — continue with local data.
    }

    // Real-time listener: apply remote changes while the app is running.
    _contactsSub = service.contactsChanges().listen((remote) async {
      if (remote == null) return;
      // Skip echo from our own push by comparing content.
      if (_contactsEqual(remote)) return;
      await _replaceLocalContacts(remote);
    }, onError: (_) {});
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  Future<void> addContact(EmergencyContact contact) async {
    await _box.add(contact);
    _markModified();
    _syncToFirestore();
    notifyListeners();
  }

  Future<void> removeContact(EmergencyContact contact) async {
    await contact.delete();
    _markModified();
    _syncToFirestore();
    notifyListeners();
  }

  Future<void> updateContact(int key, EmergencyContact updated) async {
    await _box.put(key, updated);
    _markModified();
    _syncToFirestore();
    notifyListeners();
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  void _syncToFirestore() {
    if (_firestore == null) { return; }
    _pushToFirestore(_firestore!).catchError((_) {});
  }

  Future<void> _pushToFirestore(FirestoreService service) =>
      service.saveEmergencyContacts(
        contacts.map((c) => {'name': c.name, 'role': c.role, 'phone': c.phone}).toList(),
      );

  /// Replaces the local Hive box content with [remote] contacts.
  Future<void> _replaceLocalContacts(List<Map<String, String>> remote) async {
    await _box.clear();
    for (final c in remote) {
      await _box.add(EmergencyContact(
        name:  c['name']  ?? '',
        role:  c['role']  ?? '',
        phone: c['phone'] ?? '',
      ));
    }
    notifyListeners();
  }

  /// Wipes all local Hive data without re-attaching.
  ///
  /// Call this before [attachFirestore] when a different user signs in.
  Future<void> clearLocalData() async {
    await _contactsSub?.cancel();
    _contactsSub = null;
    await _box.clear();
    await _metaBox.clear();
    notifyListeners();
  }

  /// Returns true if [remote] contains the same contacts (by name/role/phone)
  /// as the local box — used to skip echoes from our own Firestore pushes.
  bool _contactsEqual(List<Map<String, String>> remote) {
    final local = contacts;
    if (local.length != remote.length) return false;
    for (int i = 0; i < local.length; i++) {
      final l = local[i];
      final r = remote[i];
      if (l.name != (r['name'] ?? '') ||
          l.role != (r['role'] ?? '') ||
          l.phone != (r['phone'] ?? '')) { return false; }
    }
    return true;
  }
}
