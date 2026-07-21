import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart' show DateTimeRange;

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/services/backup_mapper.dart';
import '../../../core/utils/coordinate_format.dart';
import '../domain/crew_member.dart';
import '../domain/day_entry.dart';
import '../domain/timeline_entry.dart';
import '../domain/track_point.dart';
import '../domain/vessel_equipment.dart';
import 'compute_daily_stats.dart';
import 'sail_state_utils.dart';
import 'track_correlation.dart';
import 'trim_track.dart' show TimePrecision;

/// Returns true for codepoints that NotoSans can't render but NotoEmoji can
/// — used to split free-text (which may contain emoji) into runs so each
/// chunk gets the font that actually has glyphs for it.
bool _isEmojiRune(int r) =>
    (r >= 0x2600  && r <= 0x27BF)  ||  // misc symbols + dingbats
    (r >= 0xFE00  && r <= 0xFE0F)  ||  // variation selectors
     r == 0x200D                   ||  // zero-width joiner
    (r >= 0x1F000 && r <= 0x1FFFF);    // supplementary emoji blocks

/// Splits [s] into (chunk, isEmoji) pairs for mixed-font rendering by [_richText].
List<(String, bool)> _splitRuns(String s) {
  final out = <(String, bool)>[];
  final buf = StringBuffer();
  bool? cur;
  for (final r in s.runes) {
    final e = _isEmojiRune(r);
    if (cur != null && e != cur) { out.add((buf.toString(), cur)); buf.clear(); }
    buf.writeCharCode(r);
    cur = e;
  }
  if (buf.isNotEmpty) out.add((buf.toString(), cur ?? false));
  return out;
}

/// Renders [text] with [base] font, switching to [emoji] for any emoji
/// codepoints within it — user-entered notes/remarks may contain emoji that
/// NotoSans has no glyphs for, which would otherwise render as tofu boxes.
pw.Widget _richText(
  String text, {
  required pw.Font base,
  required pw.Font emoji,
  required double size,
  required PdfColor color,
}) {
  final runs = _splitRuns(text);
  if (runs.isEmpty) {
    return pw.Text('', style: pw.TextStyle(font: base, fontSize: size, color: color));
  }
  if (runs.length == 1 && !runs[0].$2) {
    return pw.Text(text, style: pw.TextStyle(font: base, fontSize: size, color: color));
  }
  return pw.RichText(
    text: pw.TextSpan(
      children: [
        for (final (chunk, isEmoji) in runs)
          pw.TextSpan(
            text: chunk,
            style: pw.TextStyle(
              font:     isEmoji ? emoji : base,
              fontSize: size,
              color:    color,
            ),
          ),
      ],
    ),
  );
}

// ── Colour palette (aligned with app theme) ────────────────────────────────────
const _navy  = PdfColor(0.00,  0.141, 0.267);    // #002444 — primary
const _fog   = PdfColor(0.937, 0.929, 0.933);    // #efedee — surface-container
const _rule  = PdfColor(0.761, 0.776, 0.812);    // #c3c6cf — outline-variant
const _steel = PdfColor(0.263, 0.278, 0.306);    // #43474e — on-surface-variant

/// All locale-dependent strings needed by the PDF exporter.
/// Populated from AppLocalizations at the call site (where BuildContext is available).
class PdfStrings {
  final String voyageLog;
  final String notes;
  final String date;
  final String distance;
  final String avgSpeedUnderway;
  final String max;
  final String duration;
  final String statistics;
  final String crew;
  final String skipper;
  final String crewMember;
  final String logEntries;
  final String timeCol;
  final String courseCol;
  final String windCol;
  final String seaCol;
  final String positionCol;
  final String remarksCol;
  final String trackMap;
  final String locale;
  final String generatedOn;

  /// Labels for decoding a timeline entry's auto-generated
  /// `vesselStatusNote` sentinel (see [isCrewNote]/[crewNoteDisplay]/
  /// [parseVesselStatus] in sail_state_utils.dart) into the timeline
  /// table's Remarks column, instead of showing the raw sentinel text.
  final String crewNoteLabel;
  final String skipperLabel;
  final String oilLabel;
  final String fuelLabel;
  final String keelLabel;
  final String keelDownLabel;
  final String keelUpLabel;

  /// Localized "Passage to {destination}" with the destination replaced by
  /// a NUL placeholder (never appears in real text) -- plain data (not a
  /// closure over AppLocalizations) so PdfStrings can cross an isolate
  /// boundary via compute(). Built at the call site with
  /// l10n.pdfPassageTo('\u0000'); substitute the real destination with
  /// replaceFirst('\u0000', destination).
  final String passageToTemplate;

  /// Same trick as [passageToTemplate] for "Departure from {origin}".
  final String departureFromTemplate;

  /// Same trick as [pageOfTemplate] (two sentinel placeholders instead
  /// of one) for "Departure from {origin} at {time}".
  final String departureFromAtTemplate;

  /// Same trick as [passageToTemplate] for "Arrival at {time}".
  final String arrivalAtTemplate;

