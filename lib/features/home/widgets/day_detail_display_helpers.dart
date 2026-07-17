import 'package:flutter/material.dart';

import '../../../app/theme/theme_extensions.dart';
import '../../../l10n/l10n_extension.dart';
import '../domain/crew_member.dart';

Widget buildCrewRow(
  BuildContext context, {
  required CrewMember member,
  required bool isFirst,
  required ColorScheme cs,
  required bool editing,
  required int index,
  VoidCallback? onTap,
}) {
  return Row(
    children: [
      if (editing) ...[
        ReorderableDragStartListener(
          index: index,
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(Icons.drag_handle,
                size: 20, color: cs.outline.withValues(alpha: 0.4)),
          ),
        ),
      ],
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cs.surfaceContainerHigh,
          ),
          child: Icon(Icons.person, color: cs.primary, size: 22),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                member.name,
                style: Theme.of(context).textTheme.fieldValueCompact.copyWith(color: cs.onSurface),
              ),
              Text(
                isFirst ? context.l10n.labelSkipper.toUpperCase() : context.l10n.labelCrewRole.toUpperCase(),
                style: Theme.of(context).textTheme.microLabel.copyWith(letterSpacing: 0.5, color: isFirst ? cs.primary : cs.mutedLabel),
              ),
            ],
          ),
        ),
      ),
      if (editing && onTap != null)
        GestureDetector(
          onTap: onTap,
          child: Icon(Icons.chevron_right, size: 18, color: cs.outlineVariant),
        ),
    ],
  );
}

Widget statCell(BuildContext context, String label, String value, ColorScheme cs) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.microLabel.copyWith(color: cs.mutedLabel),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        style: Theme.of(context).textTheme.fieldValueProse.copyWith(color: cs.primary),
      ),
    ],
  );
}

Widget amendmentSnapshotTile(
  BuildContext context, {
  required String label,
  required String dateStr,
  required String? reason,
  required DateTime time,
  required double? course,
  required double? speed,
  required String? wind,
  required String? sea,
  required String? weather,
  required String? remarks,
  required ColorScheme cs,
  required bool isOriginal,
}) {
  final timeStr =
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  final details = [
    if (course != null) 'COG ${course.toStringAsFixed(0)}°',
    if (speed != null) '${speed.toStringAsFixed(1)} kn',
    ?wind,
    ?sea,
    ?weather,
  ].join(' · ');

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall!.copyWith(
              color: isOriginal ? cs.mutedLabel : cs.secondary,
            ),
          ),
          if (dateStr.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(dateStr,
              style: Theme.of(context).textTheme.bodySmall!.copyWith(fontSize: 11, color: cs.mutedLabel)),
          ],
        ],
      ),
      const SizedBox(height: 4),
      Text(
        timeStr,
        style: Theme.of(context).textTheme.titleLarge!.copyWith(fontSize: 20, fontWeight: FontWeight.w500, color: isOriginal ? cs.mutedLabel : cs.primary),
      ),
      if (details.isNotEmpty) ...[
        const SizedBox(height: 2),
        Text(details,
          style: Theme.of(context).textTheme.bodySmall!.copyWith(color: cs.onSurfaceVariant)),
      ],
      if (remarks?.isNotEmpty == true) ...[
        const SizedBox(height: 2),
        Text(remarks!,
          style: Theme.of(context).textTheme.bodySmall!.copyWith(
            fontStyle: FontStyle.italic, color: cs.onSurface)),
      ],
      if (reason != null) ...[
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            reason,
            style: Theme.of(context).textTheme.bodySmall!.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      ],
    ],
  );
}

Widget vesselStatCell(
    BuildContext context, String label, int? level, IconData icon, ColorScheme cs, Color onCard, {bool isFuel = false}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall!.copyWith(
          color: onCard.withValues(alpha: 0.70),
        ),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Icon(icon, color: onCard.withValues(alpha: 0.75), size: 20),
          const SizedBox(width: 8),
          Text(
            level != null ? '$level%' : '—',
            style: Theme.of(context).textTheme.fieldValueProse.copyWith(color: level != null ? onCard : onCard.withValues(alpha: 0.54)),
          ),
        ],
      ),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Stack(
          children: [
            Container(height: 8, color: onCard.withValues(alpha: 0.20)),
            if (level != null)
              FractionallySizedBox(
                widthFactor: level / 100,
                child: Container(height: 8, color: cs.secondaryFixed),
              ),
          ],
        ),
      ),
      const SizedBox(height: 4),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            context.l10n.vesselEmptyLabel.toUpperCase(),
            style: Theme.of(context).textTheme.microLabel.copyWith(letterSpacing: 0.5, color: onCard.withValues(alpha: 0.50)),
          ),
          Text(
            context.l10n.vesselFullLabel.toUpperCase(),
            style: Theme.of(context).textTheme.microLabel.copyWith(letterSpacing: 0.5, color: onCard.withValues(alpha: 0.50)),
          ),
        ],
      ),
    ],
  );
}

Widget gpxUploadIcon(BuildContext context) {
  return SizedBox(
    width: 26,
    height: 26,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(Icons.file_upload_outlined, size: 22, color: Theme.of(context).colorScheme.onSurface),
        Positioned(
          bottom: -3,
          right: -6,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              'GPX',
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                color: Theme.of(context).colorScheme.onPrimary,
                fontSize: 7,
                height: 1,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Small circular directional-arrow (or fallback icon) badge for the
/// departure/arrival map markers.
Widget trackArrow(Color color, {IconData icon = Icons.arrow_upward}) => Container(
      width: 15,
      height: 15,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white, size: 8),
    );

/// Small pill label (departure/arrival time, dropped-marker timestamp) next
/// to a map marker.
Widget trackLabel(BuildContext context, String text, ColorScheme cs) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall!.copyWith(fontSize: 10, letterSpacing: 0, color: Colors.white),
      ),
    );
