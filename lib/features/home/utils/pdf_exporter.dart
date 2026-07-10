import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart'
    show BuiltInMapCachingProvider, CachedMapTile, CachedMapTileMetadata;

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/constants/map_config.dart';
import '../domain/crew_member.dart';
import '../domain/day_entry.dart';
import '../domain/timeline_entry.dart';
import '../domain/track_point.dart';
import '../domain/vessel_equipment.dart';
import 'compute_daily_stats.dart';

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
  final String avgSpeed;
  final String max;
  final String duration;
  final String stops;
  final String statistics;
  final String crew;
  final String skipper;
  final String crewMember;
  final String logEntries;
  final String timeCol;
  final String courseCol;
  final String windCol;
  final String seaCol;
  final String remarksCol;
  final String trackMap;
  final String locale;
  final String Function(String destination) passageTo;
  final String Function(String origin) departureFrom;
  final String Function(int page, int total) pageOf;

  const PdfStrings({
    required this.voyageLog,
    required this.notes,
    required this.date,
    required this.distance,
    required this.avgSpeed,
    required this.max,
    required this.duration,
    required this.stops,
    required this.statistics,
    required this.crew,
    required this.skipper,
    required this.crewMember,
    required this.logEntries,
    required this.timeCol,
    required this.courseCol,
    required this.windCol,
    required this.seaCol,
    required this.remarksCol,
    required this.trackMap,
    required this.locale,
    required this.passageTo,
    required this.departureFrom,
    required this.pageOf,
  });
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
  List<TrackPoint> trackPoints = const [],
  List<Uint8List> photoBytes = const [],
}) async {
  final regular  = await PdfGoogleFonts.notoSansRegular();
  final bold     = await PdfGoogleFonts.notoSansBold();
  final italic   = await PdfGoogleFonts.notoSansItalic();
  final emojiFont = await PdfGoogleFonts.notoEmojiRegular();

  final Uint8List? trackImageBytes =
      trackPoints.length >= 2 ? await _renderTrackImage(trackPoints) : null;

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 44),
      theme: pw.ThemeData.withFont(base: regular, bold: bold, italic: italic),
      footer: (ctx) => _footer(ctx, regular, strings),
      build: (ctx) {
        final sections = <pw.Widget>[];

        // ── Full-width: Vessel header ──────────────────────────────
        sections.add(_buildHeader(vesselName, bold, emojiFont));
        sections.add(pw.SizedBox(height: 16));

        // ── Full-width: Voyage title + date box ───────────────────
        final from = entry.fromHarbor?.trim() ?? '';
        final to   = entry.toHarbor?.trim()   ?? '';
        if (from.isNotEmpty || to.isNotEmpty) {
          sections.add(_buildRoute(from, to, entry.date, bold, regular, italic, emojiFont, strings));
          sections.add(pw.SizedBox(height: 16));
        }

        final narrative = entry.notes?.trim()    ?? '';
        final freeNote  = entry.freeText?.trim() ?? '';

        // ── Full-width: Narrative (always, avoids overflowing the two-column row)
        if (narrative.isNotEmpty) {
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

        // ── Row 2: Timeline (left) | Crew (right) ─────────────────
        if (entry.timeline.isNotEmpty || entry.crew.isNotEmpty) {
          sections.add(pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 8,
                child: entry.timeline.isNotEmpty
                    ? _buildTimeline(entry.timeline, bold, regular, emojiFont, strings, equipment)
                    : pw.SizedBox(),
              ),
              pw.SizedBox(width: 20),
              pw.Expanded(
                flex: 5,
                child: entry.crew.isNotEmpty
                    ? _buildCrew(entry.crew, bold, regular, emojiFont, strings)
                    : pw.SizedBox(),
              ),
            ],
          ));
        }


        return sections;
      },
    ),
  );

  return doc.save();
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
    pw.Font bold, pw.Font regular, pw.Font italic, pw.Font emoji, PdfStrings strings) {
  final hasFrom = from.isNotEmpty;
  final hasTo   = to.isNotEmpty;

  final title   = hasTo ? strings.passageTo(to) : strings.departureFrom(from);
  final dateStr = DateFormat('d. MMM yyyy', strings.locale).format(date);

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _richText(title, base: bold, emoji: emoji, size: 18, color: _navy),
            if (hasFrom && hasTo) ...[
              pw.SizedBox(height: 2),
              _richText(strings.departureFrom(from),
                  base: italic, emoji: emoji, size: 10, color: _steel),
            ],
          ],
        ),
      ),
      pw.SizedBox(width: 12),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(strings.date,
              style: pw.TextStyle(
                  font: bold, fontSize: 7, color: _steel, letterSpacing: 1.2)),
          pw.SizedBox(height: 2),
          pw.Text(dateStr,
              style: pw.TextStyle(font: bold, fontSize: 13, color: _navy)),
        ],
      ),
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

  final items = [
    (label: strings.distance, value: '${stats.distanceNm.toStringAsFixed(1)} nm'),
    (label: strings.avgSpeed, value: '${stats.avgOverGroundKn.toStringAsFixed(1)} kn'),
    (label: strings.max,      value: '${stats.maxSpeedKn.toStringAsFixed(1)} kn'),
    (label: strings.duration, value: dur(stats.movingDuration)),
    if (stats.nStops > 0) (label: strings.stops, value: '${stats.nStops}'),
  ];

  final rows = <pw.Widget>[];
  for (int i = 0; i < items.length; i += 2) {
    if (i > 0) rows.add(pw.SizedBox(height: 6));
    rows.add(pw.Row(
      children: [
        pw.Expanded(child: _statCard(items[i].label, items[i].value, bold, regular)),
        pw.SizedBox(width: 6),
        pw.Expanded(
          child: i + 1 < items.length
              ? _statCard(items[i + 1].label, items[i + 1].value, bold, regular)
              : pw.SizedBox(),
        ),
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
          decoration: pw.BoxDecoration(
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
                    ? pw.BoxDecoration(
                        color: _navy,
                        borderRadius:
                            const pw.BorderRadius.all(pw.Radius.circular(2)),
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
    final remarksText = [e.remarks, e.vesselStatusNote]
        .where((s) => s?.isNotEmpty == true)
        .join(' · ');

    final cells = <pw.Widget>[
      cell(DateFormat('HH:mm').format(e.time.toLocal())),
      if (hasCourse)  cell(e.course  != null ? '${e.course!.round()}°' : '—'),
      if (hasSpeed)   cell(e.speed   != null ? e.speed!.toStringAsFixed(1) : '—'),
      if (hasWind)    cell(e.wind    ?? '—'),
      if (hasSea)     cell(e.sea     ?? '—'),
      if (hasTemperature) cell(e.temperature != null ? e.temperature!.toStringAsFixed(1) : '—'),
      if (hasPressure)    cell(e.pressure    != null ? e.pressure!.toStringAsFixed(0)    : '—'),
      for (final slot in activeSlots) cell(_slotAbbr(slotValue(e, slot.key))),
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
          strings.pageOf(ctx.pageNumber, ctx.pagesCount),
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

// ── Tile-map rendering ────────────────────────────────────────────────────────
// Renders a static track-map image for the PDF by manually fetching and
// compositing map tiles onto a canvas (there's no live flutter_map widget
// available in a headless PDF-generation context).

/// Web Mercator pixel X coordinate (origin = top-left of world at zoom [z]).
double _mercX(double lon, int z) =>
    (lon + 180) / 360 * math.pow(2, z) * 256;

/// Web Mercator pixel Y coordinate (origin = top-left of world at zoom [z]).
double _mercY(double lat, int z) {
  final r = lat * math.pi / 180;
  return (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) /
      2 *
      math.pow(2, z) *
      256;
}

/// The (x, y) tile-grid indices containing (lon, lat) at zoom [z].
(int, int) _tile(double lon, double lat, int z) {
  final n = math.pow(2, z).toInt();
  return (
    (_mercX(lon, z) / 256).floor().clamp(0, n - 1),
    (_mercY(lat, z) / 256).floor().clamp(0, n - 1),
  );
}

/// Highest zoom where the track's bounding box (+ 1-tile padding each side)
/// still fits within a 5 × 4 tile grid — keeps the rendered image a fixed,
/// bounded size regardless of how long the day's track is.
int _chooseZoom(double minLat, double maxLat, double minLon, double maxLon) {
  for (int z = 17; z >= 1; z--) {
    final (x0, y0) = _tile(minLon, maxLat, z); // NW
    final (x1, y1) = _tile(maxLon, minLat, z); // SE
    if (x1 - x0 + 3 <= 5 && y1 - y0 + 3 <= 4) return z;
  }
  return 1;
}

/// Decodes raw image bytes (a downloaded/cached tile) into a drawable [ui.Image].
Future<ui.Image?> _decodeBytes(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  return (await codec.getNextFrame()).image;
}

// Shares the on-disk tile cache that flutter_map's map screens already use
// (the same MapTiler tiles are frequently re-requested here for PDF export),
// so exporting doesn't re-download tiles the map has already cached.
Future<ui.Image?> _fetchTile(int z, int tx, int ty, String base) async {
  // Supports both template URLs ({z}/{x}/{y} with optional query string)
  // and plain base URLs (base/$z/$tx/$ty.png for OpenSeaMap-style servers).
  final url = base.contains('{z}')
      ? base
          .replaceAll('{z}', '$z')
          .replaceAll('{x}', '$tx')
          .replaceAll('{y}', '$ty')
      : '$base/$z/$tx/$ty.png';

  final cache = BuiltInMapCachingProvider.getOrCreateInstance();
  CachedMapTile? cached;
  if (cache.isSupported) {
    try {
      cached = await cache.getTile(url);
    } catch (_) {
      cached = null;
    }
  }
  if (cached != null && !cached.metadata.isStale) {
    try {
      return await _decodeBytes(cached.bytes);
    } catch (_) {
      // Corrupt cache entry - fall through and re-fetch from the network.
    }
  }

  HttpClient? client;
  try {
    client = HttpClient()..userAgent = 'Logbuch/1.0 sailing logbook app';
    final req = await client
        .getUrl(Uri.parse(url))
        .timeout(const Duration(seconds: 8));
    if (cached != null) {
      final lastModified = cached.metadata.lastModified;
      final etag = cached.metadata.etag;
      if (lastModified != null) {
        req.headers.set(
          HttpHeaders.ifModifiedSinceHeader,
          HttpDate.format(lastModified),
        );
      }
      if (etag != null) req.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
    }
    final res = await req.close().timeout(const Duration(seconds: 8));

    final headers = <String, String>{};
    res.headers.forEach(
      (name, values) => headers[name.toLowerCase()] = values.join(', '),
    );

    if (res.statusCode == HttpStatus.notModified && cached != null) {
      if (cache.isSupported) {
        try {
          await cache.putTile(
            url: url,
            metadata: CachedMapTileMetadata.fromHttpHeaders(headers),
          );
        } catch (_) {}
      }
      return await _decodeBytes(cached.bytes);
    }

    if (res.statusCode != 200) return null;
    final chunks = <List<int>>[];
    await for (final c in res) { chunks.add(c); }
    final bytes = Uint8List.fromList(chunks.expand((c) => c).toList());

    if (cache.isSupported) {
      try {
        await cache.putTile(
          url: url,
          metadata: CachedMapTileMetadata.fromHttpHeaders(headers),
          bytes: bytes,
        );
      } catch (_) {}
    }

    return await _decodeBytes(bytes);
  } catch (e) {
    if (kDebugMode) debugPrint('_fetchTile: $e');
    return null;
  } finally {
    client?.close();
  }
}

/// Renders [points] onto a composited basemap-tile image (with start/end
/// markers and a north indicator) and returns it as PNG bytes, or null if
/// there are too few points to draw a track.
Future<Uint8List?> _renderTrackImage(List<TrackPoint> points) async {
  if (points.length < 2) return null;

  var minLat = points.first.lat, maxLat = minLat;
  var minLon = points.first.lon, maxLon = minLon;
  for (final p in points) {
    if (p.lat < minLat) minLat = p.lat;
    if (p.lat > maxLat) maxLat = p.lat;
    if (p.lon < minLon) minLon = p.lon;
    if (p.lon > maxLon) maxLon = p.lon;
  }

  final zoom   = _chooseZoom(minLat, maxLat, minLon, maxLon);
  final maxIdx = math.pow(2, zoom).toInt() - 1;

  final (nx0, ny0) = _tile(minLon, maxLat, zoom); // NW tile
  final (nx1, ny1) = _tile(maxLon, minLat, zoom); // SE tile
  final tx0 = (nx0 - 1).clamp(0, maxIdx);
  final ty0 = (ny0 - 1).clamp(0, maxIdx);
  final tx1 = (nx1 + 1).clamp(0, maxIdx);
  final ty1 = (ny1 + 1).clamp(0, maxIdx);

  final canvasW = (tx1 - tx0 + 1) * 256.0;
  final canvasH = (ty1 - ty0 + 1) * 256.0;

  // Fetch MapTiler tiles (same style as the daily map screen)
  final coords = [
    for (int tx = tx0; tx <= tx1; tx++)
      for (int ty = ty0; ty <= ty1; ty++) (tx, ty),
  ];

  final tileImages = await Future.wait([
    for (final (tx, ty) in coords) _fetchTile(zoom, tx, ty, kBaseTileUrl),
  ]);

  final recorder = ui.PictureRecorder();
  final canvas   = ui.Canvas(recorder);

  // Fallback background if tiles are missing
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, canvasW, canvasH),
    ui.Paint()..color = const ui.Color(0xFFD8E8F0),
  );

  // Draw MapTiler tiles
  for (int i = 0; i < coords.length; i++) {
    final (tx, ty) = coords[i];
    final img = tileImages[i];
    if (img != null) {
      canvas.drawImage(
        img,
        ui.Offset((tx - tx0) * 256.0, (ty - ty0) * 256.0),
        ui.Paint(),
      );
    }
  }

  // Project track points via Web Mercator offset by tile-grid origin
  double toX(double lon) => _mercX(lon, zoom) - tx0 * 256;
  double toY(double lat) => _mercY(lat, zoom) - ty0 * 256;

  // Track polyline — white halo + navy line for visibility on any basemap
  final trackPath = ui.Path();
  bool first = true;
  for (final p in points) {
    final x = toX(p.lon);
    final y = toY(p.lat);
    if (first) { trackPath.moveTo(x, y); first = false; }
    else        { trackPath.lineTo(x, y); }
  }
  canvas.drawPath(trackPath, ui.Paint()
    ..color      = const ui.Color(0xCCFFFFFF)
    ..strokeWidth = 6.0
    ..style      = ui.PaintingStyle.stroke
    ..strokeCap  = ui.StrokeCap.round
    ..strokeJoin = ui.StrokeJoin.round);
  canvas.drawPath(trackPath, ui.Paint()
    ..color      = const ui.Color(0xDD003366)
    ..strokeWidth = 3.0
    ..style      = ui.PaintingStyle.stroke
    ..strokeCap  = ui.StrokeCap.round
    ..strokeJoin = ui.StrokeJoin.round);

  _drawMarker(canvas, toX(points.first.lon), toY(points.first.lat),
      const ui.Color(0xFF2E7D32));
  _drawMarker(canvas, toX(points.last.lon),  toY(points.last.lat),
      const ui.Color(0xFFC62828));
  _drawNorthIndicator(canvas, canvasW - 32, 34);

  final picture  = recorder.endRecording();
  final image    = await picture.toImage(canvasW.toInt(), canvasH.toInt());
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData?.buffer.asUint8List();
}

/// Draws a filled, white-ringed dot at (x, y) — used for the track's start
/// (green) and end (red) markers.
void _drawMarker(ui.Canvas canvas, double x, double y, ui.Color color) {
  canvas.drawCircle(ui.Offset(x, y), 7, ui.Paint()..color = color);
  canvas.drawCircle(ui.Offset(x, y), 7,
    ui.Paint()
      ..color      = const ui.Color(0xFFFFFFFF)
      ..style      = ui.PaintingStyle.stroke
      ..strokeWidth = 2);
}

/// Draws a small "N" compass badge in the map image's top-right corner.
void _drawNorthIndicator(ui.Canvas canvas, double cx, double cy) {
  const r = 16.0;
  canvas.drawCircle(ui.Offset(cx, cy), r,
      ui.Paint()..color = const ui.Color(0xCCE8EEF4));
  canvas.drawCircle(ui.Offset(cx, cy), r,
    ui.Paint()
      ..color      = const ui.Color(0xFF8FA8BF)
      ..style      = ui.PaintingStyle.stroke
      ..strokeWidth = 1);
  // North arrow
  canvas.drawPath(
    ui.Path()
      ..moveTo(cx, cy - r + 5)
      ..lineTo(cx - 5.5, cy + 5)
      ..lineTo(cx + 5.5, cy + 5)
      ..close(),
    ui.Paint()..color = const ui.Color(0xFF003366));
  canvas.drawLine(ui.Offset(cx, cy + 5), ui.Offset(cx, cy + r - 4),
    ui.Paint()
      ..color      = const ui.Color(0xFF8FA8BF)
      ..strokeWidth = 2);
  final para = (ui.ParagraphBuilder(
      ui.ParagraphStyle(fontSize: 10, textAlign: ui.TextAlign.center))
    ..pushStyle(ui.TextStyle(
        color: const ui.Color(0xFF003366),
        fontSize: 10,
        fontWeight: ui.FontWeight.bold))
    ..addText('N'))
      .build()..layout(const ui.ParagraphConstraints(width: 20));
  canvas.drawParagraph(para, ui.Offset(cx - 10, cy - r - 14));
}
