import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../domain/crew_member.dart';
import '../domain/day_entry.dart';
import '../domain/timeline_entry.dart';
import '../domain/track_point.dart';
import 'compute_daily_stats.dart';

// ── Colour palette (aligned with app theme) ────────────────────────────────────
const _navy  = PdfColor(0.00,  0.141, 0.267);    // #002444 — primary
const _fog   = PdfColor(0.937, 0.929, 0.933);    // #efedee — surface-container
const _rule  = PdfColor(0.761, 0.776, 0.812);    // #c3c6cf — outline-variant
const _steel = PdfColor(0.263, 0.278, 0.306);    // #43474e — on-surface-variant

/// Builds and returns the PDF bytes for a single-day voyage report.
///
/// Fonts are downloaded from Google Fonts on first call and cached by the
/// [printing] package — no internet access needed after that.
Future<Uint8List> buildVoyagePdf({
  required DayEntry entry,
  required DailyStats? stats,
  required String vesselName,
  required String vesselMmsi,
  required String vesselCallSign,
  List<TrackPoint> trackPoints = const [],
  List<Uint8List> photoBytes = const [],
}) async {
  final regular = await PdfGoogleFonts.notoSansRegular();
  final bold    = await PdfGoogleFonts.notoSansBold();
  final italic  = await PdfGoogleFonts.notoSansItalic();

  final Uint8List? trackImageBytes =
      trackPoints.length >= 2 ? await _renderTrackImage(trackPoints) : null;

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 44),
      theme: pw.ThemeData.withFont(base: regular, bold: bold, italic: italic),
      footer: (ctx) => _footer(ctx, regular),
      build: (ctx) {
        final sections = <pw.Widget>[];

        // ── Full-width: Vessel header ──────────────────────────────
        sections.add(_buildHeader(entry, vesselName, vesselMmsi, vesselCallSign, bold, regular, italic));
        sections.add(pw.SizedBox(height: 16));

        // ── Full-width: Voyage title + date box ───────────────────
        final from = entry.fromHarbor?.trim() ?? '';
        final to   = entry.toHarbor?.trim()   ?? '';
        if (from.isNotEmpty || to.isNotEmpty) {
          sections.add(_buildRoute(from, to, entry.date, bold, regular, italic));
          sections.add(pw.SizedBox(height: 16));
        }

        final narrative = entry.notes?.trim()    ?? '';
        final freeNote  = entry.freeText?.trim() ?? '';

        // ── Full-width: Narrative (always, avoids overflowing the two-column row)
        if (narrative.isNotEmpty) {
          sections.add(_buildNotes('TAGEBUCH', narrative, bold, regular, italic));
          sections.add(pw.SizedBox(height: 14));
        }

        // ── Full-width: Photos ─────────────────────────────────────
        if (photoBytes.isNotEmpty) {
          sections.add(pw.Divider(color: _rule, thickness: 0.5));
          sections.add(pw.SizedBox(height: 8));
          sections.add(_buildPhotos(photoBytes, bold));
          sections.add(pw.SizedBox(height: 14));
        }

        // ── Full-width: Free notes ─────────────────────────────────
        if (freeNote.isNotEmpty) {
          sections.add(_buildNotes('NOTIZEN', freeNote, bold, regular, italic));
          sections.add(pw.SizedBox(height: 14));
        }

        // ── Two-column: left = log entries | right = stats+crew+map ──
        final leftCol  = <pw.Widget>[];
        final rightCol = <pw.Widget>[];

        if (entry.timeline.isNotEmpty) {
          leftCol.add(_buildTimeline(entry.timeline, bold, regular));
        }
        if (stats != null) {
          rightCol.add(_buildStats(stats, bold, regular));
        }
        if (entry.crew.isNotEmpty) {
          if (rightCol.isNotEmpty) rightCol.add(pw.SizedBox(height: 14));
          rightCol.add(_buildCrew(entry.crew, bold, regular));
        }
        if (trackImageBytes != null) {
          if (rightCol.isNotEmpty) rightCol.add(pw.SizedBox(height: 14));
          rightCol.add(_buildTrackMap(trackImageBytes, bold, regular));
        }

        if (leftCol.isNotEmpty || rightCol.isNotEmpty) {
          sections.add(pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 8,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: leftCol,
                ),
              ),
              pw.SizedBox(width: 20),
              pw.Expanded(
                flex: 6,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: rightCol,
                ),
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

pw.Widget _buildHeader(
  DayEntry entry,
  String vesselName,
  String vesselMmsi,
  String vesselCallSign,
  pw.Font bold,
  pw.Font regular,
  pw.Font italic,
) {
  final dateStr = DateFormat('d. MMMM yyyy', 'de_CH').format(entry.date);
  final subParts = <String>[
    if (vesselMmsi.isNotEmpty)     'MMSI: $vesselMmsi',
    if (vesselCallSign.isNotEmpty) 'RUFZEICHEN: $vesselCallSign',
  ];

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                vesselName.isNotEmpty ? vesselName.toUpperCase() : 'LOGBUCH',
                style: pw.TextStyle(font: bold, fontSize: 26, color: _navy),
              ),
              if (subParts.isNotEmpty) ...[
                pw.SizedBox(height: 3),
                pw.Text(
                  subParts.join('  ·  '),
                  style: pw.TextStyle(
                      font: bold, fontSize: 8, color: _steel, letterSpacing: 1.5),
                ),
              ],
            ],
          ),
          pw.Text(
            dateStr,
            style: pw.TextStyle(
                font: bold, fontSize: 10, color: _steel, letterSpacing: 0.5),
          ),
        ],
      ),
      pw.SizedBox(height: 8),
      pw.Divider(color: _navy, thickness: 1.5),
    ],
  );
}

