import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/services/boat_service.dart';
import '../../../core/services/firestore_service.dart';
import '../../../core/services/storage_service.dart';
import '../../auth/domain/auth_provider.dart';
import '../../emergency/data/emergency_repository.dart';
import '../../home/data/home_repository.dart';
import '../../home/screens/crew_roster_screen.dart';
import '../../home/utils/filter_settings.dart';
import '../../home/widgets/nav_bar.dart';
import '../domain/theme_provider.dart';
import '../../../l10n/l10n_extension.dart';

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


  Future<void> _openScanner() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const _QrScannerScreen(),
      ),
    );
    if (code != null && mounted) {
      await _connectLogbook(code);
    }
  }

  // [prefilledCode] comes from QR scan; omit to read from the text field.
  Future<void> _connectLogbook([String? prefilledCode]) async {
    final l10n = context.l10n;
    final raw = prefilledCode ?? _codeCtrl.text;
    final code = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsInvalidCode)),
      );
      return;
    }
    final user = AuthService.currentUser;
    if (user == null) return;

    // Phase 1: look up the boat by invite code.
    setState(() => _syncing = true);
    String? foundBoatId;
    String? currentBoatId;
    try {
      foundBoatId = await BoatService().findBoatByInviteCode(code);
      if (foundBoatId != null) {
        currentBoatId = await BoatService().getBoatIdForUser(user.uid);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.l10n.settingsError}: $e')),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
    if (!mounted) return;

    if (foundBoatId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsCodeNotFound)),
      );
      return;
    }
    if (foundBoatId == currentBoatId) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsAlreadyConnected)),
      );
      return;
    }

    // Phase 2: confirm and join.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final cl = ctx.l10n;
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
          title: Text(cl.settingsSwitchLogbookTitle),
          content: Text(cl.settingsSwitchLogbookContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(cl.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(cl.connect),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _syncing = true);
    try {
      await BoatService().joinBoat(foundBoatId, user.uid);
      if (!mounted) return;

      final themeProvider = context.read<ThemeProvider>();
      final repo = context.read<HomeRepository>();
      final emergencyRepo = context.read<EmergencyRepository>();
      final firestore = FirestoreService(boatId: foundBoatId);
      final storage = StorageService(boatId: foundBoatId);

      // reattachAndSync clears local Hive data first, then fetches all entries
      // from the new boat. This prevents local data from being uploaded to the
      // new boat (which attachFirestore(initialSync: true) would do).
      await repo.reattachAndSync(firestore, storage);
      await themeProvider.attachFirestore(firestore);
      await emergencyRepo.attachFirestore(firestore);

      _codeCtrl.clear();
      if (mounted) {
        FocusScope.of(context).unfocus();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.settingsConnected)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.settingsError}: $e')),
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
    final l10n = context.l10n;

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
              l10n.settingsTitle,
              style: GoogleFonts.newsreader(
                fontSize: 24,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.24,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              l10n.settingsSubtitle,
              style: GoogleFonts.inter(
                fontSize: 15,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),

            // ── Account ───────────────────────────────────────────────
            _buildAccountSection(cs),
            const SizedBox(height: 16),

            // ── Vessel Information ────────────────────────────────────
            _buildVesselSection(p, cs),
            const SizedBox(height: 16),

            // ── Display & Appearance ──────────────────────────────────
            _buildDisplaySection(p, cs),
            const SizedBox(height: 16),

            // ── Track Filter ──────────────────────────────────────────
            _buildTrackFilterSection(p, cs),
            const SizedBox(height: 16),

            // ── Crew Roster ───────────────────────────────────────────
            _buildCrewRosterSection(cs),
            const SizedBox(height: 16),

            // ── Connect Logbook ───────────────────────────────────────
            _buildConnectSection(p, cs),
            const SizedBox(height: 32),

          ],
        ),
      ),
    );
  }

  // ── Vessel Information ──────────────────────────────────────────────
  Widget _buildVesselSection(ThemeProvider p, ColorScheme cs) {
    final l10n = context.l10n;
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
                        context.l10n.settingsVesselSection.toUpperCase(),
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
                    label: l10n.settingsFieldName,
                    controller: _vesselNameCtrl,
                    hint: l10n.settingsFieldNameHint,
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
                    label: l10n.settingsFieldCallSign,
                    controller: _vesselCallSignCtrl,
                    hint: l10n.settingsFieldCallSignHint,
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
    final l10n = context.l10n;
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
                l10n.settingsAppearanceSection.toUpperCase(),
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
            l10n.settingsThemeLabel,
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
                _themeButton(l10n.settingsThemeSystem, ThemeMode.system, p, cs),
                _themeButton(l10n.settingsThemeLight, ThemeMode.light, p, cs),
                _themeButton(l10n.settingsThemeDark, ThemeMode.dark, p, cs),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.settingsLanguageLabel,
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
                _langButton(l10n.settingsLanguageDe, const Locale('de'), p, cs),
                _langButton(l10n.settingsLanguageEn, const Locale('en'), p, cs),
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

  Widget _langButton(
      String label, Locale locale, ThemeProvider p, ColorScheme cs) {
    final isActive = p.locale == locale;
    return Expanded(
      child: GestureDetector(
        onTap: () => p.setLocale(locale),
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
                    context.l10n.settingsTrackFilterSection.toUpperCase(),
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
                          ? context.l10n.settingsFilterModeMooring
                          : context.l10n.settingsFilterModeExact,
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
                    context.l10n.settingsStationaryLabel,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.settingsStationaryDesc,
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
                          label: context.l10n.settingsFilterModeMooring,
                          mode: StationaryMode.speed,
                          current: p.filterMode,
                          onTap: () => p.setFilterMode(StationaryMode.speed),
                          cs: cs,
                        ),
                        _filterModeButton(
                          label: context.l10n.settingsFilterModeExact,
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
                        ? context.l10n.settingsMooringDesc
                        : context.l10n.settingsExactPositionDesc,
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
                        context.l10n.settingsMinStopLabel,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        '${p.minStopMinutes.round()} ${context.l10n.settingsMinUnit}',
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
                    context.l10n.settingsMinStopDesc,
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
                        context.l10n.settingsMaxAnchorLabel,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        '${p.maxStopSpreadM.round()} ${context.l10n.settingsMetersUnit}',
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
                    context.l10n.settingsMaxAnchorDesc,
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
                        context.l10n.settingsColdStartLabel,
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
                    context.l10n.settingsColdStartDesc,
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
                          context.l10n.settingsTrimSharpnessLabel,
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
                      context.l10n.settingsTrimSharpnessDesc,
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
                        context.l10n.settingsUnderwayLabel,
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
                    context.l10n.settingsUnderwayDesc,
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
                        context.l10n.settingsPercentileLabel,
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
                    context.l10n.settingsPercentileDesc,
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
                        context.l10n.settingsShowRawTrackLabel,
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
                    context.l10n.settingsShowRawTrackDesc,
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
                          context.l10n.reset,
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

  // ── Crew Roster ──────────────────────────────────────────────────────
  Widget _buildCrewRosterSection(ColorScheme cs) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CrewRosterScreen()),
      ),
      child: Container(
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
                child: Container(width: 4, color: cs.tertiaryContainer),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
                child: Row(
                  children: [
                    Icon(Icons.people_outline, size: 20, color: cs.tertiary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.settingsCrewSection.toUpperCase(),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                              color: cs.secondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Consumer<HomeRepository>(
                            builder: (_, repo, _) {
                              final count = repo.roster.length;
                              return Text(
                                count == 0
                                    ? context.l10n.settingsNoEntries
                                    : '$count ${context.l10n.settingsPersonCount(count)}',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: cs.onSurfaceVariant,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: cs.outlineVariant),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Connect Logbook ──────────────────────────────────────────────────
  Widget _buildConnectSection(ThemeProvider p, ColorScheme cs) {
    final l10n = context.l10n;
    final auth = context.watch<AuthProvider>();

    if (!auth.isSignedIn) return const SizedBox.shrink();

    final code = p.installationId;
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
                l10n.settingsSyncSection.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: cs.secondary,
                ),
              ),
              Icon(Icons.link, size: 20, color: cs.outlineVariant),
            ],
          ),
          const SizedBox(height: 12),
          // ── Invite code display ──────────────────────────────────
          Text(
            l10n.settingsInviteCodeLabel,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.settingsInviteCodeDesc,
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
                    SnackBar(content: Text(l10n.settingsCodeCopied)),
                  );
                },
                icon: const Icon(Icons.copy_outlined),
                tooltip: l10n.copy,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── QR code for in-person sharing ────────────────────────
          Center(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: 'logbook://join/$code',
                version: QrVersions.auto,
                size: 150,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 20),
          // ── Join another logbook ─────────────────────────────────
          TextField(
            controller: _codeCtrl,
            style: GoogleFonts.inter(
              fontSize: 15,
              color: cs.onSurface,
            ),
            decoration: InputDecoration(
              hintText: l10n.settingsEnterInviteCode,
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
            onSubmitted: (_) => _connectLogbook(),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _syncing ? null : _connectLogbook,
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
                  : Text(l10n.settingsConnectButton),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _syncing ? null : _openScanner,
              icon: const Icon(Icons.qr_code_scanner, size: 20),
              label: Text(l10n.settingsScanQr),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: cs.outline),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                textStyle: GoogleFonts.inter(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Account ──────────────────────────────────────────────────────────
  Widget _buildAccountSection(ColorScheme cs) {
    final l10n = context.l10n;
    final auth = context.watch<AuthProvider>();

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
                l10n.settingsAccountSection.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: cs.secondary,
                ),
              ),
              Icon(Icons.person_outline, size: 20, color: cs.outlineVariant),
            ],
          ),
          const SizedBox(height: 12),
          if (auth.isSignedIn) ...[
            Text(
              l10n.settingsAccountSignedInAs,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              auth.email ?? auth.displayName ?? '',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(l10n.authSignOut),
                      content: Text(l10n.authSignOutConfirmDesc),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(l10n.cancel),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(l10n.authSignOut,
                              style: TextStyle(color: cs.error)),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) await AuthService.signOut();
                },
                icon: Icon(Icons.logout, size: 18, color: cs.error),
                label: Text(l10n.authSignOut,
                    style: GoogleFonts.inter(
                        fontSize: 14, color: cs.error)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: cs.outlineVariant),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ] else ...[
            Text(
              l10n.settingsAccountNotSignedIn,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => context.push('/auth/login'),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(l10n.settingsAccountManage,
                    style: GoogleFonts.inter(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── QR scanner screen ────────────────────────────────────────────────────────

class _QrScannerScreen extends StatefulWidget {
  const _QrScannerScreen();

  @override
  State<_QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<_QrScannerScreen> {
  final MobileScannerController _ctrl = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    _handled = true;

    // Accept both "logbook://join/CODE" deep links and raw 8-char codes.
    const scheme = 'logbook://join/';
    final code = raw.startsWith(scheme) ? raw.substring(scheme.length) : raw;
    Navigator.pop(context, code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), ''));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l10n.settingsScanTitle,
          style: GoogleFonts.inter(color: Colors.white, fontSize: 16),
        ),
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(controller: _ctrl, onDetect: _onDetect),
          // Viewfinder overlay
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white54, width: 2),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ],
      ),
    );
  }
}
