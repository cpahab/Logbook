import '../../../l10n/app_localizations.dart';
import '../data/home_repository.dart';
import '../domain/timeline_entry.dart';
import 'sail_state_utils.dart';

/// One-time, debug-only migration: converts the legacy grossState/fockState/
/// motorOn/keelDown fields on every [TimelineEntry] into the new
/// slot1State/slot2State/slot11State/slot12State plain-text fields, using
/// the same sentinel-to-text conversion the dialog's legacy fallback already
/// applies at display time.
///
/// An entry is touched only if it has a legacy value AND the corresponding
/// new slot field is still null, so running this more than once is a no-op
/// for anything already migrated — safe to re-run if it's interrupted.
///
/// Temporary: delete this file, its Settings trigger, and the legacy
/// fallback branches in the dialog/day-detail/PDF-exporter code once every
/// device has run this and confirmed the result.
int migrateLegacyEquipmentFields(HomeRepository repo, AppLocalizations l10n) {
  var migratedCount = 0;
  for (final day in repo.entries) {
    var dayChanged = false;
    for (final t in day.timeline) {
      var entryChanged = false;

      final legacyGross = normalizeSailState(t.grossState);
      if (t.slot1State == null && legacyGross != null) {
        t.slot1State = _legacySailLabel(legacyGross, l10n);
        entryChanged = true;
      }
      final legacyFock = normalizeSailState(t.fockState);
      if (t.slot2State == null && legacyFock != null) {
        t.slot2State = _legacySailLabel(legacyFock, l10n);
        entryChanged = true;
      }
      if (t.slot11State == null && t.motorOn != null) {
        t.slot11State = t.motorOn! ? l10n.on : l10n.off;
        entryChanged = true;
      }
      if (t.slot12State == null && t.keelDown != null) {
        t.slot12State = t.keelDown! ? l10n.vesselKeelDown : l10n.vesselKeelUp;
        entryChanged = true;
      }

      if (entryChanged) {
        migratedCount++;
        dayChanged = true;
      }
    }
    if (dayChanged) {
      repo.saveEntry(day, changedFields: {'timeline'});
    }
  }
  return migratedCount;
}

/// Mirrors the dialog's private `_sailLabel` sentinel-to-text mapping —
/// duplicated here rather than shared, since this whole file is meant to be
/// deleted once migration is confirmed complete.
String _legacySailLabel(String sentinel, AppLocalizations l10n) => switch (sentinel) {
  'sail:full'    => l10n.sailFull,
  'sail:reef1'   => l10n.sailReef1,
  'sail:reef2'   => l10n.sailReef2,
  'sail:lowered' => l10n.sailLowered,
  'sail:furled'  => l10n.sailFurled,
  _              => sentinel,
};
