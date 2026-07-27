import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../../../core/services/firestore_service.dart';
import '../../../core/services/logbook_key_store.dart';
import '../domain/emergency_contact.dart';

/// Local (Hive) + cloud (Firestore) store for the emergency contacts list
/// shown on the Emergency Manifest screen. Mirrors HomeRepository's
/// last-writer-wins sync strategy, but scoped to one small document instead
/// of per-day entries.
class EmergencyRepository extends ChangeNotifier {
  late Box<EmergencyContact> _box;

  /// Stores a single key `'modified_at'` (epoch-ms int) marking when contacts
  /// were last changed locally.
  late Box<int> _metaBox;

  FirestoreService? _firestore;
  StreamSubscription<List<Map<String, String>>?>? _contactsSub;

  /// True during an Emergency Manifest edit-mode session — see
  /// [beginEditing]/[endEditingAndSync]. While true, mutations skip the
  /// per-call Firestore push (deferred to a single push in
  /// [endEditingAndSync]) and the live listener is paused, so a concurrent
  /// edit from another device can't overwrite this device's in-progress,
  /// not-yet-pushed local changes mid-session.
  bool _editing = false;

  List<EmergencyContact> get contacts => _box.values.toList();

  // ── Init ───────────────────────────────────────────────────────────────────

  /// [datasetSuffix] is null for the default dataset (today's exact box
  /// names) or a local logbook id for a non-default local logbook — see
  /// [HomeRepository.init] for the identical convention.
  Future<void> init({String? datasetSuffix}) async {
    final s = datasetSuffix == null ? '' : '_$datasetSuffix';
    final cipher = await DeviceHiveKeyStore.getOrCreateCipher();
    _box     = await Hive.openBox<EmergencyContact>('emergency_contacts$s', encryptionCipher: cipher);
    _metaBox = await Hive.openBox<int>('emergency_contacts_meta$s', encryptionCipher: cipher);
    notifyListeners();
  }

  /// Switches to a different local logbook's contacts dataset. Opens the
  /// new boxes and swaps them in *before* closing the old ones, so
  /// [contacts] — which reads straight from the Hive box on every call, not
  /// from an in-memory cache — can never observe a closed box, even if a
  /// widget rebuild lands mid-switch. See [HomeRepository.switchLocalDataset].
  Future<void> switchLocalDataset(String newLogbookId) async {
    await _contactsSub?.cancel();
    _contactsSub = null;

    final oldBox = _box;
    final oldMetaBox = _metaBox;

    final s = newLogbookId.isEmpty ? '' : '_$newLogbookId';
    final cipher = await DeviceHiveKeyStore.getOrCreateCipher();
    _box     = await Hive.openBox<EmergencyContact>('emergency_contacts$s', encryptionCipher: cipher);
    _metaBox = await Hive.openBox<int>('emergency_contacts_meta$s', encryptionCipher: cipher);
    notifyListeners();

    await oldBox.close();
    await oldMetaBox.close();
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

    await _fetchAndReconcile(service, initialSync: initialSync);

    // Real-time listener: apply remote changes while the app is running.
    // asyncMap (not a raw .listen((remote) async {...})) so a second
    // snapshot event can't start applying before the first has finished —
    // Stream.listen does NOT wait for an async callback before delivering
    // the next event, so two close-together events could otherwise run
    // _replaceLocalContacts concurrently and race its clear-then-add-each
    // sequence into duplicated entries. Matches HomeRepository's entries/
    // roster listeners, which use the same asyncMap pattern.
    _contactsSub = service.contactsChanges().asyncMap((remote) async {
      if (_editing) return;
      if (remote == null) return;
      // Skip echo from our own push by comparing content.
      if (_contactsEqual(remote)) return;
      await _replaceLocalContacts(remote);
    }).listen((_) {}, onError: (_) {});
  }

  /// One-shot fetch-and-reconcile against the server: whichever of local vs
  /// remote is newer wins, exactly as [attachFirestore]'s own initial pull
  /// does. Used there, and by [refreshContacts] as a fallback for when the
  /// live listener's underlying stream has gone stale (e.g. the OS
  /// suspended it while this device was backgrounded) — a real, observed
  /// gap: a contact added on another device could sit unseen on this one
  /// until a full app relaunch re-ran this same logic.
  Future<void> _fetchAndReconcile(FirestoreService service,
      {bool initialSync = false}) async {
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
  }

  /// Re-runs the same fetch-and-reconcile [attachFirestore] does on its
  /// initial pull, without touching the live listener subscription. Call
  /// when the Emergency Manifest screen opens: the live listener alone
  /// isn't reliable enough on its own — its underlying stream can go stale
  /// while this device was backgrounded — so this gives every screen visit
  /// a fresh, guaranteed-correct check instead of depending on it.
  /// No-ops if Firestore isn't attached (offline/local mode).
  Future<void> refreshContacts() async {
    final service = _firestore;
    if (service == null || _editing) return;
    await _fetchAndReconcile(service);
  }