// ── Route ─────────────────────────────────────────────────────────────────────

pw.Widget _buildRoute(String from, String to, DateTime date,
    pw.Font bold, pw.Font regular, pw.Font italic) {
  final hasFrom = from.isNotEmpty;
  final hasTo   = to.isNotEmpty;

  final title   = hasTo ? 'Passage nach $to' : 'Abfahrt von $from';
  final dateStr = DateFormat('d. MMM yyyy', 'de_CH').format(date);

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title,
                style: pw.TextStyle(font: bold, fontSize: 18, color: _navy)),
            if (hasFrom && hasTo) ...[
              pw.SizedBox(height: 2),
              pw.Text(
                'Abfahrt von $from',
                style: pw.TextStyle(font: italic, fontSize: 10, color: _steel),
              ),
            ],
          ],
        ),
      ),
      pw.SizedBox(width: 12),
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: pw.BoxDecoration(
          color: _fog,
          border: pw.Border.all(color: _rule, width: 0.5),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('DATUM',
                style: pw.TextStyle(
                    font: bold, fontSize: 7, color: _steel, letterSpacing: 1.2)),
            pw.SizedBox(height: 2),
            pw.Text(dateStr,
                style: pw.TextStyle(font: bold, fontSize: 13, color: _navy)),
          ],
        ),
      ),
    ],
  );
}

// ── Stats ─────────────────────────────────────────────────────────────────────

