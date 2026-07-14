import '../../features/emergency/domain/emergency_contact.dart';
import '../../features/home/domain/crew_member.dart';
import '../../features/home/domain/daily_track.dart';
import '../../features/home/domain/day_entry.dart';
import '../../features/home/domain/timeline_amendment.dart';
import '../../features/home/domain/timeline_entry.dart';
import '../../features/home/domain/track_point.dart';

/// JSON (de)serialization for the backup-archive data models, kept separate
/// from Firestore's own `_toMap`/`_fromMap` (firestore_service.dart) since
/// that shape targets Firestore's Timestamp/FieldValue types and omits
/// fields Firestore doesn't sync (e.g. distanceNm) that a full local backup
/// should still preserve. Every `fromJson` reads fields defensively (`as
/// T?` + fallback) so a backup survives new nullable fields being added
/// later, per the MIGRATION INVARIANT convention on the Hive models.

Map<String, dynamic> trackPointToJson(TrackPoint p) => {
      'lat': p.lat,
      'lon': p.lon,
      'time': p.time.toUtc().toIso8601String(),
    };

TrackPoint trackPointFromJson(Map<String, dynamic> d) => TrackPoint(
      lat: (d['lat'] as num).toDouble(),
      lon: (d['lon'] as num).toDouble(),
      time: DateTime.parse(d['time'] as String),
    );

Map<String, dynamic> timelineAmendmentToJson(TimelineAmendment a) => {
      'amendedAt': a.amendedAt.toUtc().toIso8601String(),
      'reason': a.reason,
      'time': a.time.toUtc().toIso8601String(),
      'course': a.course,
      'speed': a.speed,
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
      'temperature': a.temperature,
      'pressure': a.pressure,
    };

TimelineAmendment timelineAmendmentFromJson(Map<String, dynamic> d) =>
    TimelineAmendment(
      amendedAt: DateTime.parse(d['amendedAt'] as String),
      reason: d['reason'] as String?,
      time: DateTime.parse(d['time'] as String),
      course: (d['course'] as num?)?.toDouble(),
      speed: (d['speed'] as num?)?.toDouble(),
      wind: d['wind'] as String?,
      sea: d['sea'] as String?,
      weather: d['weather'] as String?,
      remarks: d['remarks'] as String?,
      slot1State: d['slot1State'] as String?,
      slot2State: d['slot2State'] as String?,
      slot3State: d['slot3State'] as String?,
      slot4State: d['slot4State'] as String?,
      slot5State: d['slot5State'] as String?,
      slot6State: d['slot6State'] as String?,
      slot7State: d['slot7State'] as String?,
      slot8State: d['slot8State'] as String?,
      slot9State: d['slot9State'] as String?,
      slot10State: d['slot10State'] as String?,
      slot11State: d['slot11State'] as String?,
      slot12State: d['slot12State'] as String?,
      temperature: (d['temperature'] as num?)?.toDouble(),
      pressure: (d['pressure'] as num?)?.toDouble(),
    );

Map<String, dynamic> timelineEntryToJson(TimelineEntry t) => {
      'time': t.time.toUtc().toIso8601String(),
      'course': t.course,
      'speed': t.speed,
      'wind': t.wind,
      'sea': t.sea,
      'weather': t.weather,
      'remarks': t.remarks,
      'vesselStatusNote': t.vesselStatusNote,
      'createdAt': t.createdAt?.toUtc().toIso8601String(),
      'updatedAt': t.updatedAt?.toUtc().toIso8601String(),
      'amendments': t.amendments.map(timelineAmendmentToJson).toList(),
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
      'temperature': t.temperature,
      'pressure': t.pressure,
      'latitude': t.latitude,
      'longitude': t.longitude,
    };

TimelineEntry timelineEntryFromJson(Map<String, dynamic> d) => TimelineEntry(
      time: DateTime.parse(d['time'] as String),
      course: (d['course'] as num?)?.toDouble(),
      speed: (d['speed'] as num?)?.toDouble(),
      wind: d['wind'] as String?,
      sea: d['sea'] as String?,
      weather: d['weather'] as String?,
      remarks: d['remarks'] as String?,
      vesselStatusNote: d['vesselStatusNote'] as String?,
      createdAt: d['createdAt'] != null ? DateTime.parse(d['createdAt'] as String) : null,
      updatedAt: d['updatedAt'] != null ? DateTime.parse(d['updatedAt'] as String) : null,
      amendments: (d['amendments'] as List? ?? const [])
          .map((a) => timelineAmendmentFromJson(a as Map<String, dynamic>))
          .toList(),
      slot1State: d['slot1State'] as String?,
      slot2State: d['slot2State'] as String?,
      slot3State: d['slot3State'] as String?,
      slot4State: d['slot4State'] as String?,
      slot5State: d['slot5State'] as String?,
      slot6State: d['slot6State'] as String?,
      slot7State: d['slot7State'] as String?,
      slot8State: d['slot8State'] as String?,
      slot9State: d['slot9State'] as String?,
      slot10State: d['slot10State'] as String?,
      slot11State: d['slot11State'] as String?,
      slot12State: d['slot12State'] as String?,
      temperature: (d['temperature'] as num?)?.toDouble(),
      pressure: (d['pressure'] as num?)?.toDouble(),
      latitude: (d['latitude'] as num?)?.toDouble(),
      longitude: (d['longitude'] as num?)?.toDouble(),
    );