  /// Same trick as [passageToTemplate] for "Page {page} of {total}", built
  /// with sentinel values l10n.pdfPageOf(-1, -2) (real page/total are
  /// always positive, so -1/-2 can't collide) -- substitute with
  /// replaceFirst('-1', '$page').replaceFirst('-2', '$total').
  final String pageOfTemplate;

  const PdfStrings({
    required this.voyageLog,
    required this.notes,
    required this.date,
    required this.distance,
    required this.avgSpeedUnderway,
    required this.max,
    required this.duration,
    required this.statistics,
    required this.crew,
    required this.skipper,
    required this.crewMember,
    required this.logEntries,
    required this.timeCol,
    required this.courseCol,
    required this.windCol,
    required this.seaCol,
    required this.positionCol,
    required this.remarksCol,
    required this.trackMap,
    required this.locale,
    required this.generatedOn,
    required this.crewNoteLabel,
    required this.skipperLabel,
    required this.oilLabel,
    required this.fuelLabel,
    required this.keelLabel,
    required this.keelDownLabel,
    required this.keelUpLabel,
    required this.passageToTemplate,
    required this.departureFromTemplate,
    required this.departureFromAtTemplate,
    required this.arrivalAtTemplate,
    required this.pageOfTemplate,
  });
}

/// Builds the flat widget list for one day's voyage-report content (header,
/// route, notes, photos, track map + stats, timeline, crew) — shared by both
/// the single-day [buildVoyagePdf] and the multi-day [buildRangeVoyagePdf],
/// which precompute fonts/track images once and loop this per day.
///
/// [showHeader] controls the vessel-name banner + rule at the top of the
/// section: single-day export keeps it (it's the only page), while the
/// multi-day export omits it per day since the cover page already states
/// the vessel once for the whole document.
List<pw.Widget> _buildDaySections({
  required DayEntry entry,
  required DailyStats? stats,
  required String vesselName,
  required PdfStrings strings,
  required VesselEquipmentConfig equipment,
  required pw.Font regular,
  required pw.Font bold,
  required pw.Font italic,
  required pw.Font emojiFont,
  Uint8List? trackImageBytes,
  List<Uint8List> photoBytes = const [],
  bool showHeader = true,
  DateTime? departureTime,
  TimePrecision departurePrecision = TimePrecision.unknown,
  DateTime? arrivalTime,
  TimePrecision arrivalPrecision = TimePrecision.unknown,
}) {
  final sections = <pw.Widget>[];

  // ── Full-width: Vessel header ──────────────────────────────
  if (showHeader) {
    sections.add(_buildHeader(vesselName, bold, emojiFont));
    sections.add(pw.SizedBox(height: 16));
  }

  // ── Full-width: Voyage title + date box ───────────────────
  // Always rendered — the date must show even when there's no route
  // (fromHarbor/toHarbor) to build a title from.
  final from = entry.fromHarbor?.trim() ?? '';
  final to   = entry.toHarbor?.trim()   ?? '';
  sections.add(_buildRoute(from, to, entry.date, bold, regular, italic, emojiFont, strings,
      departureTime: departureTime,
      departurePrecision: departurePrecision,
      arrivalTime: arrivalTime,
      arrivalPrecision: arrivalPrecision));
  sections.add(pw.SizedBox(height: 16));

  final narrative = entry.notes?.trim()    ?? '';
  final freeNote  = entry.freeText?.trim() ?? '';

  // ── Full-width: Narrative (always, avoids overflowing the two-column row)
  if (narrative.isNotEmpty) {
    // Same orphan-header guard as the timeline/crew sections — without it
    // the section label can end up alone at the bottom of a page while the
    // note text flows to the next one.
    sections.add(pw.NewPage(freeSpace: 100));
    sections.add(_buildNotes(strings.voyageLog, narrative, bold, italic, emojiFont));
    sections.add(pw.SizedBox(height: 14));
  }

  // ── Full-width: Photos ─────────────────────────────────────
  if (photoBytes.isNotEmpty) {
    sections.add(_buildPhotos(photoBytes, bold));
    sections.add(pw.SizedBox(height: 14));
  }

  // ── Full-width: Free notes ─────────────────────────────────
  if (freeNote.isNotEmpty) {
    sections.add(pw.NewPage(freeSpace: 100));
    sections.add(_buildNotes(strings.notes, freeNote, bold, italic, emojiFont));
    sections.add(pw.SizedBox(height: 14));
  }

  // ── Row 1: Track map (left) | Stats (right) ──────────────
  if (trackImageBytes != null || stats != null) {
    sections.add(pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 8,
          child: trackImageBytes != null
              ? _buildTrackMap(trackImageBytes, bold, regular, strings)
              : pw.SizedBox(),
        ),
        pw.SizedBox(width: 20),
        pw.Expanded(
          flex: 5,
          child: stats != null
              ? _buildStats(stats, bold, regular, strings)
              : pw.SizedBox(),
        ),
      ],
    ));
    sections.add(pw.SizedBox(height: 16));
  }

  // ── Full-width: Timeline ───────────────────────────────────
  // Its own top-level section (not nested in a Row) so the table can
  // span across pages — a horizontal Row can't split across pages in
  // the pdf package, so a long timeline nested in one would throw.
  if (entry.timeline.isNotEmpty) {
    // Force a page break if less than ~120pt is left — otherwise the pdf
    // package's Column/Table spanning can fit the "LOG ENTRIES" label
    // alone at the bottom of a page while every row flows to the next one.
    sections.add(pw.NewPage(freeSpace: 120));
    sections.add(_buildTimeline(entry.timeline, bold, regular, emojiFont, strings, equipment));
    sections.add(pw.SizedBox(height: 16));
  }

  // ── Full-width: Crew ────────────────────────────────────────
  if (entry.crew.isNotEmpty) {
    // Same orphan-header guard as the timeline section above — without it
    // the "CREW" label can end up alone at the bottom of a page while the
    // whole crew list flows to the next one.
    sections.add(pw.NewPage(freeSpace: 100));
    sections.add(_buildCrew(entry.crew, bold, regular, emojiFont, strings));
  }

  return sections;
}

