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

  // ── PdfStrings construction ───────────────────────────────────────────────

  group('PdfStrings', () {
    PdfStrings make() => PdfStrings(
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
          remarksCol:    'Remarks',
          trackMap:      'COURSE & TRACK',
          locale:        'en_US',
          generatedOn:   'GENERATED ON',
          passageTo:     (dest) => 'Passage to $dest',
          departureFrom: (orig) => 'Departure from $orig',
          pageOf:        (p, t) => 'Page $p of $t',
        );

    test('stores scalar fields correctly', () {
      final s = make();
      expect(s.voyageLog,  'VOYAGE LOG');
      expect(s.notes,      'NOTES');
      expect(s.skipper,    'SKIPPER');
      expect(s.locale,     'en_US');
    });

    test('passageTo closure interpolates destination', () {
      expect(make().passageTo('Mallorca'), 'Passage to Mallorca');
    });

    test('departureFrom closure interpolates origin', () {
      expect(make().departureFrom('Barcelona'), 'Departure from Barcelona');
    });

    test('pageOf closure formats page numbers', () {
      expect(make().pageOf(1, 4), 'Page 1 of 4');
      expect(make().pageOf(3, 3), 'Page 3 of 3');
    });
  });
}