Map<String, dynamic> crewMemberToJson(CrewMember c) => {
      'id': c.id,
      'name': c.name,
      'bloodType': c.bloodType,
      'allergies': c.allergies,
      'conditions': c.conditions,
      'remarks': c.remarks,
      'personalEpirb': c.personalEpirb,
    };

CrewMember crewMemberFromJson(Map<String, dynamic> d) => CrewMember(
      id: d['id'] as String?,
      name: d['name'] as String? ?? '',
      bloodType: d['bloodType'] as String?,
      allergies: d['allergies'] as String?,
      conditions: d['conditions'] as String?,
      remarks: d['remarks'] as String?,
      personalEpirb: d['personalEpirb'] as String?,
    );

Map<String, dynamic> emergencyContactToJson(EmergencyContact c) => {
      'name': c.name,
      'role': c.role,
      'phone': c.phone,
    };

EmergencyContact emergencyContactFromJson(Map<String, dynamic> d) =>
    EmergencyContact(
      name: d['name'] as String? ?? '',
      role: d['role'] as String? ?? '',
      phone: d['phone'] as String? ?? '',
    );

Map<String, dynamic> dayEntryToJson(DayEntry e, {DailyTrack? track}) => {
      'date': e.date.toIso8601String(),
      'fromHarbor': e.fromHarbor,
      'toHarbor': e.toHarbor,
      'notes': e.notes,
      'freeText': e.freeText,
      'oilLevel': e.oilLevel,
      'fuelLevel': e.fuelLevel,
      'keelDown': e.keelDown,
      'distanceNm': e.distanceNm,
      'totalDurationSeconds': e.totalDurationSeconds,
      'movingDurationSeconds': e.movingDurationSeconds,
      'avgSpeedKnots': e.avgSpeedKnots,
      'maxSpeedKnots': e.maxSpeedKnots,
      'photos': e.photos,
      'crew': e.crew.map(crewMemberToJson).toList(),
      'timeline': e.timeline.map(timelineEntryToJson).toList(),
      'createdAt': e.createdAt?.toUtc().toIso8601String(),
      'updatedAt': e.updatedAt?.toUtc().toIso8601String(),
      if (track != null)
        'track': {
          'fileName': track.fileName,
          'points': track.points.map(trackPointToJson).toList(),
        },
    };

/// A parsed day entry plus its optional GPS track, mirroring how [DayEntry]
/// and [DailyTrack] are stored in separate Hive boxes but keyed by the same
/// date.
typedef ParsedDayEntry = ({DayEntry entry, DailyTrack? track});

ParsedDayEntry dayEntryFromJson(Map<String, dynamic> d) {
  final rawDate = DateTime.parse(d['date'] as String);
  final date = DateTime(rawDate.year, rawDate.month, rawDate.day);

  final entry = DayEntry(
    date: date,
    fromHarbor: d['fromHarbor'] as String?,
    toHarbor: d['toHarbor'] as String?,
    notes: d['notes'] as String?,
    freeText: d['freeText'] as String?,
    oilLevel: d['oilLevel'] as int?,
    fuelLevel: d['fuelLevel'] as int?,
    keelDown: d['keelDown'] as bool?,
    distanceNm: (d['distanceNm'] as num?)?.toDouble() ?? 0.0,
    totalDurationSeconds: d['totalDurationSeconds'] as int? ?? 0,
    movingDurationSeconds: d['movingDurationSeconds'] as int? ?? 0,
    avgSpeedKnots: (d['avgSpeedKnots'] as num?)?.toDouble() ?? 0.0,
    maxSpeedKnots: (d['maxSpeedKnots'] as num?)?.toDouble() ?? 0.0,
    photos: List<String>.from(d['photos'] as List? ?? const []),
    crew: (d['crew'] as List? ?? const [])
        .map((c) => crewMemberFromJson(c as Map<String, dynamic>))
        .toList(),
    timeline: (d['timeline'] as List? ?? const [])
        .map((t) => timelineEntryFromJson(t as Map<String, dynamic>))
        .toList(),
    createdAt: d['createdAt'] != null ? DateTime.parse(d['createdAt'] as String) : null,
    updatedAt: d['updatedAt'] != null ? DateTime.parse(d['updatedAt'] as String) : null,
  );

  final trackJson = d['track'] as Map<String, dynamic>?;
  final track = trackJson == null
      ? null
      : DailyTrack(
          day: date,
          fileName: trackJson['fileName'] as String? ??
              '${date.toIso8601String().substring(0, 10)}.gpx',
          points: (trackJson['points'] as List? ?? const [])
              .map((p) => trackPointFromJson(p as Map<String, dynamic>))
              .toList(),
        );

  return (entry: entry, track: track);
}