/// Inputs to [_buildVoyagePdfBytes] — plain, isolate-sendable data only
/// (fonts, decoded images, parsed entries), so the actual pdf-widget layout
/// and byte serialization (the CPU-heavy part) can run via [compute] off
/// the UI isolate.
typedef _VoyagePdfInput = ({
  DayEntry entry,
  DailyStats? stats,
  String vesselName,
  PdfStrings strings,
  VesselEquipmentConfig equipment,
  pw.Font regular,
  pw.Font bold,
  pw.Font italic,
  pw.Font emojiFont,
  Uint8List? trackImageBytes,
  List<Uint8List> photoBytes,
  DateTime? departureTime,
  TimePrecision departurePrecision,
  DateTime? arrivalTime,
  TimePrecision arrivalPrecision,
});

/// Builds the single-day [pw.Document] and serializes it to PDF bytes.
/// Top-level (and taking only plain data) so it can run via [compute] —
/// layout/pagination/text-shaping for a long timeline is real CPU work,
/// and unlike [_renderTrackImage] this part is pure Dart (no `dart:ui`,
/// no platform channels), so it's safe to run off the UI isolate.
Future<Uint8List> _buildVoyagePdfBytes(_VoyagePdfInput input) async {
  // compute() runs this in a fresh isolate, which doesn't share the main
  // isolate's intl locale data (initialized once in main.dart) — DateFormat
  // with a non-default locale (see _buildRoute/_buildTitlePage) throws
  // LocaleDataException without this.
  await initializeDateFormatting(input.strings.locale);

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 44),
      theme: pw.ThemeData.withFont(
          base: input.regular, bold: input.bold, italic: input.italic),
      footer: (ctx) => _footer(ctx, input.regular, input.strings),
      build: (ctx) => _buildDaySections(
        entry:           input.entry,
        stats:           input.stats,
        vesselName:      input.vesselName,
        strings:         input.strings,
        equipment:       input.equipment,
        regular:         input.regular,
        bold:            input.bold,
        italic:          input.italic,
        emojiFont:       input.emojiFont,
        trackImageBytes: input.trackImageBytes,
        photoBytes:      input.photoBytes,
        departureTime:      input.departureTime,
        departurePrecision: input.departurePrecision,
        arrivalTime:        input.arrivalTime,
        arrivalPrecision:   input.arrivalPrecision,
      ),
    ),
  );

  return doc.save();
}

/// Builds and returns the PDF bytes for a single-day voyage report.
///
/// Fonts are downloaded from Google Fonts on first call and cached by the
/// [printing] package — no internet access needed after that.
Future<Uint8List> buildVoyagePdf({
  required DayEntry entry,
  required DailyStats? stats,
  required String vesselName,
  required PdfStrings strings,
  required VesselEquipmentConfig equipment,
  Uint8List? trackImageBytes,
  List<Uint8List> photoBytes = const [],
  DateTime? departureTime,
  TimePrecision departurePrecision = TimePrecision.unknown,
  DateTime? arrivalTime,
  TimePrecision arrivalPrecision = TimePrecision.unknown,
}) async {
  final regular  = await PdfGoogleFonts.notoSansRegular();
  final bold     = await PdfGoogleFonts.notoSansBold();
  final italic   = await PdfGoogleFonts.notoSansItalic();
  final emojiFont = await PdfGoogleFonts.notoEmojiRegular();

  // entry as loaded from HomeRepository is a live HiveObject bound to its
  // Hive box (which holds a StreamController with listener closures) —
  // that can't cross the compute() isolate boundary. Round-tripping through
  // the (already-tested) backup JSON mapper produces a plain, detached copy.
  final detachedEntry = dayEntryFromJson(dayEntryToJson(entry)).entry;

  return compute(_buildVoyagePdfBytes, (
    entry:           detachedEntry,
    stats:           stats,
    vesselName:      vesselName,
    strings:         strings,
    equipment:       equipment,
    regular:         regular,
    bold:            bold,
    italic:          italic,
    emojiFont:       emojiFont,
    trackImageBytes: trackImageBytes,
    photoBytes:      photoBytes,
    departureTime:      departureTime,
    departurePrecision: departurePrecision,
    arrivalTime:        arrivalTime,
    arrivalPrecision:   arrivalPrecision,
  ));
}

