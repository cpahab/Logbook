import 'package:cloud_firestore/cloud_firestore.dart';

import '../../features/home/domain/crew_member.dart';
import '../../features/home/domain/day_entry.dart';
import '../../features/home/domain/timeline_entry.dart';

/// Syncs DayEntry, settings and emergency contacts to/from Firestore.
///
/// Firestore path layout:
///   logbooks/{installationId}/entries/{yyyy-MM-dd}   — daily journal entries
///   logbooks/{installationId}/meta/settings           — vessel / VHF settings
///   logbooks/{installationId}/meta/contacts           — emergency contacts
///
/// GPS tracks (DailyTrack) are kept local-only in Hive / Firebase Storage
/// because they can be arbitrarily large.
class FirestoreService {
  final FirebaseFirestore _db;
  final String installationId;

  FirestoreService({required this.installationId})
      : _db = FirebaseFirestore.instance;

  // ── Static configuration ───────────────────────────────────────────────────

  /// Call once before Firebase.initializeApp to enable local disk persistence
  /// and an unlimited cache.  This ensures writes made while offline are
  /// retried automatically when connectivity is restored.
  static void configure() {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  // ── Ref helpers ────────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _entriesRef => _db
      .collection('logbooks')
      .doc(installationId)
      .collection('entries');

  DocumentReference<Map<String, dynamic>> _metaDoc(String name) =>
      _db.collection('logbooks').doc(installationId).collection('meta').doc(name);

  // ── Write ──────────────────────────────────────────────────────────────────

  Future<void> saveEntry(DayEntry entry) =>
      _entriesRef.doc(_dateKey(entry.date)).set(_toMap(entry));

  Future<void> deleteEntry(DateTime date) =>
      _entriesRef.doc(_dateKey(date)).delete();

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

  /// Stream of added/modified entries.
  ///
  /// The first emission contains *all* current entries (Firestore always
  /// delivers the full collection state on first subscription).  Subsequent
  /// emissions contain only changed documents — making this suitable for both
  /// initial load and live updates.
  Stream<List<DayEntry>> entryChanges() {
    return _entriesRef.snapshots().map((snap) {
      return _parseDocChanges(
        snap.docChanges
            .where((c) => c.type != DocumentChangeType.removed)
            .toList(),
      );
    }).where((list) => list.isNotEmpty).cast<List<DayEntry>>();
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
      _metaDoc('contacts').snapshots().map((doc) {
        if (!doc.exists) return null;
        final data = doc.data();
        return data == null ? null : _contactsFromDoc(data);
      });

  // ── Meta: vessel settings ──────────────────────────────────────────────────

  Future<void> saveSettings(Map<String, String> settings) =>
      _metaDoc('settings').set({
        ...settings,
        'updatedAt': FieldValue.serverTimestamp(),
      });

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

  Future<void> saveEmergencyContacts(List<Map<String, String>> contacts) =>
      _metaDoc('contacts').set({
        'list': contacts,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<List<Map<String, String>>?> fetchEmergencyContacts() async {
    final doc = await _metaDoc('contacts')
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10));
    if (!doc.exists) return null;
    final data = doc.data();
    return data == null ? null : _contactsFromDoc(data);
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
    return (contacts: _contactsFromDoc(raw), updatedAt: _tsToDate(raw['updatedAt']));
  }

  // ── Serialization ──────────────────────────────────────────────────────────

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static List<DayEntry> _parseDocChanges(
      List<DocumentChange<Map<String, dynamic>>> changes) {
    final result = <DayEntry>[];
    for (final change in changes) {
      final date = DateTime.tryParse(change.doc.id);
      if (date == null) continue;
      final normalized = DateTime(date.year, date.month, date.day);
      final data = change.doc.data();
      if (data == null) continue;
      try {
        result.add(_fromMap(data, normalized));
      } catch (_) {}
    }
    return result;
  }

  static List<DayEntry> _parseDocs(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final result = <DayEntry>[];
    for (final doc in docs) {
      final date = DateTime.tryParse(doc.id);
      if (date == null) continue;
      final normalized = DateTime(date.year, date.month, date.day);
      try {
        result.add(_fromMap(doc.data(), normalized));
      } catch (_) {}
    }
    return result;
  }

  static Map<String, dynamic> _toMap(DayEntry e) => {
        'date': _dateKey(e.date),
        'fromHarbor': e.fromHarbor,
        'toHarbor': e.toHarbor,
        'notes': e.notes,
        'freeText': e.freeText,
        'oilLevel': e.oilLevel,
        'fuelLevel': e.fuelLevel,
        'distanceNm': e.distanceNm,
        'totalDurationSeconds': e.totalDurationSeconds,
        'movingDurationSeconds': e.movingDurationSeconds,
        'avgSpeedKnots': e.avgSpeedKnots,
        'maxSpeedKnots': e.maxSpeedKnots,
        'participantsList': e.participantsList,
        'crew': e.crew.map(_crewToMap).toList(),
        'timeline': e.timeline.map(_timelineToMap).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  static Map<String, dynamic> _timelineToMap(TimelineEntry t) => {
        'time': t.time.toUtc().toIso8601String(),
        'course': t.course,
        'speed': t.speed,
        'wind': t.wind,
        'sea': t.sea,
        'weather': t.weather,
        'remarks': t.remarks,
        'grossState': t.grossState,
        'fockState': t.fockState,
        'motorOn': t.motorOn,
        'vesselStatusNote': t.vesselStatusNote,
      };

  static Map<String, dynamic> _crewToMap(CrewMember c) => {
        'name': c.name,
        'bloodType': c.bloodType,
        'allergies': c.allergies,
        'conditions': c.conditions,
        'remarks': c.remarks,
      };

  static DayEntry _fromMap(Map<String, dynamic> d, DateTime date) => DayEntry(
        date: date,
        fromHarbor: d['fromHarbor'] as String?,
        toHarbor: d['toHarbor'] as String?,
        notes: d['notes'] as String?,
        freeText: d['freeText'] as String?,
        oilLevel: d['oilLevel'] as int?,
        fuelLevel: d['fuelLevel'] as int?,
        distanceNm: (d['distanceNm'] as num?)?.toDouble() ?? 0.0,
        totalDurationSeconds: d['totalDurationSeconds'] as int? ?? 0,
        movingDurationSeconds: d['movingDurationSeconds'] as int? ?? 0,
        avgSpeedKnots: (d['avgSpeedKnots'] as num?)?.toDouble() ?? 0.0,
        maxSpeedKnots: (d['maxSpeedKnots'] as num?)?.toDouble() ?? 0.0,
        participantsList: List<String>.from(d['participantsList'] as List? ?? []),
        crew: (d['crew'] as List? ?? [])
            .map((c) => _crewFromMap(c as Map<String, dynamic>))
            .toList(),
        timeline: (d['timeline'] as List? ?? [])
            .map((t) => _timelineFromMap(t as Map<String, dynamic>))
            .toList(),
      );

  static TimelineEntry _timelineFromMap(Map<String, dynamic> d) => TimelineEntry(
        time: DateTime.parse(d['time'] as String).toLocal(),
        course: (d['course'] as num?)?.toDouble(),
        speed: (d['speed'] as num?)?.toDouble(),
        wind: d['wind'] as String?,
        sea: d['sea'] as String?,
        weather: d['weather'] as String?,
        remarks: d['remarks'] as String?,
        grossState: d['grossState'] as String?,
        fockState: d['fockState'] as String?,
        motorOn: d['motorOn'] as bool?,
        vesselStatusNote: d['vesselStatusNote'] as String?,
      );

  static CrewMember _crewFromMap(Map<String, dynamic> d) => CrewMember(
        name: d['name'] as String? ?? '',
        bloodType: d['bloodType'] as String?,
        allergies: d['allergies'] as String?,
        conditions: d['conditions'] as String?,
        remarks: d['remarks'] as String?,
      );

  // ── Private helpers ────────────────────────────────────────────────────────

  static DateTime? _tsToDate(dynamic v) =>
      v is Timestamp ? v.toDate() : null;

  static Map<String, String> _settingsFromDoc(Map<String, dynamic> data) {
    final result = <String, String>{};
    for (final e in data.entries) {
      if (e.key == 'updatedAt') continue;
      result[e.key] = e.value?.toString() ?? '';
    }
    return result;
  }

  static List<Map<String, String>> _contactsFromDoc(Map<String, dynamic> data) {
    final list = data['list'] as List? ?? [];
    return list
        .map((e) => Map<String, String>.from(
            (e as Map).map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''))))
        .toList();
  }
}
