import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../features/home/domain/crew_member.dart';
import '../../features/home/domain/day_entry.dart';
import '../../features/home/domain/timeline_amendment.dart';
import '../../features/home/domain/timeline_entry.dart';
import 'crypto_service.dart';
import 'logbook_key_store.dart';

/// Syncs DayEntry, settings and emergency contacts to/from Firestore.
///
/// Firestore path layout:
///   logbooks/{logbookId}/entries/{yyyy-MM-dd}   — daily journal entries
///   logbooks/{logbookId}/meta/settings           — vessel / VHF settings
///   logbooks/{logbookId}/meta/contacts           — emergency contacts
///
/// GPS tracks (DailyTrack) are kept local-only in Hive / Firebase Storage
/// because they can be arbitrarily large.
///
/// Sensitive free-text fields (DayEntry.notes/freeText/fromHarbor/toHarbor,
/// CrewMember, TimelineEntry/TimelineAmendment's free-text sub-fields,
/// EmergencyContact) are encrypted client-side with AES-256-GCM (see
/// [CryptoService]) before ever reaching Firestore — structured/navigational
/// fields (dates, course, speed, lat/lon, tombstones) stay plaintext, since
/// `updatedAt` in particular must remain a plaintext, queryable server
/// timestamp for [fetchEntriesUpdatedSince] and conflict resolution. The
/// encryption key is a single secret shared directly with every logbook
/// member (see [LogbookKeyStore]/`logbook_service.dart`'s QR-invite flow),
/// not a per-member wrapped key — see CryptoService's doc comment for why.
class FirestoreService {
  final FirebaseFirestore _db;
  final String logbookId;
  final CryptoService _crypto;

  FirestoreService({required this.logbookId, required CryptoService crypto})
      : _db = FirebaseFirestore.instance,
        _crypto = crypto;

  /// Resolves (or creates) [logbookId]'s shared encryption key via
  /// [LogbookKeyStore] and constructs the service — the standard way to get
  /// a [FirestoreService] instance; the raw constructor above exists mainly
  /// for tests that supply their own [CryptoService].
  static Future<FirestoreService> create(String logbookId) async {
    final key = await LogbookKeyStore.getOrCreateKey(logbookId);
    return FirestoreService(logbookId: logbookId, crypto: CryptoService(key));
  }

  // ── Static configuration ───────────────────────────────────────────────────