/// One day's pre-loaded inputs for [buildRangeVoyagePdf] — mirrors the
/// per-day parameters [buildVoyagePdf] takes, so the caller assembles these
/// the same way it already does for a single-day export, just once per day
/// in the range.
class RangeDayInput {
  final DayEntry entry;
  final DailyStats? stats;
  final Uint8List? trackImageBytes;
  final List<Uint8List> photoBytes;
  final DateTime? departureTime;
  final TimePrecision departurePrecision;
  final DateTime? arrivalTime;
  final TimePrecision arrivalPrecision;

  const RangeDayInput({
    required this.entry,
    required this.stats,
    this.trackImageBytes,
    this.photoBytes = const [],
    this.departureTime,
    this.departurePrecision = TimePrecision.unknown,
    this.arrivalTime,
    this.arrivalPrecision = TimePrecision.unknown,
  });
}

/// Builds and returns the PDF bytes for a multi-day voyage report spanning
/// [range]: a cover page (logbook name, vessel name, date range) followed by
/// each of [days] starting on its own page, in one continuous document so
/// page numbers ("Page X of Y") span the whole thing.
///
/// Inputs to [_buildRangeVoyagePdfBytes] — see [_VoyagePdfInput].
typedef _RangeVoyagePdfInput = ({
  List<RangeDayInput> days,
  String logbookName,
  String vesselName,
  DateTimeRange range,
  PdfStrings strings,
  VesselEquipmentConfig equipment,
  pw.Font regular,
  pw.Font bold,
  pw.Font italic,
  pw.Font emojiFont,
});

/// Builds the multi-day [pw.Document] and serializes it to PDF bytes.
/// Top-level for the same reason as [_buildVoyagePdfBytes] — this is the
/// CPU-heavy pure-Dart part (layout/pagination across every day in the
/// range), safe to run via [compute].
Future<Uint8List> _buildRangeVoyagePdfBytes(_RangeVoyagePdfInput input) async {
  // See _buildVoyagePdfBytes — this isolate needs its own intl locale init.
  await initializeDateFormatting(input.strings.locale);

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 44),
      theme: pw.ThemeData.withFont(
          base: input.regular, bold: input.bold, italic: input.italic),
      footer: (ctx) => _footer(ctx, input.regular, input.strings),
      build: (ctx) {
        final widgets = <pw.Widget>[
          _buildTitlePage(input.logbookName, input.vesselName, input.range,
              input.bold, input.regular, input.italic, input.emojiFont, input.strings),
        ];
        for (int i = 0; i < input.days.length; i++) {
          widgets.add(pw.NewPage());
          widgets.addAll(_buildDaySections(
            entry:           input.days[i].entry,
            stats:           input.days[i].stats,
            vesselName:      input.vesselName,
            strings:         input.strings,
            equipment:       input.equipment,
            regular:         input.regular,
            bold:            input.bold,
            italic:          input.italic,
            emojiFont:       input.emojiFont,
            trackImageBytes: input.days[i].trackImageBytes,
            photoBytes:      input.days[i].photoBytes,
            showHeader:      false,
            departureTime:      input.days[i].departureTime,
            departurePrecision: input.days[i].departurePrecision,
            arrivalTime:        input.days[i].arrivalTime,
            arrivalPrecision:   input.days[i].arrivalPrecision,
          ));
        }
        return widgets;
      },
    ),
  );

  return doc.save();
}

/// [days] must already be sorted ascending by date and pre-filtered to the
/// picked range — this function does no filtering of its own.
Future<Uint8List> buildRangeVoyagePdf({
  required List<RangeDayInput> days,
  required String logbookName,
  required String vesselName,
  required DateTimeRange range,
  required PdfStrings strings,
  required VesselEquipmentConfig equipment,
}) async {
  final regular   = await PdfGoogleFonts.notoSansRegular();
  final bold      = await PdfGoogleFonts.notoSansBold();
  final italic    = await PdfGoogleFonts.notoSansItalic();
  final emojiFont = await PdfGoogleFonts.notoEmojiRegular();

  // Same detachment as buildVoyagePdf — each day's entry is a live,
  // box-attached HiveObject until round-tripped through the JSON mapper.
  final detachedDays = [
    for (final d in days)
      RangeDayInput(
        entry:           dayEntryFromJson(dayEntryToJson(d.entry)).entry,
        stats:           d.stats,
        trackImageBytes: d.trackImageBytes,
        photoBytes:      d.photoBytes,
        departureTime:      d.departureTime,
        departurePrecision: d.departurePrecision,
        arrivalTime:        d.arrivalTime,
        arrivalPrecision:   d.arrivalPrecision,
      ),
  ];

  return compute(_buildRangeVoyagePdfBytes, (
    days:        detachedDays,
    logbookName: logbookName,
    vesselName:  vesselName,
    range:       range,
    strings:     strings,
    equipment:   equipment,
    regular:     regular,
    bold:        bold,
    italic:      italic,
    emojiFont:   emojiFont,
  ));
}

