import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/timeline_entry.dart';
import '../domain/vessel_equipment.dart';
import '../utils/sail_state_utils.dart';

/// Full timeline entry as a multi-line tooltip string.
String buildEntryTooltip(
    TimelineEntry t, AppLocalizations l10n, List<EquipmentSlot> activeSlots) {
  final buf = StringBuffer(DateFormat('HH:mm').format(t.time.toLocal()));

  final nav = <String>[];
  // Course/speed: strip unit annotation from dialog label (e.g. "Course (°)" → "Course")
  final courseLabel = l10n.entryDialogCourseLabel.split(' ').first;
  final speedLabel  = l10n.entryDialogSpeedLabel.split(' ').first;
  if (t.course != null) nav.add('$courseLabel: ${t.course!.toStringAsFixed(0)}°');
  if (t.speed  != null) nav.add('$speedLabel: ${t.speed!.toStringAsFixed(1)} kn');
  if (nav.isNotEmpty) buf.write('\n${nav.join(' · ')}');

  final cond = <String>[];
  if (t.wind?.isNotEmpty    == true) cond.add('${l10n.entryDialogWindLabel.split(' ').first}: ${t.wind!}');
  if (t.sea?.isNotEmpty     == true) cond.add('${l10n.entryDialogSeaLabel}: ${t.sea!}');
  if (t.weather?.isNotEmpty == true) cond.add('${l10n.entryDialogWeatherLabel}: ${t.weather!}');
  if (t.temperature != null) cond.add('${t.temperature!.toStringAsFixed(1)}°C');
  if (t.pressure != null) cond.add('${t.pressure!.toStringAsFixed(0)} mBar');
  if (cond.isNotEmpty) buf.write('\n${cond.join(' · ')}');

  final sails = equipmentStatusLines(t, activeSlots);
  if (sails.isNotEmpty) buf.write('\n${sails.join(' · ')}');

  if (t.remarks?.isNotEmpty          == true) buf.write('\n${t.remarks}');
  if (t.vesselStatusNote?.isNotEmpty == true) {
    buf.write('\n${isCrewNote(t.vesselStatusNote)
        ? crewNoteDisplay(t.vesselStatusNote!, l10n.dataCrewNote, l10n.labelSkipper)
        : vesselStatusDisplay(t.vesselStatusNote!, l10n)}');
  }

  return buf.toString();
}

/// True on native iOS/Android; false on web and desktop.
/// Used to select tooltip trigger mode: tap on touch, hover+longPress on desktop.
bool get isTouchPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
     defaultTargetPlatform == TargetPlatform.android);

/// Formats a stop duration as "1h 30m" or "45m", for a mid-stop marker tooltip.
String fmtDur(double minutes) {
  final m = minutes.round();
  return m >= 60 ? '${m ~/ 60}h ${m % 60}m' : '${m}m';
}
