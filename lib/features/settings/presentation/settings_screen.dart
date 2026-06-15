import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/services/firestore_service.dart';
import '../../../core/services/storage_service.dart';
import '../../home/data/home_repository.dart';
import '../../home/utils/filter_settings.dart';
import '../../home/widgets/nav_bar.dart';
import '../domain/theme_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _vesselNameCtrl;
  late TextEditingController _vesselMmsiCtrl;
  late TextEditingController _vesselCallSignCtrl;
  final TextEditingController _codeCtrl = TextEditingController();
  bool _syncing = false;
  bool _trackFilterExpanded = false;

  @override
  void initState() {
    super.initState();
    final p = context.read<ThemeProvider>();
    _vesselNameCtrl = TextEditingController(text: p.vesselName);
    _vesselMmsiCtrl = TextEditingController(text: p.vesselMmsi);
    _vesselCallSignCtrl = TextEditingController(text: p.vesselCallSign);
  }

  @override
  void dispose() {
    _vesselNameCtrl.dispose();
    _vesselMmsiCtrl.dispose();
    _vesselCallSignCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  String _formatCode(String code) {
    if (code.length == 8) return '${code.substring(0, 4)}-${code.substring(4)}';
    return code;
  }


  Future<void> _connectCode() async {
    final raw = _codeCtrl.text;
    final code = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (code.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ungültiger Code.')),
      );
      return;
    }

    final themeProvider = context.read<ThemeProvider>();
    final repo = context.read<HomeRepository>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          titleTextStyle: TextStyle(
            color: cs.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          contentTextStyle: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 14,
          ),
          title: const Text('Logbuch verbinden'),
          content: Text(
            'Dieses Gerät wird mit dem Logbuch "$code" verbunden. '
            'Alle lokalen Einträge werden gelöscht und durch die Cloud-Daten ersetzt.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Verbinden'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    themeProvider.setLogbookCode(code);
    _codeCtrl.clear();
    if (mounted) FocusScope.of(context).unfocus();

    setState(() => _syncing = true);
    try {
      await repo.reattachAndSync(
        FirestoreService(installationId: code),
        StorageService(installationId: code),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verbunden und synchronisiert.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ThemeProvider>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        foregroundColor: cs.primary,
        iconTheme: IconThemeData(color: cs.primary),
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.black12,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        automaticallyImplyLeading: false,
      ),
      bottomNavigationBar: AppBottomNav(
        active: NavTab.settings,
        showFab: false,
        onSelect: (tab) {
          if (tab == NavTab.journal) context.go('/');
          if (tab == NavTab.map) context.push('/tracks');
          if (tab == NavTab.safety) context.push('/emergency');
        },
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Page header ───────────────────────────────────────────
            Text(
              'Einstellungen',
              style: GoogleFonts.newsreader(
                fontSize: 24,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.24,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Navigationsumgebung konfigurieren',
              style: GoogleFonts.inter(
                fontSize: 15,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),

            // ── Vessel Information ────────────────────────────────────
            _buildVesselSection(p, cs),
            const SizedBox(height: 16),

            // ── Display & Appearance ──────────────────────────────────
            _buildDisplaySection(p, cs),
            const SizedBox(height: 16),

            // ── Track Filter ──────────────────────────────────────────
            _buildTrackFilterSection(p, cs),
            const SizedBox(height: 16),

            // ── Synchronization ───────────────────────────────────────
            _buildSyncSection(p, cs),
            const SizedBox(height: 32),

          ],
        ),
      ),
    );
  }

  // ── Vessel Information ──────────────────────────────────────────────
  Widget _buildVesselSection(ThemeProvider p, ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Positioned(
              left: 0, top: 0, bottom: 0,
              child: Container(width: 4, color: cs.onTertiaryFixedVariant),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'SCHIFF',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: cs.secondary,
                        ),
                      ),
                      Icon(Icons.directions_boat_outlined,
                          size: 20, color: cs.outlineVariant),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _vesselRow(
                    label: 'Name',
                    controller: _vesselNameCtrl,
                    hint: 'z.B. S.V. Adventure',
                    onChanged: p.setVesselName,
                    cs: cs,
                  ),
                  _rowDivider(cs),
                  _vesselRow(
                    label: 'MMSI',
                    controller: _vesselMmsiCtrl,
                    hint: '123456789',
                    onChanged: p.setVesselMmsi,
                    keyboard: TextInputType.number,
                    cs: cs,
                  ),
                  _rowDivider(cs),
                  _vesselRow(
                    label: 'Rufzeichen',
                    controller: _vesselCallSignCtrl,
                    hint: 'z.B. HB-9-XY',
                    onChanged: p.setVesselCallSign,
                    cs: cs,
                    isLast: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vesselRow({
    required String label,
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onChanged,
    required ColorScheme cs,
    TextInputType keyboard = TextInputType.text,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 15,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              textAlign: TextAlign.right,
              keyboardType: keyboard,
              textInputAction: TextInputAction.next,
              style: GoogleFonts.newsreader(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: hint,
                hintStyle: GoogleFonts.inter(
                  fontSize: 15,
                  color: cs.outline.withValues(alpha: 0.5),
                ),
              ),
              onChanged: onChanged,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rowDivider(ColorScheme cs) => Divider(
        color: cs.surfaceContainerHigh,
        height: 16,
        thickness: 1,
      );

  // ── Display & Appearance ────────────────────────────────────────────
  Widget _buildDisplaySection(ThemeProvider p, ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'DARSTELLUNG',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: cs.secondary,
                ),
              ),
              Icon(Icons.palette_outlined,
                  size: 20, color: cs.outlineVariant),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'App-Design',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                _themeButton('System', ThemeMode.system, p, cs),
                _themeButton('Hell', ThemeMode.light, p, cs),
                _themeButton('Dunkel', ThemeMode.dark, p, cs),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _themeButton(
      String label, ThemeMode mode, ThemeProvider p, ColorScheme cs) {
    final isActive = p.themeMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => p.setThemeMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? cs.surfaceContainerLowest : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              color: isActive ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  bool _filterIsModified(ThemeProvider p) =>
      p.filterMode != StationaryMode.speed ||
      p.minStopMinutes != 5.0 ||
      p.maxStopSpreadM != 30.0 ||
      p.detectColdStart != true ||
      p.coldStartSettleFactor != 3.0 ||
      p.makingWayThresholdKn != 1.0 ||
      p.topSpeedPercentile != 0.99;

  // ── Track Filter ────────────────────────────────────────────────────
  Widget _buildTrackFilterSection(ThemeProvider p, ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header (always visible, tap to expand) ────────────
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _trackFilterExpanded = !_trackFilterExpanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Row(
                children: [
                  Text(
                    'TRACKFILTER',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: cs.secondary,
                    ),
                  ),
                  if (_filterIsModified(p)) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (!_trackFilterExpanded)
                    Text(
                      p.filterMode == StationaryMode.speed
                          ? 'Liegeplatz & Anker'
                          : 'Genaue Position',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _trackFilterExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more,
                        size: 20, color: cs.outlineVariant),
                  ),
                ],
              ),
            ),
          ),
          // ── Expandable content ────────────────────────────────
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: _trackFilterExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(color: cs.surfaceContainerHigh, height: 1, thickness: 1),
                  const SizedBox(height: 12),
                  Text(
                    'Stationäre Erkennung',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Bestimmt, wie Liegeplätze, Ankerstopps und Hafenbesuche erkannt und als Ankerpunkt dargestellt werden – am Anfang, Ende und unterwegs.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        _filterModeButton(
                          label: 'Liegeplatz & Anker',
                          mode: StationaryMode.speed,
                          current: p.filterMode,
                          onTap: () => p.setFilterMode(StationaryMode.speed),
                          cs: cs,
                        ),
                        _filterModeButton(
                          label: 'Genaue Position',
                          mode: StationaryMode.both,
                          current: p.filterMode,
                          onTap: () => p.setFilterMode(StationaryMode.both),
                          cs: cs,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    p.filterMode == StationaryMode.speed
                        ? 'Liegeplatz und Ankerpositionen werden als einzelner Punkt dargestellt. Auch ein weitausholender Ankerkreis wird zu einem Punkt zusammengefasst.'
                        : 'Nur eng geclusterte Positionen gelten als stationär. Breite Ankerkreise bleiben sichtbar – besser für Ankerwache.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  _rowDivider(cs),
                  // ── Min. stop duration ──────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Min. Stopp-Dauer',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        '${p.minStopMinutes.round()} min',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: p.minStopMinutes,
                    min: 1,
                    max: 30,
                    divisions: 29,
                    onChanged: p.setMinStopMinutes,
                  ),
                  Text(
                    'Mindestdauer eines echten Stopps (Anker, Hafen). Kurze Langsamfahrten (Wende, Flaute) werden ignoriert.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  _rowDivider(cs),
                  // ── Max anchor swing ────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Max. Ankerschwung',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        '${p.maxStopSpreadM.round()} m',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: p.maxStopSpreadM,
                    min: 10,
                    max: 100,
                    divisions: 18,
                    onChanged: p.setMaxStopSpreadM,
                  ),
                  Text(
                    'Maximale Ausdehnung eines Stopps. Erhöhen bei weitem Ankerschwung über Nacht (Standard: 30 m).',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  _rowDivider(cs),
                  // ── Cold-start trimming ─────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Kaltstart-Trimmen',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      Switch(
                        value: p.detectColdStart,
                        onChanged: p.setDetectColdStart,
                      ),
                    ],
                  ),
                  Text(
                    'Entfernt ungenaue GPS-Fixes am Spuranfang, bevor der Empfänger eingeschwungen ist.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  if (p.detectColdStart) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Trim-Schärfe',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          p.coldStartSettleFactor.toStringAsFixed(1),
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: p.coldStartSettleFactor,
                      min: 1.0,
                      max: 6.0,
                      divisions: 10,
                      onChanged: p.setColdStartSettleFactor,
                    ),
                    Text(
                      'Niedrigerer Wert = aggressiver trimmen. Standard: 3.0.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  _rowDivider(cs),
                  // ── Underway threshold ──────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Unterwegs-Schwelle',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        '${p.makingWayThresholdKn.toStringAsFixed(1)} kn',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: p.makingWayThresholdKn,
                    min: 0.3,
                    max: 3.0,
                    divisions: 27,
                    onChanged: p.setMakingWayThresholdKn,
                  ),
                  Text(
                    'Mindestgeschwindigkeit für den Fahrt-Durchschnitt. Driften unterhalb wird nicht mitgezählt.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  _rowDivider(cs),
                  // ── Max-speed percentile ────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Spitzenwert-Perzentil',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        'p${(p.topSpeedPercentile * 100).round()}',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: p.topSpeedPercentile,
                    min: 0.90,
                    max: 1.00,
                    divisions: 10,
                    onChanged: p.setTopSpeedPercentile,
                  ),
                  Text(
                    'p99 ignoriert das oberste 1 % der Messwerte und unterdrückt GPS-Ausreißer. p100 = echter Maximalwert.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  _rowDivider(cs),
                  // ── Raw track overlay ───────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Ungefilterte Spur anzeigen',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      Switch(
                        value: p.showRawTrack,
                        onChanged: p.setShowRawTrack,
                      ),
                    ],
                  ),
                  Text(
                    'Zeigt den Roh-GPX-Track zusätzlich zur gefilterten Spur an. Dient zur Fehleranalyse und zum Optimieren der Filtereinstellungen.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  if (_filterIsModified(p)) ...[
                    _rowDivider(cs),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: p.resetFilterDefaults,
                        icon: Icon(Icons.restart_alt,
                            size: 16, color: cs.onSurfaceVariant),
                        label: Text(
                          'Zurücksetzen',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterModeButton({
    required String label,
    required StationaryMode mode,
    required StationaryMode current,
    required VoidCallback onTap,
    required ColorScheme cs,
  }) {
    final isActive = current == mode;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? cs.surfaceContainerLowest : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              color: isActive ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  // ── Synchronization ─────────────────────────────────────────────────
  Widget _buildSyncSection(ThemeProvider p, ColorScheme cs) {
    final code = p.logbookCode;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SYNCHRONISIERUNG',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: cs.secondary,
                ),
              ),
              Icon(Icons.sync, size: 20, color: cs.outlineVariant),
            ],
          ),
          const SizedBox(height: 12),
          // Current code
          Text(
            'LOGBUCH-CODE',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Gib diesen Code auf einem anderen Gerät ein, um dasselbe Logbuch zu teilen.',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _formatCode(code),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: cs.onPrimaryContainer,
                      letterSpacing: 6,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _formatCode(code)));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Code kopiert.')),
                  );
                },
                icon: const Icon(Icons.copy_outlined),
                tooltip: 'Kopieren',
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Connect to new logbook
          Text(
            'LOGBOOK SYNC',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Mit einem anderen Logbuch via Firebase verbinden.',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _codeCtrl,
            style: GoogleFonts.inter(
              fontSize: 15,
              color: cs.onSurface,
            ),
            decoration: InputDecoration(
              hintText: 'Sync-Code eingeben',
              hintStyle: GoogleFonts.inter(
                fontSize: 15,
                color: cs.onSurfaceVariant,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: cs.primary),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              filled: true,
              fillColor: cs.surfaceContainerLow,
            ),
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _connectCode(),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _syncing ? null : _connectCode,
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                textStyle: GoogleFonts.inter(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
              child: _syncing
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: cs.onPrimary),
                    )
                  : const Text('Synchronisieren'),
            ),
          ),
        ],
      ),
    );
  }
}