// ── Title page ────────────────────────────────────────────────────────────────

/// A4 content height (page height minus the document's own top/bottom
/// margin) — used to make the cover page fill exactly one page.
/// Cover-page content, vertically nudged toward the middle of the page with
/// generous fixed padding rather than a forced page-filling height — the
/// exact usable height of a [pw.MultiPage] page varies with its footer, so
/// a `Container(height: ...)` sized to the full page can end up taller than
/// what's actually free and never fit, sending the pdf package's pagination
/// into a runaway loop (only guarded by an `assert`, so it's silently
/// unbounded in release builds).
pw.Widget _buildTitlePage(String logbookName, String vesselName, DateTimeRange range,
    pw.Font bold, pw.Font regular, pw.Font italic, pw.Font emoji, PdfStrings strings) {
  final fmt = DateFormat('d. MMM yyyy', strings.locale);
  final rangeStr = '${fmt.format(range.start)} – ${fmt.format(range.end)}';
  final generatedStr =
      '${strings.generatedOn} ${DateFormat('d. MMM yyyy, HH:mm', strings.locale).format(DateTime.now())}';

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.SizedBox(height: 220),
      _richText(
        logbookName.isNotEmpty ? logbookName.toUpperCase() : 'LOGBOOK',
        base: bold, emoji: emoji, size: 34, color: _navy,
      ),
      if (vesselName.isNotEmpty) ...[
        pw.SizedBox(height: 10),
        _richText(vesselName, base: italic, emoji: emoji, size: 20, color: _navy),
      ],
      pw.SizedBox(height: 28),
      pw.Container(width: 120, height: 1.5, color: _navy),
      pw.SizedBox(height: 28),
      pw.Text(rangeStr, style: pw.TextStyle(font: bold, fontSize: 16, color: _steel)),
      pw.SizedBox(height: 60),
      pw.Text(generatedStr, style: pw.TextStyle(font: regular, fontSize: 9, color: _rule)),
    ],
  );
}

// ── Header ────────────────────────────────────────────────────────────────────

pw.Widget _buildHeader(String vesselName, pw.Font bold, pw.Font emoji) {
  final name = vesselName.isNotEmpty ? vesselName.toUpperCase() : 'LOGBUCH';
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _richText(name, base: bold, emoji: emoji, size: 26, color: _navy),
      pw.SizedBox(height: 8),
      pw.Divider(color: _navy, thickness: 1.5),
    ],
  );
}

// ── Route ─────────────────────────────────────────────────────────────────────

pw.Widget _buildRoute(String from, String to, DateTime date,
    pw.Font bold, pw.Font regular, pw.Font italic, pw.Font emoji, PdfStrings strings, {
  DateTime? departureTime,
  TimePrecision departurePrecision = TimePrecision.unknown,
  DateTime? arrivalTime,
  TimePrecision arrivalPrecision = TimePrecision.unknown,
}) {
  final hasFrom  = from.isNotEmpty;
  final hasTo    = to.isNotEmpty;
  final hasRoute = hasFrom || hasTo;

  final dateStr = DateFormat('d. MMM yyyy', strings.locale).format(date);

  final dateColumn = pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: [
      pw.Text(strings.date,
          style: pw.TextStyle(
              font: bold, fontSize: 7, color: _steel, letterSpacing: 1.2)),
      pw.SizedBox(height: 2),
      pw.Text(dateStr,
          style: pw.TextStyle(font: bold, fontSize: 13, color: _navy)),
    ],
  );

  // No route (fromHarbor/toHarbor) recorded for this day — still show the
  // date, just without a title to its left.
  if (!hasRoute) {
    return pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [dateColumn]);
  }

  final title = hasTo
      ? strings.passageToTemplate.replaceFirst('\u0000', to)
      : strings.departureFromTemplate.replaceFirst('\u0000', from);

  // Measured departure/arrival times ("HH:mm", or "~HH:mm" when only
  // estimated from the speed signal rather than bounded by a detected
  // stop) — omitted when there's no measured departure at all (a track
  // already under way at its very start has no real departure in the
  // data) or no track data for the day.
  String? departureTimeStr;
  if (departureTime != null && departurePrecision != TimePrecision.unknown) {
    final t = DateFormat('HH:mm', strings.locale).format(departureTime.toLocal());
    departureTimeStr = departurePrecision == TimePrecision.estimated ? '~$t' : t;
  }
  String? arrivalTimeStr;
  if (arrivalTime != null) {
    final t = DateFormat('HH:mm', strings.locale).format(arrivalTime.toLocal());
    arrivalTimeStr = arrivalPrecision == TimePrecision.estimated ? '~$t' : t;
  }

  // Subtitle under the title, shown only alongside a full "from X to Y"
  // route (matching the previous hasFrom && hasTo condition): "Departure
  // from {from}[ at {time}][. Arrival at {time}.]" — enriched with the
  // measured times when available, falling back to the plain harbor-name
  // sentence otherwise.
  String? subtitle;
  if (hasFrom && hasTo) {
    final departurePart = departureTimeStr != null
        ? strings.departureFromAtTemplate
            .replaceFirst('\u0000', from).replaceFirst('\u0000', departureTimeStr)
        : strings.departureFromTemplate.replaceFirst('\u0000', from);
    subtitle = arrivalTimeStr != null
        ? '$departurePart. ${strings.arrivalAtTemplate.replaceFirst('\u0000', arrivalTimeStr)}.'
        : departurePart;
  }

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _richText(title, base: bold, emoji: emoji, size: 18, color: _navy),
            if (subtitle != null) ...[
              pw.SizedBox(height: 2),
              _richText(subtitle, base: italic, emoji: emoji, size: 10, color: _steel),
            ],
          ],
        ),
      ),
      pw.SizedBox(width: 12),
      dateColumn,
    ],
  );
}

