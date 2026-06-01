import 'package:cloud_firestore/cloud_firestore.dart';

import '../../features/home/domain/day_entry.dart';
import '../../features/home/domain/timeline_entry.dart';

/// Syncs DayEntry objects to/from Firestore.
///
/// Path layout:
///   logbooks/{installationId}/entries/{yyyy-MM-dd}
///
/// GPS tracks (DailyTrack) are kept local-only in Hive because they can be
/// arbitrarily large and are supplementary data.
class FirestoreService {
  final FirebaseFirestore _db;
  final String installationId;

  FirestoreService({required this.installationId})
      : _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _entriesRef => _db
      .collection('logbooks')
      .doc(installationId)
      .collection('entries');

  // ------------------------------------------------------------------
  // Write
  // ------------------------------------------------------------------

  Future<void> saveEntry(DayEntry entry) =>
      _entriesRef.doc(_dateKey(entry.date)).set(_toMap(entry));

  Future<void> deleteEntry(DateTime date) =>
      _entriesRef.doc(_dateKey(date)).delete();

  // ------------------------------------------------------------------
  // Read — only fetches entries absent from the local set so that
  // offline edits are never silently overwritten.
  // ------------------------------------------------------------------

  Future<List<DayEntry>> fetchMissingEntries(Set<DateTime> localDates) async {
    final snapshot = await _entriesRef
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10));

    final result = <DayEntry>[];
    for (final doc in snapshot.docs) {
      final date = DateTime.tryParse(doc.id);
      if (date == null) continue;
      final normalized = DateTime(date.year, date.month, date.day);
      if (localDates.contains(normalized)) continue;
      try {
        result.add(_fromMap(doc.data(), normalized));
      } catch (_) {
        // Skip malformed documents.
      }
    }
    return result;
  }

  // ------------------------------------------------------------------
  // Serialization
  // ------------------------------------------------------------------

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static Map<String, dynamic> _toMap(DayEntry e) => {
        'date': _dateKey(e.date),
        'fromHarbor': e.fromHarbor,
        'toHarbor': e.toHarbor,
        'notes': e.notes,
        'hasGpx': e.hasGpx,
        'distanceNm': e.distanceNm,
        'totalDurationSeconds': e.totalDurationSeconds,
        'movingDurationSeconds': e.movingDurationSeconds,
        'avgSpeedKnots': e.avgSpeedKnots,
        'maxSpeedKnots': e.maxSpeedKnots,
        'participants': e.participants,
        'controlled': e.controlled,
        'participantsList': e.participantsList,
        'checkedItems': e.checkedItems,
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
      };

  static DayEntry _fromMap(Map<String, dynamic> d, DateTime date) => DayEntry(
        date: date,
        fromHarbor: d['fromHarbor'] as String?,
        toHarbor: d['toHarbor'] as String?,
        notes: d['notes'] as String?,
        hasGpx: d['hasGpx'] as bool? ?? false,
        distanceNm: (d['distanceNm'] as num?)?.toDouble() ?? 0.0,
        totalDurationSeconds: d['totalDurationSeconds'] as int? ?? 0,
        movingDurationSeconds: d['movingDurationSeconds'] as int? ?? 0,
        avgSpeedKnots: (d['avgSpeedKnots'] as num?)?.toDouble() ?? 0.0,
        maxSpeedKnots: (d['maxSpeedKnots'] as num?)?.toDouble() ?? 0.0,
        participants: d['participants'] as String?,
        controlled: d['controlled'] as String?,
        participantsList:
            List<String>.from(d['participantsList'] as List? ?? []),
        checkedItems: List<String>.from(d['checkedItems'] as List? ?? []),
        timeline: (d['timeline'] as List? ?? [])
            .map((t) => _timelineFromMap(t as Map<String, dynamic>))
            .toList(),
      );

  static TimelineEntry _timelineFromMap(Map<String, dynamic> d) =>
      TimelineEntry(
        time: DateTime.parse(d['time'] as String),
        course: (d['course'] as num?)?.toDouble(),
        speed: (d['speed'] as num?)?.toDouble(),
        wind: d['wind'] as String?,
        sea: d['sea'] as String?,
        weather: d['weather'] as String?,
        remarks: d['remarks'] as String?,
        grossState: d['grossState'] as String?,
        fockState: d['fockState'] as String?,
        motorOn: d['motorOn'] as bool?,
      );
}
