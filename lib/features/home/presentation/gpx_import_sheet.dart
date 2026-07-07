import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/theme_extensions.dart';
import '../../../l10n/l10n_extension.dart';
import '../../settings/domain/theme_provider.dart';
import '../domain/daily_track.dart';
import '../utils/gpx_date_resolver.dart';
import '../utils/gpx_parser.dart';

enum GpxImportState {
  error,
  multiDay,
  noTimestamps,
  conflict,
}

enum GpxErrorKind {
  invalidEncoding,
  invalidXml,
  hasRoutesOnly,
  hasWaypointsOnly,
  noSupportedContent,
}

/// Result returned from [showGpxImportSheet].
class GpxImportChoice {
  final DateTime date;
  final GpxImportAction action;
  const GpxImportChoice({required this.date, required this.action});
}

enum GpxImportAction { replace, merge, clear }

/// Shows the GPX import decision bottom sheet and returns the user's choice,
/// or null if the user cancelled or the file has an unrecoverable error.
Future<GpxImportChoice?> showGpxImportSheet({
  required BuildContext context,
  required GpxParseResult parseResult,
  required GpxDateResolution resolution,
  /// Existing track for the resolved date, if any.
  DailyTrack? existingTrack,
}) {
  return showModalBottomSheet<GpxImportChoice>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _GpxImportSheet(
      parseResult: parseResult,
      resolution: resolution,
      existingTrack: existingTrack,
    ),
  );
}

class _GpxImportSheet extends StatefulWidget {
  final GpxParseResult parseResult;
  final GpxDateResolution resolution;
  final DailyTrack? existingTrack;

  const _GpxImportSheet({
    required this.parseResult,
    required this.resolution,
    required this.existingTrack,
  });

  @override
  State<_GpxImportSheet> createState() => _GpxImportSheetState();
}