  /// Starts a local-only edit session (the Emergency Manifest's edit-mode
  /// toggle): further add/remove/update calls skip their per-mutation
  /// Firestore push, and the live listener ignores incoming remote changes,
  /// until [endEditingAndSync] pushes the session's final result once and
  /// resumes listening. Narrows the window for a concurrent edit from
  /// another device to race with this device's in-progress changes down to
  /// a single push instead of one per keystroke/add/remove.
  void beginEditing() {
    _editing = true;
  }

  /// Ends a session started by [beginEditing]: pushes the current local
  /// list once and resumes applying remote changes.
  Future<void> endEditingAndSync() async {
    _editing = false;
    _markModified();
    _syncToFirestore();
  }

  /// Switches contacts to a different logbook. [remoteContacts] must already
  /// have been fetched by the caller (via
  /// [FirestoreService.fetchContactsWithMeta]) — this only applies it, it
  /// never wipes local state to attempt its own fetch. Callers should fetch
  /// first and abort the whole logbook switch on failure, exactly as
  /// [HomeRepository.reattachAndSync] does for day entries, so a network
  /// blip during a switch can never leave contacts wiped with nothing
  /// confirmed to replace them.
  ///
  /// [remoteContacts] null means the new logbook has no contacts document
  /// yet — local contacts clear to empty and that becomes the first write.
  Future<void> applySwitchedLogbookContacts(
      List<Map<String, String>>? remoteContacts, FirestoreService service) async {
    await _contactsSub?.cancel();
    _contactsSub = null;

    _firestore = service;

    if (remoteContacts != null) {
      await _replaceLocalContacts(remoteContacts);
    } else {
      await _box.clear();
      await _pushToFirestore(service);
      notifyListeners();
    }
    _markModified();

    // See attachFirestore's identical listener for why asyncMap (not a raw
    // .listen((remote) async {...})) is required here.
    _contactsSub = service.contactsChanges().asyncMap((remote) async {
      if (_editing) return;
      if (remote == null) return;
      if (_contactsEqual(remote)) return;
      await _replaceLocalContacts(remote);
    }).listen((_) {}, onError: (_) {});
  }

  // ── Mutations ──────────────────────────────────────────────────────────────
  // Each of these pushes to Firestore immediately UNLESS a [beginEditing]
  // session is active, in which case the push is deferred to that session's
  // single [endEditingAndSync] call — see its doc comment for why.

  /// Adds [contact] locally and pushes the updated list to Firestore.
  Future<void> addContact(EmergencyContact contact) async {
    await _box.add(contact);
    _markModified();
    if (!_editing) _syncToFirestore();
    notifyListeners();
  }

  /// Removes [contact] locally and pushes the updated list to Firestore.
  Future<void> removeContact(EmergencyContact contact) async {
    await contact.delete();
    _markModified();
    if (!_editing) _syncToFirestore();
    notifyListeners();
  }

  /// Replaces the contact at Hive key [key] with [updated] and pushes the
  /// updated list to Firestore.
  Future<void> updateContact(int key, EmergencyContact updated) async {
    await _box.put(key, updated);
    _markModified();
    if (!_editing) _syncToFirestore();
    notifyListeners();
  }

  /// Persists [newOrder] as the contacts' explicit display order (a drag
  /// reorder on the Emergency Manifest screen) and pushes it to Firestore.
  /// Clears and re-adds rather than reusing existing keys — Hive's
  /// iteration order follows insertion order, not key order — mirroring
  /// the same pattern [HomeRepository.reorderRoster] uses for the roster.
  Future<void> reorderContacts(List<EmergencyContact> newOrder) async {
    await _box.clear();
    for (final c in newOrder) {
      await _box.add(c);
    }
    _markModified();
    if (!_editing) _syncToFirestore();
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

  /// Serializes [_replaceLocalContacts] calls — its clear-then-add-each
  /// sequence isn't atomic, so two independent call paths (the live
  /// listener and [refreshContacts]'s one-shot fetch both apply remote
  /// data) overlapping could otherwise interleave and duplicate entries the
  /// same way two concurrent listener events could before that was fixed
  /// with asyncMap. Chaining onto this Future — rather than a bool guard —
  /// makes sure every call still eventually runs against fresh data instead
  /// of being dropped while one is already in flight.
  Future<void> _replaceChain = Future.value();

  /// Replaces the local Hive box content with [remote] contacts.
  Future<void> _replaceLocalContacts(List<Map<String, String>> remote) {
    final next = _replaceChain.then((_) async {
      await _box.clear();
      for (final c in remote) {
        await _box.add(EmergencyContact(
          name:  c['name']  ?? '',
          role:  c['role']  ?? '',
          phone: c['phone'] ?? '',
        ));
      }
      notifyListeners();
    });
    _replaceChain = next;
    return next;
  }

  /// Replaces all local contacts with [parsed] (from a parsed backup
  /// archive) and pushes the restored list to Firestore. Clears the box
  /// itself first (safe even if the caller — e.g. a full-replace restore —
  /// already called [clearLocalData]), so this also works standalone as an
  /// "update" mode opt-in ("sync emergency contacts from backup") without
  /// needing the caller to wipe anything else first.
  Future<void> restoreContacts(List<EmergencyContact> parsed) async {
    await _box.clear();
    for (final c in parsed) { await _box.add(c); }
    _markModified();
    _syncToFirestore();
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