pw.Widget _buildStats(DailyStats stats, pw.Font bold, pw.Font regular) {
  String dur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return h > 0 ? '${h}h ${m}min' : '${m}min';
  }

  final items = [
    (label: 'DISTANZ',  value: '${stats.distanceNm.toStringAsFixed(1)} nm'),
    (label: 'Ø FAHRT',  value: '${stats.avgOverGroundKn.toStringAsFixed(1)} kn'),
    (label: 'MAX',      value: '${stats.maxSpeedKn.toStringAsFixed(1)} kn'),
    (label: 'FAHRZEIT', value: dur(stats.movingDuration)),
    if (stats.nStops > 0) (label: 'STOPPS', value: '${stats.nStops}'),
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
    children: rows,
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

pw.Widget _buildCrew(List<CrewMember> crew, pw.Font bold, pw.Font regular) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _sectionLabel('MUSTERROLLE', bold),
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
              pw.Text(
                crew[i].name,
                style: pw.TextStyle(
                    font: i == 0 ? bold : regular, fontSize: 10, color: _steel),
              ),
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
                  i == 0 ? 'SKIPPER' : 'BESATZUNG',
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

pw.Widget _buildTimeline(
    List<TimelineEntry> entries, pw.Font bold, pw.Font regular) {
  // Detect which optional columns are actually populated so we only render them.
  final hasCourse  = entries.any((e) => e.course  != null);
  final hasSpeed   = entries.any((e) => e.speed   != null);
  final hasWind    = entries.any((e) => e.wind?.isNotEmpty  == true);
  final hasSea     = entries.any((e) => e.sea?.isNotEmpty   == true);
  final hasMotor   = entries.any((e) => e.motorOn != null);
  final hasSail    = entries.any((e) => e.grossState != null || e.fockState != null);
  final hasRemarks = entries.any((e) =>
      e.remarks?.isNotEmpty == true || e.vesselStatusNote?.isNotEmpty == true);

  // Build ordered column list so flex widths stay aligned.
  final cols = <({String header, double flex})>[
    (header: 'Zeit',      flex: 1.0),
    if (hasCourse)  (header: 'Kurs',   flex: 0.8),
    if (hasSpeed)   (header: 'kn',     flex: 0.7),
    if (hasWind)    (header: 'Wind',   flex: 1.1),
    if (hasSea)     (header: 'See',    flex: 0.8),
    if (hasMotor)   (header: 'Motor',  flex: 0.7),
    if (hasSail)    (header: 'Segel',  flex: 1.0),
    if (hasRemarks) (header: 'Bemerkungen', flex: 2.6),
  ];

  final columnWidths = {
    for (int i = 0; i < cols.length; i++)
      i: pw.FlexColumnWidth(cols[i].flex),
  };

  String sailAbbr(String? s) {
    if (s == null || s.isEmpty) return '—';
    if (s.contains('Voll') || s.contains('Gesetzt')) return 'VG';
    if (s.contains('1.') || s.contains('R1'))        return 'R1';
    if (s.contains('2.') || s.contains('R2'))        return 'R2';
    return '—';
  }

  pw.Widget cell(String text, {bool isHeader = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        font:     isHeader ? bold : regular,
        fontSize: 8,
        color:    isHeader ? PdfColors.white : _steel,
      ),
    ),
  );

  pw.TableRow headerRow() => pw.TableRow(
    decoration: const pw.BoxDecoration(color: _navy),
    children: cols.map((c) => cell(c.header, isHeader: true)).toList(),
  );

  pw.TableRow dataRow(TimelineEntry e, bool shade) {
    final sailText =
        '${sailAbbr(e.grossState)} / ${sailAbbr(e.fockState)}';
    final remarksText = [e.remarks, e.vesselStatusNote]
        .where((s) => s?.isNotEmpty == true)
        .join(' · ');

    final cells = <pw.Widget>[
      cell(DateFormat('HH:mm').format(e.time.toLocal())),
      if (hasCourse)  cell(e.course  != null ? '${e.course!.round()}°' : '—'),
      if (hasSpeed)   cell(e.speed   != null ? e.speed!.toStringAsFixed(1) : '—'),
      if (hasWind)    cell(e.wind    ?? '—'),
      if (hasSea)     cell(e.sea     ?? '—'),
      if (hasMotor)   cell(e.motorOn == null ? '—' : (e.motorOn! ? 'AN' : 'AUS')),
      if (hasSail)    cell(sailText),
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
      _sectionLabel('LOGBUCH-EINTRÄGE', bold),
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
    String label, String notes, pw.Font bold, pw.Font regular, pw.Font italic) {
  final isNarrative = label == 'TAGEBUCH';
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _sectionLabel(label, bold),
      pw.SizedBox(height: 6),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: isNarrative ? PdfColors.white : _fog,
          border: pw.Border.all(color: _rule, width: 0.5),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Text(
          isNarrative ? '“$notes”' : notes,
          style: pw.TextStyle(
            font: isNarrative ? italic : regular,
            fontSize: isNarrative ? 10 : 9,
            color: _steel,
          ),
        ),
      ),
    ],
  );
}

// ── Photos ────────────────────────────────────────────────────────────────────

pw.Widget _buildPhotos(List<Uint8List> photos, pw.Font bold) {
  const nCols = 4;
  const cellH = 110.0;

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
    children: [
      _sectionLabel('VISUELLE DOKUMENTATION', bold),
      pw.SizedBox(height: 8),
      ...rows,
    ],
  );
}

// ── Footer ────────────────────────────────────────────────────────────────────

pw.Widget _footer(pw.Context ctx, pw.Font regular) {
  return pw.Column(
    children: [
      pw.Divider(color: _rule, thickness: 0.3),
      pw.SizedBox(height: 4),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Log erstellt mit Logbuch-App',
            style: pw.TextStyle(
                font: regular, fontSize: 7, color: _rule, letterSpacing: 0.8)),
          pw.Row(
            children: [
              pw.Text(
                'Skipper: ',
                style: pw.TextStyle(font: regular, fontSize: 7, color: _rule)),
              pw.Container(
                width: 80,
                height: 8,
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: _rule, width: 0.5),
                  ),
                ),
              ),
              pw.SizedBox(width: 20),
              pw.Text(
                'Seite ${ctx.pageNumber} von ${ctx.pagesCount}',
                style: pw.TextStyle(font: regular, fontSize: 7, color: _rule)),
            ],
          ),
        ],
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