// ── Stats ─────────────────────────────────────────────────────────────────────

pw.Widget _buildStats(DailyStats stats, pw.Font bold, pw.Font regular, PdfStrings strings) {
  String dur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return h > 0 ? '${h}h ${m}min' : '${m}min';
  }

  // Each row pairs two stat cards.
  final rowPairs = [
    (
      (label: strings.distance, value: '${stats.distanceNm.toStringAsFixed(1)} nm'),
      (label: strings.duration, value: dur(stats.movingDuration)),
    ),
    (
      (label: strings.avgSpeedUnderway, value: '${stats.avgMakingWayKn.toStringAsFixed(1)} kn'),
      (label: strings.max,              value: '${stats.maxSpeedKn.toStringAsFixed(1)} kn'),
    ),
  ];

  final rows = <pw.Widget>[];
  for (int i = 0; i < rowPairs.length; i++) {
    if (i > 0) rows.add(pw.SizedBox(height: 6));
    final (left, right) = rowPairs[i];
    rows.add(pw.Row(
      children: [
        pw.Expanded(child: _statCard(left.label, left.value, bold, regular)),
        pw.SizedBox(width: 6),
        pw.Expanded(child: _statCard(right.label, right.value, bold, regular)),
      ],
    ));
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _sectionLabel(strings.statistics, bold),
      pw.SizedBox(height: 6),
      ...rows,
    ],
  );
}

pw.Widget _statCard(String label, String value, pw.Font bold, pw.Font regular) =>
    pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _rule, width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  font: regular, fontSize: 7, color: _steel, letterSpacing: 0.8)),
          pw.SizedBox(height: 3),
          pw.Text(value,
              style: pw.TextStyle(font: bold, fontSize: 14, color: _navy)),
        ],
      ),
    );

// ── Crew ──────────────────────────────────────────────────────────────────────