  /// Call once before Firebase.initializeApp to enable local disk persistence
  /// and an unlimited cache.  This ensures writes made while offline are
  /// retried automatically when connectivity is restored.
  static void configure() {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: 50 * 1024 * 1024, // 50 MB — enough for the full logbook
    );
  }

  // ── Ref helpers ────────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _entriesRef => _db
      .collection('logbooks')
      .doc(logbookId)
      .collection('entries');

  DocumentReference<Map<String, dynamic>> _metaDoc(String name) =>
      _db.collection('logbooks').doc(logbookId).collection('meta').doc(name);

  // ── Write ──────────────────────────────────────────────────────────────────

  /// Saves [entry]. When [changedFields] is null, the whole document is
  /// replaced — appropriate for genuinely new documents or deliberate full
  /// resyncs. When [changedFields] is given, only those keys (plus
  /// createdAt/updatedAt) are written via a merge, so a device holding a
  /// stale copy of *other* fields (e.g. one it hasn't yet pulled from another
  /// device) cannot clobber them with an unrelated edit. Every sensitive
  /// field gets its own independent ciphertext (see [_toMap]), so a partial
  /// merge write only re-encrypts the fields actually being written — it
  /// never needs to touch the ciphertext of unrelated fields.
  Future<void> saveEntry(DayEntry entry, {Set<String>? changedFields}) async {
    final data = await _toMap(entry);
    if (changedFields == null) {
      return _entriesRef.doc(_dateKey(entry.date)).set(data);
    }
    final partial = <String, dynamic>{
      for (final field in changedFields) field: data[field],
      'createdAt': data['createdAt'],
      'updatedAt': data['updatedAt'],
    };
    return _entriesRef
        .doc(_dateKey(entry.date))
        .set(partial, SetOptions(merge: true));
  }

  /// Marks the entry for [date] deleted — a tombstone field write, not a
  /// physical `.delete()`. A real delete is invisible to every sync path
  /// except a live listener that happened to be connected at the exact
  /// moment it occurred: incremental "updated since" queries and one-shot
  /// fetches can only see documents that still exist, so a genuinely
  /// deleted doc simply looks the same as one that was never created —
  /// there is no way to distinguish "gone" from "never existed" once it's
  /// physically removed. Writing `deletedAt` instead makes the deletion
  /// travel through the exact same durable channels a normal edit already
  /// does (this is a plain merge write, so it retries like any other write
  /// if offline). The document itself is kept forever after this — at
  /// personal-logbook scale that's a few dozen bytes per deleted day, which
  /// is judged an acceptable tradeoff over building a server-side cleanup job.
  Future<void> deleteEntry(DateTime date) => _entriesRef.doc(_dateKey(date)).set({
        'deletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  // ── One-shot reads ─────────────────────────────────────────────────────────

  /// Fetches every entry from the server (ignores local Firestore cache).
  Future<List<DayEntry>> fetchAllEntries() async {
    final snap = await _entriesRef
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 15));
    return _parseDocs(snap.docs);
  }

  /// Fetches only entries absent from [localDates].
  Future<List<DayEntry>> fetchMissingEntries(Set<DateTime> localDates) async {
    final snap = await _entriesRef
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 15));
    final filtered = snap.docs.where((d) {
      final date = DateTime.tryParse(d.id);
      if (date == null) return false;
      return !localDates.contains(DateTime(date.year, date.month, date.day));
    }).toList();
    return _parseDocs(filtered);
  }

  /// Fetches entries whose Firestore [updatedAt] server timestamp is strictly
  /// after [since].  Used for incremental startup sync.
  Future<List<DayEntry>> fetchEntriesUpdatedSince(DateTime since) async {
    final snap = await _entriesRef
        .where('updatedAt', isGreaterThan: Timestamp.fromDate(since))
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 15));
    return _parseDocs(snap.docs);
  }

  // ── Real-time streams ──────────────────────────────────────────────────────

  /// Stream of entry changes: upserted (added/modified) and removed entries.
  ///
  /// The first emission contains *all* current entries as upserted (Firestore
  /// always delivers the full collection state on first subscription).
  /// Subsequent emissions include deletions so that date-moves and explicit
  /// deletes propagate to all connected devices.
  Stream<({List<DayEntry> upserted, List<DateTime> removed})> entryChanges() {
    return _entriesRef.snapshots().asyncMap((snap) async {
      final upserted = await _parseDocChanges(
        snap.docChanges
            .where((c) => c.type != DocumentChangeType.removed)
            .toList(),
      );
      final removed = snap.docChanges
          .where((c) => c.type == DocumentChangeType.removed)
          .map((c) => DateTime.tryParse(c.doc.id))
          .whereType<DateTime>()
          .map((d) => DateTime(d.year, d.month, d.day))
          .toList();
      return (upserted: upserted, removed: removed);
    }).where((r) => r.upserted.isNotEmpty || r.removed.isNotEmpty);
  }

  /// Stream of the settings document.  Emits null when the document is absent.
  Stream<Map<String, String>?> settingsChanges() =>
      _metaDoc('settings').snapshots().map((doc) {
        if (!doc.exists) return null;
        final data = doc.data();
        return data == null ? null : _settingsFromDoc(data);
      });

  /// Stream of the contacts document.  Emits null when the document is absent.
  Stream<List<Map<String, String>>?> contactsChanges() =>
      _metaDoc('contacts').snapshots().asyncMap((doc) async {
        if (!doc.exists) return null;
        final data = doc.data();
        return data == null ? null : await _contactsFromDoc(data);
      });

  // ── Meta: vessel settings ──────────────────────────────────────────────────

  /// Overwrites the vessel/VHF settings document with [settings].
  Future<void> saveSettings(Map<String, String> settings) =>
      _metaDoc('settings').set({
        ...settings,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// One-shot fetch of the settings document from the server.
  Future<Map<String, String>?> fetchSettings() async {
    final doc = await _metaDoc('settings')
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10));
    if (!doc.exists) return null;
    final data = doc.data();
    return data == null ? null : _settingsFromDoc(data);
  }

  /// Like [fetchSettings] but also returns the server [updatedAt] timestamp.
  Future<({Map<String, String>? data, DateTime? updatedAt})>
      fetchSettingsWithMeta() async {
    final doc = await _metaDoc('settings')
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10));
    if (!doc.exists) return (data: null, updatedAt: null);
    final raw = doc.data();
    if (raw == null) return (data: null, updatedAt: null);
    return (data: _settingsFromDoc(raw), updatedAt: _tsToDate(raw['updatedAt']));
  }

  // ── Meta: UI state ────────────────────────────────────────────────────────

  /// Saves the dashboard month-expansion map.
  Future<void> saveUiState(Map<String, bool> monthExpanded) =>
      _metaDoc('ui').set({
        'monthExpanded': monthExpanded,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// Real-time stream of UI state.  Emits null when the document is absent.
  Stream<Map<String, bool>?> uiStateChanges() =>
      _metaDoc('ui').snapshots().map((doc) {
        if (!doc.exists) return null;
        final data = doc.data();
        return data == null ? null : _uiStateFromDoc(data);
      });

  /// Fetches UI state together with the server [updatedAt] timestamp.
  Future<({Map<String, bool>? data, DateTime? updatedAt})>
      fetchUiStateWithMeta() async {
    final doc = await _metaDoc('ui')
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10));
    if (!doc.exists) return (data: null, updatedAt: null);
    final raw = doc.data();
    if (raw == null) return (data: null, updatedAt: null);
    return (data: _uiStateFromDoc(raw), updatedAt: _tsToDate(raw['updatedAt']));
  }

  static Map<String, bool> _uiStateFromDoc(Map<String, dynamic> data) {
    final raw = data['monthExpanded'];
    if (raw is! Map) return {};
    return Map<String, bool>.fromEntries(
      raw.entries.map((e) => MapEntry(e.key as String, e.value == true)),
    );
  }

  // ── Meta: emergency contacts ───────────────────────────────────────────────
  // Each contact's fields (name/role/phone) are all sensitive, so the whole
  // {name, role, phone} map is encrypted as one envelope — see
  // CryptoService.encryptJson.

  /// Overwrites the emergency contacts list document with [contacts].
  Future<void> saveEmergencyContacts(List<Map<String, String>> contacts) async =>
      _metaDoc('contacts').set({
        'list': await Future.wait(contacts.map(_crypto.encryptJson)),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// One-shot fetch of the emergency contacts document from the server.
  Future<List<Map<String, String>>?> fetchEmergencyContacts() async {
    final doc = await _metaDoc('contacts')
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10));
    if (!doc.exists) return null;
    final data = doc.data();
    return data == null ? null : await _contactsFromDoc(data);
  }

  /// Like [fetchEmergencyContacts] but also returns the server [updatedAt].
  Future<({List<Map<String, String>>? contacts, DateTime? updatedAt})>
      fetchContactsWithMeta() async {
    final doc = await _metaDoc('contacts')
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10));
    if (!doc.exists) return (contacts: null, updatedAt: null);
    final raw = doc.data();
    if (raw == null) return (contacts: null, updatedAt: null);
    return (
      contacts: await _contactsFromDoc(raw),
      updatedAt: _tsToDate(raw['updatedAt']),
    );
  }

  // ── Meta: crew roster ─────────────────────────────────────────────────────

  /// Overwrites the crew roster document with [members].
  Future<void> saveRoster(List<CrewMember> members) async =>
      _metaDoc('crew_roster').set({
        'members': await Future.wait(members.map(_crewToMap)),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// One-shot fetch of the crew roster from the server. Returns `[]` if no
  /// roster document exists yet.
  Future<List<CrewMember>> fetchRoster() async {
    final doc = await _metaDoc('crew_roster')
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10));
    if (!doc.exists) return [];
    final data = doc.data();
    return data == null ? [] : await _rosterFromDoc(data);
  }

  /// Real-time stream of the crew roster.
  Stream<List<CrewMember>> rosterChanges() =>
      _metaDoc('crew_roster').snapshots().asyncMap((doc) async {
        if (!doc.exists) return <CrewMember>[];
        final data = doc.data();
        return data == null ? <CrewMember>[] : await _rosterFromDoc(data);
      });

  // ── Serialization ──────────────────────────────────────────────────────────
  // Each domain model has a _xToMap/_xFromMap pair below converting it
  // to/from the plain Map Firestore reads and writes. Sensitive sub-objects
  // are instance methods (not static) since they need _crypto; structured/
  // navigational fields that never need encryption stay static where that
  // was already the case.

  /// Firestore document ID for an entry: `yyyy-MM-dd`.
  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<List<DayEntry>> _parseDocChanges(
      List<DocumentChange<Map<String, dynamic>>> changes) async {
    final result = <DayEntry>[];
    for (final change in changes) {
      final date = DateTime.tryParse(change.doc.id);
      if (date == null) continue;
      final normalized = DateTime(date.year, date.month, date.day);
      final data = change.doc.data();
      if (data == null) continue;
      try {
        result.add(await _fromMap(data, normalized));
      } catch (e) {
        if (kDebugMode) debugPrint('FirestoreService: failed to parse doc change: $e');
      }
    }
    return result;
  }

  Future<List<DayEntry>> _parseDocs(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final result = <DayEntry>[];
    for (final doc in docs) {
      final date = DateTime.tryParse(doc.id);
      if (date == null) continue;
      final normalized = DateTime(date.year, date.month, date.day);
      try {
        result.add(await _fromMap(doc.data(), normalized));
      } catch (e) {
        if (kDebugMode) debugPrint('FirestoreService: failed to parse doc ${doc.id}: $e');
      }
    }
    return result;
  }

  /// Encrypts [text] into an envelope, or returns null unchanged — used for
  /// every optional sensitive string field on [DayEntry].
  Future<Map<String, dynamic>?> _encryptOptionalText(String? text) async =>
      text == null ? null : await _crypto.encryptText(text);

  /// Reverses [_encryptOptionalText].
  Future<String?> _decryptOptionalText(dynamic envelope) async =>
      envelope == null ? null : await _crypto.decryptText(envelope as Map<String, dynamic>);

  Future<Map<String, dynamic>> _toMap(DayEntry e) async => {
        'date': _dateKey(e.date),
        'fromHarbor': await _encryptOptionalText(e.fromHarbor),
        'toHarbor': await _encryptOptionalText(e.toHarbor),
        'notes': await _encryptOptionalText(e.notes),
        'freeText': await _encryptOptionalText(e.freeText),
        'oilLevel': e.oilLevel,
        'fuelLevel': e.fuelLevel,
        'crew': await Future.wait(e.crew.map(_crewToMap)),
        'timeline': await Future.wait(e.timeline.map(_timelineToMap)),
        'photos': e.photos,
        'keelDown': e.keelDown,
        'createdAt': e.createdAt?.toUtc().toIso8601String(),
        // Server timestamp, not the client string used elsewhere in this map:
        // fetchEntriesUpdatedSince() below runs a `isGreaterThan Timestamp`
        // query, and Firestore range filters only match fields of the same
        // type as the query value — a client-set ISO string would silently
        // never match and the incremental pull would always come back empty.
        'updatedAt': FieldValue.serverTimestamp(),
        'deletedAt': e.deletedAt?.toUtc().toIso8601String(),
        'trackDeletedAt': e.trackDeletedAt?.toUtc().toIso8601String(),
      };

  /// [TimelineEntry]'s structured/navigational fields (time, course, speed,
  /// temperature, pressure, one-time GPS fix, timestamps) are written
  /// plaintext; its free-text fields (wind/sea/weather/remarks/
  /// vesselStatusNote/12 slot states) are bundled into a single encrypted
  /// `sensitive` envelope — one nonce per timeline entry, not one per string
  /// field, since they're always read/written as a whole unit.
  Future<Map<String, dynamic>> _timelineToMap(TimelineEntry t) async => {
        'time': t.time.toUtc().toIso8601String(),
        'course': t.course,
        'speed': t.speed,
        'createdAt': t.createdAt?.toUtc().toIso8601String(),
        'updatedAt': t.updatedAt?.toUtc().toIso8601String(),
        'amendments': await Future.wait(t.amendments.map(_amendmentToMap)),
        'temperature': t.temperature,
        'pressure': t.pressure,
        'latitude': t.latitude,
        'longitude': t.longitude,
        'sensitive': await _crypto.encryptJson({
          'wind': t.wind,
          'sea': t.sea,
          'weather': t.weather,
          'remarks': t.remarks,
          'vesselStatusNote': t.vesselStatusNote,
          'slot1State': t.slot1State,
          'slot2State': t.slot2State,
          'slot3State': t.slot3State,
          'slot4State': t.slot4State,
          'slot5State': t.slot5State,
          'slot6State': t.slot6State,
          'slot7State': t.slot7State,
          'slot8State': t.slot8State,
          'slot9State': t.slot9State,
          'slot10State': t.slot10State,
          'slot11State': t.slot11State,
          'slot12State': t.slot12State,
        }),
      };

  /// The whole {name, bloodType, allergies, conditions, remarks,
  /// personalEpirb} object is sensitive, so it's encrypted as one envelope;
  /// [CrewMember.id] (a roster-link key, not confidential) stays plaintext
  /// alongside it. Shared by both the day-entry `crew` list and the roster
  /// (`_rosterFromDoc`/`saveRoster`) — identical shape either way.
  Future<Map<String, dynamic>> _crewToMap(CrewMember c) async => {
        'id': c.id,
        'data': await _crypto.encryptJson({
          'name': c.name,
          'bloodType': c.bloodType,
          'allergies': c.allergies,
          'conditions': c.conditions,
          'remarks': c.remarks,
          'personalEpirb': c.personalEpirb,
        }),
      };

  Future<DayEntry> _fromMap(Map<String, dynamic> d, DateTime date) async => DayEntry(
        date: date,
        fromHarbor: await _decryptOptionalText(d['fromHarbor']),
        toHarbor: await _decryptOptionalText(d['toHarbor']),
        notes: await _decryptOptionalText(d['notes']),
        freeText: await _decryptOptionalText(d['freeText']),
        oilLevel: d['oilLevel'] as int?,
        fuelLevel: d['fuelLevel'] as int?,
        crew: await Future.wait(
          (d['crew'] as List? ?? []).map((c) => _crewFromMap(c as Map<String, dynamic>)),
        ),
        timeline: await Future.wait(
          (d['timeline'] as List? ?? []).map((t) => _timelineFromMap(t as Map<String, dynamic>)),
        ),
        photos: List<String>.from(d['photos'] as List? ?? []),
        keelDown: d['keelDown'] as bool?,
        createdAt: _tsToDate(d['createdAt']),
        updatedAt: _tsToDate(d['updatedAt']),
        deletedAt: _tsToDate(d['deletedAt']),
        trackDeletedAt: _tsToDate(d['trackDeletedAt']),
      );

  Future<TimelineEntry> _timelineFromMap(Map<String, dynamic> d) async {
    final sensitive = await _crypto.decryptJson(d['sensitive'] as Map<String, dynamic>);
    return TimelineEntry(
      time: _parseDate(d['time']),
      course: (d['course'] as num?)?.toDouble(),
      speed: (d['speed'] as num?)?.toDouble(),
      wind: sensitive['wind'] as String?,
      sea: sensitive['sea'] as String?,
      weather: sensitive['weather'] as String?,
      remarks: sensitive['remarks'] as String?,
      vesselStatusNote: sensitive['vesselStatusNote'] as String?,
      createdAt: _tsToDate(d['createdAt']),
      updatedAt: _tsToDate(d['updatedAt']),
      amendments: await Future.wait(
        (d['amendments'] as List? ?? []).map((a) => _amendmentFromMap(a as Map<String, dynamic>)),
      ),
      slot1State: sensitive['slot1State'] as String?,
      slot2State: sensitive['slot2State'] as String?,
      slot3State: sensitive['slot3State'] as String?,
      slot4State: sensitive['slot4State'] as String?,
      slot5State: sensitive['slot5State'] as String?,
      slot6State: sensitive['slot6State'] as String?,
      slot7State: sensitive['slot7State'] as String?,
      slot8State: sensitive['slot8State'] as String?,
      slot9State: sensitive['slot9State'] as String?,
      slot10State: sensitive['slot10State'] as String?,
      slot11State: sensitive['slot11State'] as String?,
      slot12State: sensitive['slot12State'] as String?,
      temperature: (d['temperature'] as num?)?.toDouble(),
      pressure: (d['pressure'] as num?)?.toDouble(),
      latitude: (d['latitude'] as num?)?.toDouble(),
      longitude: (d['longitude'] as num?)?.toDouble(),
    );
  }

  /// [TimelineAmendment]'s structured fields (amendedAt, time, course,
  /// speed, temperature, pressure) are written plaintext; its free-text
  /// fields (reason, wind/sea/weather/remarks, 12 slot states) are bundled
  /// into a single encrypted `sensitive` envelope — same rationale as
  /// [_timelineToMap].
  Future<Map<String, dynamic>> _amendmentToMap(TimelineAmendment a) async => {
        'amendedAt': a.amendedAt.toUtc().toIso8601String(),
        'time': a.time.toUtc().toIso8601String(),
        'course': a.course,
        'speed': a.speed,
        'temperature': a.temperature,
        'pressure': a.pressure,
        'sensitive': await _crypto.encryptJson({
          'reason': a.reason,
          'wind': a.wind,
          'sea': a.sea,
          'weather': a.weather,
          'remarks': a.remarks,
          'slot1State': a.slot1State,
          'slot2State': a.slot2State,
          'slot3State': a.slot3State,
          'slot4State': a.slot4State,
          'slot5State': a.slot5State,
          'slot6State': a.slot6State,
          'slot7State': a.slot7State,
          'slot8State': a.slot8State,
          'slot9State': a.slot9State,
          'slot10State': a.slot10State,
          'slot11State': a.slot11State,
          'slot12State': a.slot12State,
        }),
      };

  Future<TimelineAmendment> _amendmentFromMap(Map<String, dynamic> d) async {
    final sensitive = await _crypto.decryptJson(d['sensitive'] as Map<String, dynamic>);
    return TimelineAmendment(
      amendedAt: _parseDate(d['amendedAt']),
      reason: sensitive['reason'] as String?,
      time: _parseDate(d['time']),
      course: (d['course'] as num?)?.toDouble(),
      speed: (d['speed'] as num?)?.toDouble(),
      wind: sensitive['wind'] as String?,
      sea: sensitive['sea'] as String?,
      weather: sensitive['weather'] as String?,
      remarks: sensitive['remarks'] as String?,
      slot1State: sensitive['slot1State'] as String?,
      slot2State: sensitive['slot2State'] as String?,
      slot3State: sensitive['slot3State'] as String?,
      slot4State: sensitive['slot4State'] as String?,
      slot5State: sensitive['slot5State'] as String?,
      slot6State: sensitive['slot6State'] as String?,
      slot7State: sensitive['slot7State'] as String?,
      slot8State: sensitive['slot8State'] as String?,
      slot9State: sensitive['slot9State'] as String?,
      slot10State: sensitive['slot10State'] as String?,
      slot11State: sensitive['slot11State'] as String?,
      slot12State: sensitive['slot12State'] as String?,
      temperature: (d['temperature'] as num?)?.toDouble(),
      pressure: (d['pressure'] as num?)?.toDouble(),
    );
  }

  Future<CrewMember> _crewFromMap(Map<String, dynamic> d) async {
    final data = await _crypto.decryptJson(d['data'] as Map<String, dynamic>);
    return CrewMember(
      name: data['name'] as String? ?? '',
      bloodType: data['bloodType'] as String?,
      allergies: data['allergies'] as String?,
      conditions: data['conditions'] as String?,
      remarks: data['remarks'] as String?,
      personalEpirb: data['personalEpirb'] as String?,
      id: d['id'] as String?,
    );
  }

  // ── Roster serialization ───────────────────────────────────────────────────
  // Reuses _crewToMap/_crewFromMap — a roster member and a day-entry crew
  // member are the same shape.

  Future<List<CrewMember>> _rosterFromDoc(Map<String, dynamic> data) async {
    final list = data['members'] as List? ?? [];
    return Future.wait(list.map((e) => _crewFromMap(e as Map<String, dynamic>)));
  }

  /// Reverses [saveEmergencyContacts]'s per-contact envelope — each decrypted
  /// envelope is a `{name, role, phone}` map, which every entry is coerced
  /// back into `Map<String, String>` for, matching this function's existing
  /// (pre-encryption) return type.
  Future<List<Map<String, String>>> _contactsFromDoc(Map<String, dynamic> data) async {
    final list = data['list'] as List? ?? [];
    final result = <Map<String, String>>[];
    for (final e in list) {
      final decrypted = await _crypto.decryptJson(e as Map<String, dynamic>);
      result.add(decrypted.map((k, v) => MapEntry(k, v?.toString() ?? '')));
    }
    return result;
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  static DateTime? _tsToDate(dynamic v) {
    if (v is Timestamp) return v.toDate().toLocal();
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    return null;
  }

  /// Like [_tsToDate] but for required (non-nullable) date fields — throws
  /// if the value is missing or unparseable.
  static DateTime _parseDate(dynamic v) =>
      _tsToDate(v) ?? (throw FormatException('Cannot parse date: $v'));

  static Map<String, String> _settingsFromDoc(Map<String, dynamic> data) {
    final result = <String, String>{};
    for (final e in data.entries) {
      if (e.key == 'updatedAt') continue;
      result[e.key] = e.value?.toString() ?? '';
    }
    return result;
  }
}
