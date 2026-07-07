import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../app/route_names.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/l10n_extension.dart';
import '../../settings/domain/theme_provider.dart';
import '../data/home_repository.dart';
import '../domain/track_point.dart';
import '../utils/gpx_date_resolver.dart';
import '../utils/gpx_parser.dart';

class GpxImportScreen extends StatefulWidget {
  final String filePath;
  const GpxImportScreen({super.key, required this.filePath});

  @override
  State<GpxImportScreen> createState() => _GpxImportScreenState();
}

enum _Phase { loading, error, ready }

class _GpxImportScreenState extends State<GpxImportScreen> {
  _Phase _phase = _Phase.loading;
  GpxParseResult? _result;
  GpxDateResolution? _resolution;
  Uint8List? _bytes;
  DateTime? _selectedDate;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  Future<void> _parse() async {
    final Uint8List bytes;
    try {
      bytes = await File(widget.filePath).readAsBytes();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _result = const GpxParseResult(
            points: [], error: GpxParseError.invalidEncoding);
      });
      return;
    }

    final result = GpxParser().parseBytes(bytes);
    final resolution = GpxDateResolver.resolve(result);

    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _result = result;
      _resolution = resolution;
      if (result.error != null ||
          resolution.hasRoutesOnly ||
          resolution.hasWaypointsOnly) {
        _phase = _Phase.error;
      } else {
        _phase = _Phase.ready;
        _selectedDate = resolution.resolvedDate;
      }
    });
  }

  String get _locale => context.read<ThemeProvider>().localeString;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      useRootNavigator: false,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(
          () => _selectedDate = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _doImport(HomeRepository repo) async {
    final date = _selectedDate;
    if (date == null || _bytes == null) return;
    setState(() => _importing = true);
    repo.addEntry(date);
    final fileName = '${date.toIso8601String().substring(0, 10)}.gpx';
    await repo.importGpxFromBytes(date, _bytes!, fileName);
    if (!mounted) return;
    _finish(date);
  }

  Future<void> _doReplace(HomeRepository repo) async {
    final date = _selectedDate;
    if (date == null || _bytes == null) return;
    setState(() => _importing = true);
    await repo.removeGpx(date);
    repo.addEntry(date);
    final fileName = '${date.toIso8601String().substring(0, 10)}.gpx';
    await repo.importGpxFromBytes(date, _bytes!, fileName);
    if (!mounted) return;
    _finish(date);
  }

  Future<void> _doMerge(HomeRepository repo) async {
    final date = _selectedDate;
    final result = _result;
    if (date == null || result == null) return;
    setState(() => _importing = true);
    final existing = repo.dailyTracks[date]?.points ?? [];
    final merged = _mergePoints(existing, result.points);
    repo.addEntry(date);
    await repo.replaceTrackPoints(date, merged);
    if (!mounted) return;
    _finish(date);
  }

  static List<TrackPoint> _mergePoints(
      List<TrackPoint> a, List<TrackPoint> b) {
    final all = [...a, ...b]..sort((x, y) => x.time.compareTo(y.time));
    final unique = <TrackPoint>[];
    TrackPoint? last;
    for (final p in all) {
      if (last == null ||
          last.lat != p.lat ||
          last.lon != p.lon ||
          last.time != p.time) {
        unique.add(p);
      }
      last = p;
    }
    return unique;
  }

  void _finish(DateTime date) {
    final dateStr = DateFormat('d MMM', _locale).format(date);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.gpxShareImported(dateStr))),
    );
    context.goNamed(AppRoute.dayDetail, pathParameters: {
      'year': '${date.year}',
      'month': '${date.month}',
      'day': '${date.day}',
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.goNamed(AppRoute.home),
        ),
        title: Text(l10n.gpxImportTitle),
      ),
      body: switch (_phase) {
        _Phase.loading => const Center(child: CircularProgressIndicator()),
        _Phase.error   => _buildError(l10n),
        _Phase.ready   => _buildReady(l10n),
      },
    );
  }

  // ── Error ───────────────────────────────────────────────────────────────────

  Widget _buildError(AppLocalizations l10n) {
    final result = _result;
    final String msg;
    if (result == null || result.error == GpxParseError.invalidEncoding) {
      msg = l10n.gpxShareErrorEncoding;
    } else if (result.error == GpxParseError.invalidXml) {
      msg = l10n.gpxShareErrorInvalidXml;
    } else if (result.hasRoutesOnly) {
      msg = l10n.gpxShareErrorRoutesOnly;
    } else if (result.hasWaypointsOnly) {
      msg = l10n.gpxShareErrorWaypointsOnly;
    } else {
      msg = l10n.gpxShareErrorEmpty;
    }
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 56, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(msg,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => context.goNamed(AppRoute.home),
                child: Text(l10n.close),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Ready ───────────────────────────────────────────────────────────────────

  Widget _buildReady(AppLocalizations l10n) {
    final result = _result!;
    final resolution = _resolution!;
    final locale = _locale;
    final repo = context.watch<HomeRepository>();
    final selectedDate = _selectedDate;
    final existing =
        selectedDate != null ? repo.dailyTracks[selectedDate] : null;
    final entryExists = selectedDate != null &&
        repo.entries.any((e) => e.date == selectedDate);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── File summary card ────────────────────────────────────────────
            _SummaryCard(
              fileName: widget.filePath.split('/').last,
              result: result,
              resolution: resolution,
              locale: locale,
            ),

            const SizedBox(height: 20),

            // ── Context notices (only when relevant) ─────────────────────────
            if (resolution.isMultiDay) ...[
              _Notice(
                icon: Icons.calendar_month_outlined,
                text: l10n.gpxShareMultiDay(
                  resolution.spannedDays.length,
                  DateFormat('d MMM', locale)
                      .format(resolution.spannedDays.first),
                  DateFormat('d MMM', locale)
                      .format(resolution.spannedDays.last),
                ),
              ),
              const SizedBox(height: 16),
            ] else if (resolution.hasPointsWithoutTimestamps) ...[
              _Notice(
                icon: Icons.schedule_outlined,
                text: l10n.gpxShareNoTimestamps,
              ),
              const SizedBox(height: 16),
            ],

            // ── Date assignment ──────────────────────────────────────────────
            Text(l10n.gpxImportAssignDay, style: tt.labelLarge),
            const SizedBox(height: 6),
            _DateTile(
              date: selectedDate,
              locale: locale,
              onTap: _pickDate,
            ),

            // New-entry notice — only if this date has no existing entry
            if (selectedDate != null && !entryExists) ...[
              const SizedBox(height: 8),
              _Notice(
                icon: Icons.add_circle_outline,
                text: l10n.gpxImportNewEntry,
                small: true,
              ),
            ],

            // Date-mismatch warning — only when the GPX has a known date and
            // the user has manually picked a different one
            if (selectedDate != null &&
                resolution.resolvedDate != null &&
                selectedDate != resolution.resolvedDate) ...[
              const SizedBox(height: 8),
              _Notice(
                icon: Icons.warning_amber_outlined,
                text: l10n.gpxImportDateMismatch(
                  DateFormat('d MMM yyyy', locale)
                      .format(resolution.resolvedDate!),
                ),
                small: true,
                isWarning: true,
              ),
            ],

            const SizedBox(height: 24),

            // ── Conflict: Replace / Merge ─────────────────────────────────
            if (existing != null) ...[
              Text(l10n.gpxImportConflict, style: tt.labelLarge),
              const SizedBox(height: 8),
              _TrackInfoRow(
                label: 'New',
                points: result.points,
                cs: cs,
                isIncoming: true,
                locale: locale,
              ),
              const SizedBox(height: 4),
              _TrackInfoRow(
                label: 'Existing',
                points: existing.points,
                cs: cs,
                isIncoming: false,
                locale: locale,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _importing ? null : () => _doReplace(repo),
                      child: Text(l10n.gpxShareActionReplace),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _importing ? null : () => _doMerge(repo),
                      child: Text(l10n.gpxShareActionMerge),
                    ),
                  ),
                ],
              ),
            ] else ...[
              // ── Import button ─────────────────────────────────────────────
              FilledButton(
                onPressed: (selectedDate != null && !_importing)
                    ? () => _doImport(repo)
                    : null,
                child: _importing
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.importLabel),
              ),
            ],

            const SizedBox(height: 12),
            TextButton(
              onPressed: _importing ? null : () => context.goNamed(AppRoute.home),
              child: Text(l10n.cancel),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final String fileName;
  final GpxParseResult result;
  final GpxDateResolution resolution;
  final String locale;

  const _SummaryCard({
    required this.fileName,
    required this.result,
    required this.resolution,
    required this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final pts = result.points;
    final dateFmt = DateFormat('d MMM yyyy', locale);
    final timeFmt = DateFormat('HH:mm', locale);

    final lines = <String>[];
    if (pts.isNotEmpty) {
      lines.add(l10n.gpxImportPoints(pts.length));
      if (!resolution.hasPointsWithoutTimestamps) {
        final start = pts.first.time.toLocal();
        final end = pts.last.time.toLocal();
        if (resolution.isMultiDay) {
          lines.add(
              '${dateFmt.format(start)} – ${dateFmt.format(end)}');
        } else {
          lines.add(
              '${dateFmt.format(start)} · ${timeFmt.format(start)} – ${timeFmt.format(end)}');
        }
      }
    }

    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.route_outlined, color: cs.primary, size: 32),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: tt.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  for (final line in lines) ...[
                    const SizedBox(height: 2),
                    Text(
                      line,
                      style: tt.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool small;
  final bool isWarning;

  const _Notice({
    required this.icon,
    required this.text,
    this.small = false,
    this.isWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = isWarning ? cs.error : cs.secondary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: small ? 16 : 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: (small
                    ? Theme.of(context).textTheme.bodySmall
                    : Theme.of(context).textTheme.bodyMedium)
                ?.copyWith(color: isWarning ? cs.error : cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _DateTile extends StatelessWidget {
  final DateTime? date;
  final String locale;
  final VoidCallback onTap;

  const _DateTile(
      {required this.date, required this.locale, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = DateFormat('d MMM yyyy', locale);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: date == null ? cs.error : cs.outline),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 20,
                color: date == null ? cs.error : cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                date != null ? fmt.format(date!) : '—',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: date == null ? cs.error : null,
                    ),
              ),
            ),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _TrackInfoRow extends StatelessWidget {
  final String label;
  final List<TrackPoint> points;
  final ColorScheme cs;
  final bool isIncoming;
  final String locale;

  const _TrackInfoRow({
    required this.label,
    required this.points,
    required this.cs,
    required this.isIncoming,
    required this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('HH:mm', locale);
    final timeStr = points.isNotEmpty
        ? '${timeFmt.format(points.first.time)} – ${timeFmt.format(points.last.time)}'
        : '—';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isIncoming
            ? cs.primaryContainer.withValues(alpha: 0.4)
            : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            isIncoming ? Icons.upload_outlined : Icons.storage_outlined,
            size: 18,
            color: isIncoming ? cs.primary : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            '$label  ',
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          Text('${points.length} pts',
              style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          Text(timeStr, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
