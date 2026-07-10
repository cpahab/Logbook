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