pw.Widget _buildCrew(List<CrewMember> crew, pw.Font bold, pw.Font regular, pw.Font emoji, PdfStrings strings) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _sectionLabel(strings.crew, bold),
      pw.SizedBox(height: 6),
      for (int i = 0; i < crew.length; i++)
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: _rule, width: 0.5),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _richText(crew[i].name,
                  base: i == 0 ? bold : regular,
                  emoji: emoji, size: 10, color: _steel),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: i == 0
                    ? const pw.BoxDecoration(
                        color: _navy,
                        borderRadius:
                            pw.BorderRadius.all(pw.Radius.circular(2)),
                      )
                    : pw.BoxDecoration(
                        border: pw.Border.all(color: _rule, width: 0.5),
                        borderRadius:
                            const pw.BorderRadius.all(pw.Radius.circular(2)),
                      ),
                child: pw.Text(
                  i == 0 ? strings.skipper : strings.crewMember,
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 7,
                    letterSpacing: 0.8,
                    color: i == 0 ? PdfColors.white : _steel,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

// ── Timeline table ────────────────────────────────────────────────────────────

/// Returns a 2-character uppercase PDF cell abbreviation for a state label.
/// Falls back to '—' for null or empty.
String _slotAbbr(String? state) {
  if (state == null || state.trim().isEmpty) return '—';
  final t = state.trim();
  return t.substring(0, t.length.clamp(0, 2)).toUpperCase();
}

pw.Widget _buildTimeline(List<TimelineEntry> entries, pw.Font bold, pw.Font regular,
    pw.Font emoji, PdfStrings strings, VesselEquipmentConfig equipment) {
  // Detect which optional columns are actually populated so we only render them.
  final hasCourse  = entries.any((e) => e.course  != null);
  final hasSpeed   = entries.any((e) => e.speed   != null);
  final hasWind    = entries.any((e) => e.wind?.isNotEmpty  == true);
  final hasSea     = entries.any((e) => e.sea?.isNotEmpty   == true);
  final hasTemperature = entries.any((e) => e.temperature != null);
  final hasPressure    = entries.any((e) => e.pressure != null);
  final hasPosition = entries.any((e) => e.latitude != null && e.longitude != null);
  final hasRemarks = entries.any((e) =>
      e.remarks?.isNotEmpty == true || e.vesselStatusNote?.isNotEmpty == true);

  final activeSlots = equipment.activeSlots;

  // Build ordered column list so flex widths stay aligned.
  final cols = <({String header, double flex})>[
    (header: strings.timeCol,    flex: 1.0),
    if (hasCourse)  (header: strings.courseCol, flex: 0.8),
    if (hasSpeed)   (header: 'kn',              flex: 0.7),
    if (hasWind)    (header: strings.windCol,   flex: 1.1),
    if (hasSea)     (header: strings.seaCol,    flex: 0.8),
    if (hasTemperature) (header: '°C',   flex: 0.6),
    if (hasPressure)    (header: 'mBar', flex: 0.7),
    for (final slot in activeSlots)
      (header: slot.label.substring(0, slot.label.length.clamp(0, 6)), flex: 0.7),
    if (hasPosition) (header: strings.positionCol, flex: 1.8),
    if (hasRemarks) (header: strings.remarksCol, flex: 2.6),
  ];

  final columnWidths = {
    for (int i = 0; i < cols.length; i++)
      i: pw.FlexColumnWidth(cols[i].flex),
  };

  pw.Widget cell(String text, {bool isHeader = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    child: isHeader
        ? pw.Text(text, style: pw.TextStyle(font: bold, fontSize: 8, color: PdfColors.white))
        : _richText(text, base: regular, emoji: emoji, size: 8, color: _steel),
  );

  pw.TableRow headerRow() => pw.TableRow(
    decoration: const pw.BoxDecoration(color: _navy),
    children: cols.map((c) => cell(c.header, isHeader: true)).toList(),
  );

  /// The recorded value for one slot on [e].
  String? slotValue(TimelineEntry e, String key) => switch (key) {
    'slot1'  => e.slot1State,
    'slot2'  => e.slot2State,
    'slot3'  => e.slot3State,
    'slot4'  => e.slot4State,
    'slot5'  => e.slot5State,
    'slot6'  => e.slot6State,
    'slot7'  => e.slot7State,
    'slot8'  => e.slot8State,
    'slot9'  => e.slot9State,
    'slot10' => e.slot10State,
    'slot11' => e.slot11State,
    'slot12' => e.slot12State,
    _        => null,
  };

  pw.TableRow dataRow(TimelineEntry e, bool shade) {
    // vesselStatusNote is an auto-generated sentinel ('crew:role=0:...' or
    // 'vs:oil=...,fuel=...,keel=...') — decode it into display text instead
    // of showing the raw internal format, same as the in-app entry card.
    final vesselStatusText = e.vesselStatusNote?.isNotEmpty == true
        ? (isCrewNote(e.vesselStatusNote)
            ? crewNoteDisplay(e.vesselStatusNote!, strings.crewNoteLabel, strings.skipperLabel)
            : parseVesselStatus(
                e.vesselStatusNote!,
                oilLabel:       (pct) => '${strings.oilLabel}: $pct%',
                fuelLabel:      (pct) => '${strings.fuelLabel}: $pct%',
                keelDownLabel:  strings.keelDownLabel,
                keelUpLabel:    strings.keelUpLabel,
                keelFieldLabel: strings.keelLabel,
              ))
        : null;
    final remarksText = [e.remarks, vesselStatusText]
        .where((s) => s?.isNotEmpty == true)
        .join(' · ');

    final cells = <pw.Widget>[
      cell(DateFormat('HH:mm').format(e.time.toLocal())),
      if (hasCourse)  cell(e.course != null && e.course!.isFinite ? '${e.course!.round()}°' : '—'),
      if (hasSpeed)   cell(e.speed   != null ? e.speed!.toStringAsFixed(1) : '—'),
      if (hasWind)    cell(e.wind    ?? '—'),
      if (hasSea)     cell(e.sea     ?? '—'),
      if (hasTemperature) cell(e.temperature != null ? e.temperature!.toStringAsFixed(1) : '—'),
      if (hasPressure)    cell(e.pressure    != null ? e.pressure!.toStringAsFixed(0)    : '—'),
      for (final slot in activeSlots) cell(_slotAbbr(slotValue(e, slot.key))),
      if (hasPosition)
        cell(e.latitude != null && e.longitude != null
            ? formatDDM(e.latitude!, e.longitude!)
            : '—'),
      if (hasRemarks) cell(remarksText.isEmpty ? '—' : remarksText),
    ];

    return pw.TableRow(
      decoration: shade ? const pw.BoxDecoration(color: _fog) : null,
      children: cells,
    );
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _sectionLabel(strings.logEntries, bold),
      pw.SizedBox(height: 6),
      pw.Table(
        columnWidths: columnWidths,
        border: pw.TableBorder.all(color: _rule, width: 0.5),
        children: [
          headerRow(),
          for (int i = 0; i < entries.length; i++)
            dataRow(entries[i], i.isOdd),
        ],
      ),
    ],
  );
}

// ── Notes ─────────────────────────────────────────────────────────────────────

pw.Widget _buildNotes(
    String label, String notes, pw.Font bold, pw.Font italic, pw.Font emoji) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _sectionLabel(label, bold),
      pw.SizedBox(height: 6),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(10),
        child: _richText(notes, base: italic, emoji: emoji, size: 10, color: _steel),
      ),
    ],
  );
}

