/// Converts a legacy German sail state string to its locale-neutral sentinel.
/// Returns the input unchanged if it already is a sentinel, and null for
/// unrecognised strings.
String? normalizeSailState(String? s) {
  if (s == null) return null;
  if (s.startsWith('sail:')) return s;
  if (s.contains('Voll') || s.contains('voll')) return 'sail:full';
  if (s.contains('1.'))                          return 'sail:reef1';
  if (s.contains('2.'))                          return 'sail:reef2';
  if (s.contains('Niedergeholt'))                return 'sail:lowered';
  if (s.contains('Eingerollt'))                  return 'sail:furled';
  return null;
}

/// Returns the 2-letter PDF abbreviation for a sail state sentinel or legacy
/// German string. Returns '—' for null, empty, or unrecognised input.
String sailStateAbbr(String? s) {
  if (s == null || s.isEmpty) return '—';
  // Sentinel-based (current format)
  if (s == 'sail:full')    return 'VG';
  if (s == 'sail:reef1')   return 'R1';
  if (s == 'sail:reef2')   return 'R2';
  if (s == 'sail:lowered') return 'NR';
  if (s == 'sail:furled')  return 'ER';
  // Legacy German strings
  if (s.contains('Voll'))         return 'VG';
  if (s.contains('1.'))           return 'R1';
  if (s.contains('2.'))           return 'R2';
  if (s.contains('Niedergeholt')) return 'NR';
  if (s.contains('Eingerollt'))   return 'ER';
  return '—';
}

/// Parses a vessel-status sentinel string (`vs:key=val,...`) into display
/// parts. The caller supplies label functions so this stays l10n-free and
/// fully testable.
///
/// Returns the raw [note] unchanged when it doesn't start with `'vs:'`
/// (legacy plain-text notes pass through unmodified).
String parseVesselStatus(
  String note, {
  required String Function(String percent) oilLabel,
  required String Function(String percent) fuelLabel,
  required String keelDownLabel,
  required String keelUpLabel,
  required String keelFieldLabel,
}) {
  if (!note.startsWith('vs:')) return note;
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
