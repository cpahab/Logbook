import 'package:flutter_test/flutter_test.dart';
import 'package:logbook/core/services/backup_mapper.dart';
import 'package:logbook/features/emergency/domain/emergency_contact.dart';
import 'package:logbook/features/home/domain/crew_member.dart';
import 'package:logbook/features/home/domain/daily_track.dart';
import 'package:logbook/features/home/domain/day_entry.dart';
import 'package:logbook/features/home/domain/timeline_amendment.dart';
import 'package:logbook/features/home/domain/timeline_entry.dart';
import 'package:logbook/features/home/domain/track_point.dart';

void main() {
  group('trackPoint', () {
    test('round-trips through JSON', () {
      final p = TrackPoint(lat: 46.2, lon: 6.15, time: DateTime.utc(2026, 7, 11, 14, 30));
      final round = trackPointFromJson(trackPointToJson(p));
      expect(round.lat, p.lat);
      expect(round.lon, p.lon);
      expect(round.time, p.time);
    });
  });

  group('timelineAmendment', () {
    test('round-trips with every field populated', () {
      final a = TimelineAmendment(
        amendedAt: DateTime.utc(2026, 7, 11, 9),
        reason: 'Wind corrected',
        time: DateTime.utc(2026, 7, 11, 8, 45),
        course: 180.0,
        speed: 5.5,
        wind: 'SW 12kt',
        sea: 'Moderate',
        weather: 'Sunny',
        remarks: 'All good',
        slot1State: 'Full',
        slot12State: 'Down',
        temperature: 21.5,
        pressure: 1013.0,
      );
      final round = timelineAmendmentFromJson(timelineAmendmentToJson(a));
      expect(timelineAmendmentToJson(round), timelineAmendmentToJson(a));
    });

    test('fromJson tolerates missing optional keys (older backup)', () {
      final minimal = {
        'amendedAt': DateTime.utc(2026, 7, 11).toIso8601String(),
        'time': DateTime.utc(2026, 7, 11).toIso8601String(),
      };
      final a = timelineAmendmentFromJson(minimal);
      expect(a.reason, isNull);
      expect(a.course, isNull);
      expect(a.temperature, isNull);
    });
  });

  group('timelineEntry', () {
    test('round-trips with nested amendments', () {
      final t = TimelineEntry(
        time: DateTime.utc(2026, 7, 11, 10),
        course: 90.0,
        speed: 6.2,
        wind: 'N 8kt',
        remarks: 'Departure',
        slot1State: 'Reefed',
        slot11State: 'Off',
        temperature: 19.0,
        amendments: [
          TimelineAmendment(
            amendedAt: DateTime.utc(2026, 7, 11, 11),
            time: DateTime.utc(2026, 7, 11, 10),
            course: 85.0,
          ),
        ],
      );
      final round = timelineEntryFromJson(timelineEntryToJson(t));
      expect(timelineEntryToJson(round), timelineEntryToJson(t));
    });

    test('fromJson tolerates a missing amendments key', () {
      final minimal = {'time': DateTime.utc(2026, 7, 11).toIso8601String()};
      final t = timelineEntryFromJson(minimal);
      expect(t.amendments, isEmpty);
    });
  });

  group('crewMember', () {
    test('round-trips through JSON', () {
      final c = CrewMember(
        name: 'Skipper',
        bloodType: 'O+',
        allergies: 'None',
        id: 'abc123',
        personalEpirb: 'EPIRB-1',
      );
      final round = crewMemberFromJson(crewMemberToJson(c));
      expect(round.name, c.name);
      expect(round.bloodType, c.bloodType);
      expect(round.id, c.id);
      expect(round.personalEpirb, c.personalEpirb);
    });
  });

  group('emergencyContact', () {
    test('round-trips through JSON', () {
      final c = EmergencyContact(name: 'Jane', role: 'Wife', phone: '+41 79 000 00 00');
      final round = emergencyContactFromJson(emergencyContactToJson(c));
      expect(round.name, c.name);
      expect(round.role, c.role);
      expect(round.phone, c.phone);
    });
  });

  group('dayEntry', () {
    test('round-trips with a track', () {
      final date = DateTime(2026, 7, 11);
      final entry = DayEntry(
        date: date,
        fromHarbor: 'Rapperswil',
        toHarbor: 'Zürich',
        distanceNm: 12.4,
        avgSpeedKnots: 5.1,
        photos: ['logbooks/x/photos/2026-07-11/1.jpg'],
        crew: [CrewMember(name: 'Skipper', id: 'c1')],
        timeline: [TimelineEntry(time: DateTime.utc(2026, 7, 11, 9))],
      );
      final track = DailyTrack(
        day: date,
        fileName: '2026-07-11.gpx',
        points: [TrackPoint(lat: 47.2, lon: 8.8, time: DateTime.utc(2026, 7, 11, 9))],
      );

      final parsed = dayEntryFromJson(dayEntryToJson(entry, track: track));

      expect(parsed.entry.date, date);
      expect(parsed.entry.fromHarbor, entry.fromHarbor);
      expect(parsed.entry.distanceNm, entry.distanceNm);
      expect(parsed.entry.photos, entry.photos);
      expect(parsed.entry.crew.single.name, 'Skipper');
      expect(parsed.entry.timeline, hasLength(1));
      expect(parsed.track, isNotNull);
      expect(parsed.track!.fileName, track.fileName);
      expect(parsed.track!.points.single.lat, 47.2);
    });

    test('round-trips without a track', () {
      final entry = DayEntry(date: DateTime(2026, 7, 12));
      final parsed = dayEntryFromJson(dayEntryToJson(entry));
      expect(parsed.track, isNull);
    });
  });
}