pw.Widget _buildTrackMap(Uint8List imageBytes, pw.Font bold, pw.Font regular) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _sectionLabel('KURS & TRACK', bold),
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
        '© OpenStreetMap  ·  © OpenSeaMap',
        style: pw.TextStyle(font: regular, fontSize: 6, color: _rule),
      ),
    ],
  );
}

// ── Tile-map rendering ────────────────────────────────────────────────────────

// Web Mercator pixel coordinates (origin = top-left of world at zoom z)
double _mercX(double lon, int z) =>
    (lon + 180) / 360 * math.pow(2, z) * 256;

double _mercY(double lat, int z) {
  final r = lat * math.pi / 180;
  return (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) /
      2 *
      math.pow(2, z) *
      256;
}

(int, int) _tile(double lon, double lat, int z) {
  final n = math.pow(2, z).toInt();
  return (
    (_mercX(lon, z) / 256).floor().clamp(0, n - 1),
    (_mercY(lat, z) / 256).floor().clamp(0, n - 1),
  );
}

// Highest zoom where the bounding box (+ 1-tile padding each side) fits
// within 5 × 4 tiles.
int _chooseZoom(double minLat, double maxLat, double minLon, double maxLon) {
  for (int z = 17; z >= 1; z--) {
    final (x0, y0) = _tile(minLon, maxLat, z); // NW
    final (x1, y1) = _tile(maxLon, minLat, z); // SE
    if (x1 - x0 + 3 <= 5 && y1 - y0 + 3 <= 4) return z;
  }
  return 1;
}

Future<ui.Image?> _fetchTile(int z, int tx, int ty, String base) async {
  try {
    final client = HttpClient()..userAgent = 'Logbuch/1.0 sailing logbook app';
    final req = await client
        .getUrl(Uri.parse('$base/$z/$tx/$ty.png'))
        .timeout(const Duration(seconds: 8));
    final res = await req.close().timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) { client.close(); return null; }
    final chunks = <List<int>>[];
    await for (final c in res) { chunks.add(c); }
    client.close();
    final bytes = Uint8List.fromList(chunks.expand((c) => c).toList());
    final codec = await ui.instantiateImageCodec(bytes);
    return (await codec.getNextFrame()).image;
  } catch (_) {
    return null;
  }
}

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

  // Fetch OSM base + OpenSeaMap overlay in parallel
  final coords = [
    for (int tx = tx0; tx <= tx1; tx++)
      for (int ty = ty0; ty <= ty1; ty++) (tx, ty),
  ];

  const osmUrl  = 'https://tile.openstreetmap.org';
  const seamUrl = 'https://tiles.openseamap.org/seamark';

  final results = await Future.wait([
    for (final (tx, ty) in coords) _fetchTile(zoom, tx, ty, osmUrl),
    for (final (tx, ty) in coords) _fetchTile(zoom, tx, ty, seamUrl),
  ]);
  final osmImages  = results.sublist(0, coords.length);
  final seamImages = results.sublist(coords.length);

  final recorder = ui.PictureRecorder();
  final canvas   = ui.Canvas(recorder);

  // Fallback background if tiles are missing
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, canvasW, canvasH),
    ui.Paint()..color = const ui.Color(0xFFD8E8F0),
  );

  // Draw OSM tiles
  for (int i = 0; i < coords.length; i++) {
    final (tx, ty) = coords[i];
    final img = osmImages[i];
    if (img != null) {
      canvas.drawImage(
        img,
        ui.Offset((tx - tx0) * 256.0, (ty - ty0) * 256.0),
        ui.Paint(),
      );
    }
  }

  // Draw OpenSeaMap overlay tiles
  for (int i = 0; i < coords.length; i++) {
    final (tx, ty) = coords[i];
    final img = seamImages[i];
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

void _drawMarker(ui.Canvas canvas, double x, double y, ui.Color color) {
  canvas.drawCircle(ui.Offset(x, y), 7, ui.Paint()..color = color);
  canvas.drawCircle(ui.Offset(x, y), 7,
    ui.Paint()
      ..color      = const ui.Color(0xFFFFFFFF)
      ..style      = ui.PaintingStyle.stroke
      ..strokeWidth = 2);
}

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