class _GpxImportSheetState extends State<_GpxImportSheet> {
  late DateTime _selectedDate;
  DailyTrack? _currentExisting;
  bool _datePicked = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.resolution.resolvedDate ?? DateTime.now();
    _selectedDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    _currentExisting = widget.existingTrack;
  }

  GpxImportState get _state {
    final r = widget.resolution;
    if (r.hasRoutesOnly || r.hasWaypointsOnly ||
        widget.parseResult.error != null) {
      return GpxImportState.error;
    }
    if (r.hasPointsWithoutTimestamps) return GpxImportState.noTimestamps;
    if (r.isMultiDay && !_datePicked) return GpxImportState.multiDay;
    if (_currentExisting != null) return GpxImportState.conflict;
    return GpxImportState.error; // should not reach here — caller skips sheet for clear
  }

  GpxErrorKind get _errorKind {
    if (widget.resolution.hasRoutesOnly) return GpxErrorKind.hasRoutesOnly;
    if (widget.resolution.hasWaypointsOnly) return GpxErrorKind.hasWaypointsOnly;
    switch (widget.parseResult.error) {
      case GpxParseError.invalidEncoding: return GpxErrorKind.invalidEncoding;
      case GpxParseError.invalidXml:      return GpxErrorKind.invalidXml;
      case GpxParseError.noSupportedContent:
      case null: return GpxErrorKind.noSupportedContent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24, 16, 24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: switch (_state) {
        GpxImportState.error      => _buildError(cs),
        GpxImportState.multiDay   => _buildMultiDay(cs),
        GpxImportState.noTimestamps => _buildNoTimestamps(cs),
        GpxImportState.conflict   => _buildConflict(cs),
      },
    );
  }

  Widget _buildHandle() => Center(
    child: Container(
      width: 36, height: 4,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );

  Widget _buildError(ColorScheme cs) {
    final l10n = context.l10n;
    final msg = switch (_errorKind) {
      GpxErrorKind.invalidEncoding    => l10n.gpxShareErrorEncoding,
      GpxErrorKind.invalidXml         => l10n.gpxShareErrorInvalidXml,
      GpxErrorKind.hasRoutesOnly      => l10n.gpxShareErrorRoutesOnly,
      GpxErrorKind.hasWaypointsOnly   => l10n.gpxShareErrorWaypointsOnly,
      GpxErrorKind.noSupportedContent => l10n.gpxShareErrorEmpty,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHandle(),
        Icon(Icons.error_outline, size: 40, color: cs.error),
        const SizedBox(height: 12),
        Text(msg, style: Theme.of(context).textTheme.fieldHintCompact.copyWith(color: cs.onSurface)),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.close),
          ),
        ),
      ],
    );
  }

  Widget _buildMultiDay(ColorScheme cs) {
    final l10n = context.l10n;
    final locale = context.read<ThemeProvider>().localeString;
    final days = widget.resolution.spannedDays;
    final fmt = DateFormat('d MMM yyyy', locale);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHandle(),
        Text(
          l10n.gpxShareMultiDay(
            days.length,
            fmt.format(days.first),
            fmt.format(days.last),
          ),
          style: Theme.of(context).textTheme.fieldHintCompact.copyWith(color: cs.onSurface),
        ),
        if (widget.resolution.trackCount > 1) ...[
          const SizedBox(height: 8),
          Text(
            l10n.gpxShareMergedNote(widget.resolution.trackCount),
            style: Theme.of(context).textTheme.bodySmall!.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 16),
        _DatePickerRow(
          selected: _selectedDate,
          locale: locale,
          onChanged: (d) => setState(() {
            _selectedDate = d;
            _datePicked = true;
          }),
        ),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(
                GpxImportChoice(date: _selectedDate, action: GpxImportAction.clear),
              ),
              child: Text(l10n.importLabel),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _buildNoTimestamps(ColorScheme cs) {
    final l10n = context.l10n;
    final locale = context.read<ThemeProvider>().localeString;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHandle(),
        Text(
          l10n.gpxShareNoTimestamps,
          style: Theme.of(context).textTheme.fieldHintCompact.copyWith(color: cs.onSurface),
        ),
        const SizedBox(height: 16),
        _DatePickerRow(
          selected: _selectedDate,
          locale: locale,
          onChanged: (d) => setState(() => _selectedDate = d),
        ),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(
                GpxImportChoice(date: _selectedDate, action: GpxImportAction.clear),
              ),
              child: Text(l10n.importLabel),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _buildConflict(ColorScheme cs) {
    final l10n = context.l10n;
    final locale = context.read<ThemeProvider>().localeString;
    final incoming = widget.parseResult.points;
    final existing = _currentExisting!.points;
    final fmt = DateFormat('d MMM yyyy', locale);
    final timeFmt = DateFormat('HH:mm', locale);

    String incomingLine() {
      if (incoming.isEmpty) return l10n.gpxShareConflictIncoming('—', 0, '—', '—');
      return l10n.gpxShareConflictIncoming(
        fmt.format(incoming.first.time.toLocal()),
        incoming.length,
        timeFmt.format(incoming.first.time.toLocal()),
        timeFmt.format(incoming.last.time.toLocal()),
      );
    }

    String existingLine() {
      if (existing.isEmpty) return l10n.gpxShareConflictExisting('—', 0, '—', '—');
      return l10n.gpxShareConflictExisting(
        fmt.format(existing.first.time.toLocal()),
        existing.length,
        timeFmt.format(existing.first.time.toLocal()),
        timeFmt.format(existing.last.time.toLocal()),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHandle(),
        Text(
          incomingLine(),
          style: Theme.of(context).textTheme.bodySmall!.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(
          existingLine(),
          style: Theme.of(context).textTheme.bodySmall!.copyWith(color: cs.onSurfaceVariant),
        ),
        if (widget.resolution.trackCount > 1) ...[
          const SizedBox(height: 8),
          Text(
            l10n.gpxShareMergedNote(widget.resolution.trackCount),
            style: Theme.of(context).textTheme.bodySmall!.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 20),
        _ConflictButton(
          label: l10n.gpxShareActionReplace,
          onTap: () => Navigator.of(context).pop(
            GpxImportChoice(date: _selectedDate, action: GpxImportAction.replace),
          ),
          cs: cs,
        ),
        const SizedBox(height: 8),
        _ConflictButton(
          label: l10n.gpxShareActionMerge,
          onTap: () => Navigator.of(context).pop(
            GpxImportChoice(date: _selectedDate, action: GpxImportAction.merge),
          ),
          cs: cs,
        ),
        const SizedBox(height: 8),
        _ConflictButton(
          label: l10n.gpxShareActionDifferent,
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _selectedDate,
              firstDate: DateTime(2000),
              lastDate: DateTime.now().add(const Duration(days: 365)),
              locale: context.read<ThemeProvider>().materialLocale,
            );
            if (picked == null || !mounted) return;
            setState(() {
              _selectedDate = DateTime(picked.year, picked.month, picked.day);
              _datePicked = true;
              // Re-check conflict for new date is handled by the handler
              // which will call this sheet again if needed.
              _currentExisting = null;
            });
          },
          cs: cs,
        ),
        const SizedBox(height: 8),
        _ConflictButton(
          label: l10n.cancel,
          onTap: () => Navigator.of(context).pop(),
          cs: cs,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _DatePickerRow extends StatelessWidget {
  final DateTime selected;
  final String locale;
  final ValueChanged<DateTime> onChanged;

  const _DatePickerRow({
    required this.selected,
    required this.locale,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = DateFormat('d MMM yyyy', locale);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: selected,
          firstDate: DateTime(2000),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          locale: context.read<ThemeProvider>().materialLocale,
        );
        if (picked != null) {
          onChanged(DateTime(picked.year, picked.month, picked.day));
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Icon(Icons.calendar_today_outlined, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Text(
            fmt.format(selected),
            style: Theme.of(context).textTheme.fieldHintCompact.copyWith(color: cs.onSurface),
          ),
          const Spacer(),
          Icon(Icons.chevron_right, size: 18, color: cs.outlineVariant),
        ]),
      ),
    );
  }
}

class _ConflictButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final ColorScheme cs;

  const _ConflictButton({
    required this.label,
    required this.onTap,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: OutlinedButton(
      onPressed: onTap,
      child: Text(label),
    ),
  );
}
