import 'package:flutter_test/flutter_test.dart';
import 'package:logbook/features/home/utils/pdf_exporter.dart';
import 'package:logbook/features/home/utils/sail_state_utils.dart';

void main() {
  // ── parseVesselStatus ─────────────────────────────────────────────────────

  group('parseVesselStatus', () {
    final labels = (
      oilLabel:       (String pct) => 'Oil: $pct%',
      fuelLabel:      (String pct) => 'Fuel: $pct%',
      keelDownLabel:  'Down',
      keelUpLabel:    'Up',
      keelFieldLabel: 'Keel',
    );

    test('parses oil + fuel sentinel', () {
      expect(
        parseVesselStatus('vs:oil=75,fuel=60',
            oilLabel:       labels.oilLabel,
            fuelLabel:      labels.fuelLabel,
            keelDownLabel:  labels.keelDownLabel,
            keelUpLabel:    labels.keelUpLabel,
            keelFieldLabel: labels.keelFieldLabel),
        'Oil: 75% · Fuel: 60%',
      );
    });

    test('parses keel=down sentinel', () {
      expect(
        parseVesselStatus('vs:keel=down',
            oilLabel:       labels.oilLabel,
            fuelLabel:      labels.fuelLabel,
            keelDownLabel:  labels.keelDownLabel,
            keelUpLabel:    labels.keelUpLabel,
            keelFieldLabel: labels.keelFieldLabel),
        'Keel: Down',
      );
    });

    test('parses keel=up sentinel', () {
      expect(
        parseVesselStatus('vs:keel=up',
            oilLabel:       labels.oilLabel,
            fuelLabel:      labels.fuelLabel,
            keelDownLabel:  labels.keelDownLabel,
            keelUpLabel:    labels.keelUpLabel,
            keelFieldLabel: labels.keelFieldLabel),
        'Keel: Up',
      );
    });

    test('handles partial sentinel with only oil', () {
      expect(
        parseVesselStatus('vs:oil=50',
            oilLabel:       labels.oilLabel,
            fuelLabel:      labels.fuelLabel,
            keelDownLabel:  labels.keelDownLabel,
            keelUpLabel:    labels.keelUpLabel,
            keelFieldLabel: labels.keelFieldLabel),
        'Oil: 50%',
      );
    });

    test('ignores unknown keys gracefully', () {
      expect(
        parseVesselStatus('vs:oil=80,unknown=foo',
            oilLabel:       labels.oilLabel,
            fuelLabel:      labels.fuelLabel,
            keelDownLabel:  labels.keelDownLabel,
            keelUpLabel:    labels.keelUpLabel,
            keelFieldLabel: labels.keelFieldLabel),
        'Oil: 80%',
      );
    });
  });

  // ── isCrewNote / crewNoteDisplay ──────────────────────────────────────────

  group('isCrewNote', () {
    test('true for a crew: sentinel', () {
      expect(isCrewNote('crew:role=0:Alice · Bob'), isTrue);
    });

    test('false for a vs: sentinel', () {
      expect(isCrewNote('vs:oil=75'), isFalse);
    });

    test('false for null', () {
      expect(isCrewNote(null), isFalse);
    });

    test('false for plain text', () {
      expect(isCrewNote('Some remark'), isFalse);
    });
  });

  group('crewNoteDisplay', () {
    test('marks the skipper (role=0) and passes other names through', () {
      expect(
        crewNoteDisplay('crew:role=0:Alice · Bob', 'Crew', 'Skipper'),
        'Crew: Alice (Skipper) · Bob',
      );
    });

    test('handles a single skipper with no other crew', () {
      expect(
        crewNoteDisplay('crew:role=0:Alice', 'Crew', 'Skipper'),
        'Crew: Alice (Skipper)',
      );
    });

    test('handles crew with no role=0 marker', () {
      expect(
        crewNoteDisplay('crew:Alice · Bob', 'Crew', 'Skipper'),
        'Crew: Alice · Bob',
      );
    });
  });

  // ── PdfStrings construction ───────────────────────────────────────────────

  group('PdfStrings', () {
    PdfStrings make() => const PdfStrings(
          voyageLog:     'VOYAGE LOG',
          notes:         'NOTES',
          date:          'DATE',
          distance:      'DISTANCE',
          avgSpeed:      'AVG SPEED',
          avgSpeedUnderway: 'AVG SPEED UNDERWAY',
          max:           'MAX',
          duration:      'UNDERWAY',
          stops:         'STOPS',
          statistics:    'STATISTICS',
          crew:          'CREW',
          skipper:       'SKIPPER',
          crewMember:    'CREW',
          logEntries:    'LOG ENTRIES',
          timeCol:       'Time',
          courseCol:     'Hdg',
          windCol:       'Wind',
          seaCol:        'Sea',
          positionCol:   'Position',
          remarksCol:    'Remarks',
          trackMap:      'COURSE & TRACK',
          locale:        'en_US',
          generatedOn:   'GENERATED ON',
          crewNoteLabel: 'Crew',
          skipperLabel:  'Skipper',
          oilLabel:      'Engine oil',
          fuelLabel:     'Fuel',
          keelLabel:     'Keel',
          keelDownLabel: 'Down',
          keelUpLabel:   'Up',
          passageToTemplate:     'Passage to \u0000',
          departureFromTemplate: 'Departure from \u0000',
          pageOfTemplate:        'Page -1 of -2',
        );

    test('stores scalar fields correctly', () {
      final s = make();
      expect(s.voyageLog,  'VOYAGE LOG');
      expect(s.notes,      'NOTES');
      expect(s.skipper,    'SKIPPER');
      expect(s.locale,     'en_US');
    });

    test('passageToTemplate substitutes the destination placeholder', () {
      expect(make().passageToTemplate.replaceFirst('\u0000', 'Mallorca'),
          'Passage to Mallorca');
    });

    test('departureFromTemplate substitutes the origin placeholder', () {
      expect(make().departureFromTemplate.replaceFirst('\u0000', 'Barcelona'),
          'Departure from Barcelona');
    });

    test('pageOfTemplate substitutes the page/total placeholders', () {
      expect(
          make().pageOfTemplate.replaceFirst('-1', '1').replaceFirst('-2', '4'),
          'Page 1 of 4');
      expect(
          make().pageOfTemplate.replaceFirst('-1', '3').replaceFirst('-2', '3'),
          'Page 3 of 3');
    });
  });
}
