import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../l10n/l10n_extension.dart';
import '../../settings/domain/theme_provider.dart';
import '../data/home_repository.dart';
import '../domain/track_point.dart';
import '../utils/gpx_date_resolver.dart';
import '../utils/gpx_parser.dart';
import 'gpx_import_sheet.dart';

class GpxShareHandler {
  static Future<void> handle({
    required BuildContext context,
    required String filePath,
    required HomeRepository repo,
  }) async {
    // ── 1. Read file ───────────────────────────────────────────────────────────
    final Uint8List bytes;
    try {
      bytes = await File(filePath).readAsBytes();
    } catch (_) {
      if (!context.mounted) return;
      _showErrorSheet(context,
          const GpxParseResult(points: [], error: GpxParseError.invalidEncoding));
      return;
    }

    // ── 2. Parse ───────────────────────────────────────────────────────────────
    final parseResult = GpxParser().parseBytes(bytes);

    // ── 3. Resolve date ────────────────────────────────────────────────────────
    final resolution = GpxDateResolver.resolve(parseResult);

    if (!context.mounted) return;

    // Unrecoverable content errors → show error sheet and stop.
    if (parseResult.error != null ||
        resolution.hasRoutesOnly ||
        resolution.hasWaypointsOnly) {
      _showErrorSheet(context, parseResult);
      return;
    }

    // ── 4. Cases needing the import sheet ─────────────────────────────────────
    DateTime date;

    if (resolution.hasPointsWithoutTimestamps || resolution.resolvedDate == null) {
      // No timestamps — ask the user which day.
      final choice = await showGpxImportSheet(
        context: context,
        parseResult: parseResult,
        resolution: resolution,
        existingTrack: null,
      );
      if (choice == null || !context.mounted) return;
      date = choice.date;
    } else if (resolution.isMultiDay) {
      // Track spans multiple days — ask which day to attach to.
      final existing = repo.dailyTracks[resolution.resolvedDate];
      final choice = await showGpxImportSheet(
        context: context,
        parseResult: parseResult,
        resolution: resolution,
        existingTrack: existing,
      );
      if (choice == null || !context.mounted) return;
      date = choice.date;
      if (choice.action == GpxImportAction.merge) {
        await _doMerge(context, date, parseResult.points, repo, bytes);
        return;
      }
      if (choice.action == GpxImportAction.replace) {
        await repo.removeGpx(date);
      }
    } else {
      date = resolution.resolvedDate!;
      // Single unambiguous day — check for existing track conflict.
      final existing = repo.dailyTracks[date];
      if (existing != null) {
        if (!context.mounted) return;
        final choice = await showGpxImportSheet(
          context: context,
          parseResult: parseResult,
          resolution: resolution,
          existingTrack: existing,
        );
        if (choice == null || !context.mounted) return;
        date = choice.date;
        if (choice.action == GpxImportAction.merge) {
          await _doMerge(context, date, parseResult.points, repo, bytes);
          return;
        }
        if (choice.action == GpxImportAction.replace) {
          await repo.removeGpx(date);
        }
      }
    }

    if (!context.mounted) return;

    // ── 5. Import ──────────────────────────────────────────────────────────────
    repo.addEntry(date); // no-op if the entry already exists
    final fileName = '${date.toIso8601String().substring(0, 10)}.gpx';
    await repo.importGpxFromBytes(date, bytes, fileName);

    if (!context.mounted) return;
    _navigateAndSnack(context, date);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  static Future<void> _doMerge(
    BuildContext context,
    DateTime date,
    List<TrackPoint> incoming,
    HomeRepository repo,
    Uint8List bytes,
  ) async {
    final existingPts = repo.dailyTracks[date]?.points ?? [];
    final merged = _mergePoints(existingPts, incoming);
    repo.addEntry(date);
    await repo.replaceTrackPoints(date, merged);
    if (!context.mounted) return;
    _navigateAndSnack(context, date);
  }

  static List<TrackPoint> _mergePoints(
      List<TrackPoint> existing, List<TrackPoint> incoming) {
    final merged = [...existing, ...incoming];
    merged.sort((a, b) => a.time.compareTo(b.time));
    final unique = <TrackPoint>[];
    TrackPoint? last;
    for (final p in merged) {
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

  static void _showErrorSheet(BuildContext context, GpxParseResult parseResult) {
    showGpxImportSheet(
      context: context,
      parseResult: parseResult,
      resolution: GpxDateResolution(
        resolvedDate: null,
        isMultiDay: false,
        spannedDays: [],
        trackCount: parseResult.sourceTrackCount,
        hasRoutesOnly: parseResult.hasRoutesOnly,
        hasWaypointsOnly: parseResult.hasWaypointsOnly,
      ),
      existingTrack: null,
    );
  }

  static void _navigateAndSnack(BuildContext context, DateTime date) {
    final locale = context.read<ThemeProvider>().localeString;
    final dateStr = DateFormat('d MMM', locale).format(date);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.gpxShareImported(dateStr))),
    );
    context.go('/day/${date.year}/${date.month}/${date.day}');
  }
}
