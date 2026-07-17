import '../../../l10n/app_localizations.dart';
import '../domain/timeline_entry.dart';
import '../domain/vessel_equipment.dart';

/// Whether a `TimelineEntry.vesselStatusNote` is a crew-change note
/// (`crew:role=0:Alice · Bob`) rather than a `vs:` vessel-status sentinel.
bool isCrewNote(String? note) => note?.startsWith('crew:') == true;

/// Looks up the recorded state for one configurable equipment [slot] on
/// [t] by its fixed storage key ('slot1' … 'slot12').
String? slotValue(TimelineEntry t, String key) => switch (key) {
  'slot1'  => t.slot1State,
  'slot2'  => t.slot2State,
  'slot3'  => t.slot3State,
  'slot4'  => t.slot4State,
  'slot5'  => t.slot5State,
  'slot6'  => t.slot6State,
  'slot7'  => t.slot7State,
  'slot8'  => t.slot8State,
  'slot9'  => t.slot9State,
  'slot10' => t.slot10State,
  'slot11' => t.slot11State,
  'slot12' => t.slot12State,
  _        => null,
};

/// Builds one display line per active equipment [slot] with a recorded
/// state on [t] ("Label: state").
List<String> equipmentStatusLines(
    TimelineEntry t, List<EquipmentSlot> activeSlots) {
  final lines = <String>[];
  for (final slot in activeSlots) {
    final val = slotValue(t, slot.key);
    if (val != null) lines.add('${slot.label}: $val');
  }
  return lines;
}

/// Renders a `vs:` vessel-status sentinel note into its localised display string.
String vesselStatusDisplay(String note, AppLocalizations l10n) =>
    parseVesselStatus(
      note,
      oilLabel:       (pct) => '${l10n.vesselOilLabel}: $pct%',
      fuelLabel:      (pct) => '${l10n.vesselFuelLabel}: $pct%',
      keelDownLabel:  l10n.vesselKeelDown,
      keelUpLabel:    l10n.vesselKeelUp,
      keelFieldLabel: l10n.entryDialogKeelLabel,
    );

/// Renders a crew note into its display string, stripping the sentinel
/// prefix and prepending the (caller-supplied, l10n-ready) crew label.
/// 'crew:role=0:Alice · Bob' → 'Crew: Alice (Skipper) · Bob'
String crewNoteDisplay(String note, String crewLabel, String skipperLabel) {
  final body = note.substring(5).split(' · ').map((part) {
    if (part.startsWith('role=0:')) return '${part.substring(7)} ($skipperLabel)';
    return part;
  }).join(' · ');
  return '$crewLabel: $body';
}

/// Parses a vessel-status sentinel string (`vs:key=val,...`) into display
/// parts. The caller supplies label functions so this stays l10n-free and
/// fully testable.
String parseVesselStatus(
  String note, {
  required String Function(String percent) oilLabel,
  required String Function(String percent) fuelLabel,
  required String keelDownLabel,
  required String keelUpLabel,
  required String keelFieldLabel,
}) {
  final parts = <String>[];
  for (final kv in note.substring(3).split(',')) {
    final idx = kv.indexOf('=');
    if (idx < 0) continue;
    final key = kv.substring(0, idx);
    final val = kv.substring(idx + 1);
    switch (key) {
      case 'oil':
        parts.add(oilLabel(val));
      case 'fuel':
        parts.add(fuelLabel(val));
      case 'keel':
        parts.add('$keelFieldLabel: ${val == 'down' ? keelDownLabel : keelUpLabel}');
    }
  }
  return parts.join(' · ');
}