// ── Photos ────────────────────────────────────────────────────────────────────

pw.Widget _buildPhotos(List<Uint8List> photos, pw.Font bold) {
  const nCols = 3;
  const cellH = 150.0;

  final rows = <pw.Widget>[];
  for (int i = 0; i < photos.length; i += nCols) {
    final end = math.min(i + nCols, photos.length);
    rows.add(pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (int j = 0; j < nCols; j++) ...[
          if (j > 0) pw.SizedBox(width: 6),
          pw.Expanded(
            child: j < end - i
                ? pw.Container(
                    height: cellH,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: _rule, width: 0.5),
                      borderRadius:
                          const pw.BorderRadius.all(pw.Radius.circular(3)),
                    ),
                    child: pw.ClipRRect(
                      horizontalRadius: 3,
                      verticalRadius: 3,
                      child: pw.Image(
                        pw.MemoryImage(photos[i + j]),
                        fit: pw.BoxFit.cover,
                      ),
                    ),
                  )
                : pw.SizedBox(height: cellH),
          ),
        ],
      ],
    ));
    if (end < photos.length) rows.add(pw.SizedBox(height: 6));
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: rows,
  );
}

// ── Footer ────────────────────────────────────────────────────────────────────

pw.Widget _footer(pw.Context ctx, pw.Font regular, PdfStrings strings) {
  return pw.Column(
    children: [
      pw.Divider(color: _rule, thickness: 0.3),
      pw.SizedBox(height: 4),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          strings.pageOfTemplate
              .replaceFirst('-1', '${ctx.pageNumber}')
              .replaceFirst('-2', '${ctx.pagesCount}'),
          style: pw.TextStyle(font: regular, fontSize: 7, color: _rule),
        ),
      ),
    ],
  );
}

// ── Helper ────────────────────────────────────────────────────────────────────

pw.Widget _sectionLabel(String label, pw.Font bold) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
              font: bold, fontSize: 8, color: _steel, letterSpacing: 1.5),
        ),
        pw.SizedBox(height: 3),
        pw.Divider(color: _rule, thickness: 0.5),
      ],
    );

// ── Track map ─────────────────────────────────────────────────────────────────

pw.Widget _buildTrackMap(Uint8List imageBytes, pw.Font bold, pw.Font regular, PdfStrings strings) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _sectionLabel(strings.trackMap, bold),
      pw.SizedBox(height: 6),
      pw.Container(
        height: 160,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _rule, width: 0.5),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.ClipRRect(
          horizontalRadius: 4,
          verticalRadius: 4,
          child: pw.Image(pw.MemoryImage(imageBytes), fit: pw.BoxFit.cover),
        ),
      ),
      pw.SizedBox(height: 3),
      pw.Text(
        '© MapTiler  ·  © OpenStreetMap contributors',
        style: pw.TextStyle(font: regular, fontSize: 6, color: _rule),
      ),
    ],
  );
}

// ── Track-map data helpers ──────────────────────────────────────────────────────
// The actual map image is rendered by the caller (see map_capture.dart's
// captureTrackMapImage/capturePositionsMapImage, using the same live
// BaseVectorMapLayer the on-screen maps use) and passed in as
// trackImageBytes below. These two just derive the (lat, lon) marker
// positions callers need to pass alongside the track/position points.

/// The (lat, lon) marker position for every logbook entry on a tracked day —
/// an entry's own captured GPS fix if it has one, otherwise the track's
/// nearest-in-time point, via the same [correlateTimelineWithTrack] the
/// in-app day-detail map already uses. Unlike [positionedFixes], this
/// covers every entry (a course change, an equipment note, ...), not just
/// ones that logged their own position.
List<(double, double)> entryMarkerPositions(
  DayEntry entry,
  List<TrackPoint> trackPoints,
) {
  if (entry.timeline.isEmpty) return [];
  final correlated = {
    for (final (t, p) in correlateTimelineWithTrack(entry.timeline, trackPoints))
      t: p,
  };
  final sorted = [...entry.timeline]..sort((a, b) => a.time.compareTo(b.time));
  return [
    for (final t in sorted)
      if (t.latitude != null && t.longitude != null)
        (t.latitude!, t.longitude!)
      else if (correlated[t] != null)
        (correlated[t]!.lat, correlated[t]!.lon),
  ];
}

/// The (lat, lon) of every timeline entry that captured a GPS fix, in
/// chronological order — used as a fallback map when the day has no
/// continuous GPS track (e.g. logged entirely by hand, or the track wasn't
/// imported) but at least one log entry still has a position.
List<(double, double)> positionedFixes(DayEntry entry) {
  final positioned = entry.timeline
      .where((t) => t.latitude != null && t.longitude != null)
      .toList()
    ..sort((a, b) => a.time.compareTo(b.time));
  return [for (final t in positioned) (t.latitude!, t.longitude!)];
}
