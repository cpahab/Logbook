/// Whether a `TimelineEntry.vesselStatusNote` is a crew-change note
/// (`crew:role=0:Alice · Bob`) rather than a `vs:` vessel-status sentinel.
bool isCrewNote(String? note) => note?.startsWith('crew:') == true;

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
