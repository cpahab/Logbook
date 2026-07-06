import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../home/data/home_repository.dart';
import '../../home/widgets/nav_bar.dart';
import '../../settings/domain/theme_provider.dart';
import '../../../app/theme/theme_extensions.dart';
import '../../../core/services/gps_consent_service.dart';
import '../../../l10n/l10n_extension.dart';

class MaydayScreen extends StatefulWidget {
  const MaydayScreen({super.key});

  @override
  State<MaydayScreen> createState() => _MaydayScreenState();
}

class _MaydayScreenState extends State<MaydayScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;
  int _selectedDistress = 0;

  String? _positionText;  // null = still acquiring
  bool _positionError = false;

  static const _distressOptions = ['SINKING / FLOODING', 'FIRE', 'ABANDONING SHIP'];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await GpsConsentService.requestIfNeeded(context);
      if (mounted) _acquirePosition();
    });
  }

  Future<void> _acquirePosition() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        if (mounted) setState(() => _positionError = true);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (mounted) {
        setState(() => _positionText = _formatDDM(pos.latitude, pos.longitude));
      }
    } catch (_) {
      if (mounted) setState(() => _positionError = true);
    }
  }

  /// Formats decimal degrees as nautical DDM: "N 47° 30.456'  E 008° 18.123'"
  static String _formatDDM(double lat, double lng) {
    String ddm(double val, List<String> dirs) {
      final dir = val >= 0 ? dirs[0] : dirs[1];
      final abs = val.abs();
      final deg = abs.truncate();
      final min = (abs - deg) * 60;
      return "$dir ${deg.toString().padLeft(dirs[0] == 'N' ? 2 : 3, '0')}° ${min.toStringAsFixed(3)}'";
    }
    return '${ddm(lat, ['N', 'S'])}  ${ddm(lng, ['E', 'W'])}';
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final em = cs;
    final vessel = context.watch<ThemeProvider>();
    final today = DateTime.now();
    final homeRepo = context.read<HomeRepository>();
    final todayCrew = homeRepo.getEntry(today)?.crew ?? [];
    final crewCount = todayCrew.isNotEmpty ? todayCrew.length : homeRepo.lastCrew.length;

    final vesselName = vessel.vesselName.isNotEmpty ? vessel.vesselName : '—';
    final callSign = vessel.vesselCallSign.isNotEmpty ? vessel.vesselCallSign : '—';
    final mmsi = vessel.vesselMmsi.isNotEmpty ? vessel.vesselMmsi : '—';

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: em.criticalColor,
        foregroundColor: cs.onError,
        elevation: 2,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: cs.onError),
          onPressed: () => context.pop(),
        ),
        title: Text(
          context.l10n.maydayScreenTitle,
          style: GoogleFonts.dmSans(
            color: cs.onError,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        active: NavTab.safety,
        showFab: false,
        onSelect: (tab) {
          if (tab == NavTab.journal) context.go('/');
          if (tab == NavTab.map) context.go('/tracks');
          if (tab == NavTab.settings) context.go('/settings');
        },
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          // Distress Signal Guide link
          _DistressSignalCard(),
          const SizedBox(height: 16),

          // Procedure header
          _ProcedureHeader(),
          const SizedBox(height: 16),

          // Steps
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, _) => _StepDsc(pulseValue: _pulseAnim.value),
          ),
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, _) => _StepSignal(pulseValue: _pulseAnim.value),
          ),
          const SizedBox(height: 12),
          _StepIdentification(
            vesselName: vesselName,
            callSign: callSign,
            mmsi: mmsi,
          ),
          const SizedBox(height: 12),
          _StepPosition(
            positionText: _positionText,
            positionError: _positionError,
          ),
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, _) => _StepDistress(
              pulseValue: _pulseAnim.value,
              selectedIndex: _selectedDistress,
              options: _distressOptions,
              onSelect: (i) => setState(() => _selectedDistress = i),
            ),
          ),
          const SizedBox(height: 12),
          _StepCrew(crewCount: crewCount),
          const SizedBox(height: 12),
          const _StepClosing(),
          const SizedBox(height: 20),

          // Tips
          const _TipsSection(),
        ],
      ),
    );
  }
}

// ─── Distress Signal Guide card ───────────────────────────────────────────────

class _DistressSignalCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final em = cs;
    final l10n = context.l10n;
    return GestureDetector(
      onTap: () => context.push('/emergency/distress'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: em.cardShadowColor,
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.menu_book, color: cs.onPrimaryContainer, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.emergencyGuideTitle,
                    style: GoogleFonts.dmSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  Text(
                    l10n.emergencyDistressGuideSubtitle,
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: cs.outlineVariant),
          ],
        ),
      ),
    );
  }
}

// ─── Procedure Header ─────────────────────────────────────────────────────────

class _ProcedureHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final em = cs;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.emergency, color: em.criticalColor, size: 20),
            const SizedBox(width: 8),
            Text(
              l10n.emergencyUrgentProcedure,
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2.4,
                color: em.criticalColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          // "MAYDAY" in the title is the international distress call — kept as protocol reference
          l10n.emergencyRadioProtocolLabel,
          style: GoogleFonts.dmSans(
            fontSize: 36,
            fontWeight: FontWeight.w700,
            color: em.criticalColor,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 6),
        Divider(color: em.criticalMutedColor, thickness: 2),
        const SizedBox(height: 4),
        Text(
          l10n.emergencyFollowScript,
          style: GoogleFonts.dmSans(
            fontSize: 14,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w500,
            color: cs.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

// ─── Step helpers ─────────────────────────────────────────────────────────────

class _StepDsc extends StatelessWidget {
  final double pulseValue;
  const _StepDsc({required this.pulseValue});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final em = cs;
    final l10n = context.l10n;
    final borderOpacity = 0.3 + 0.7 * (1 - pulseValue);
    final shadowBlur = 10 * (1 - pulseValue);
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: em.criticalColor.withValues(alpha: borderOpacity),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: em.criticalColor.withValues(alpha: 0.2 * (1 - pulseValue)),
            blurRadius: shadowBlur,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Stack(
          children: [
            Positioned(
              left: 0, top: 0, bottom: 0,
              child: Container(width: 6, color: em.criticalColor),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: em.criticalColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.crisis_alert, color: cs.onError, size: 22),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          // Maritime protocol step label — kept in English per SOLAS/IMO standard
                          'STEP 1: DSC DISTRESS ALERT',
                          style: GoogleFonts.dmSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                            color: em.criticalColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _DscAction(
                          number: '1',
                          text: l10n.emergencyDscAction1,
                        ),
                        const SizedBox(height: 6),
                        _DscAction(
                          number: '2',
                          text: l10n.emergencyDscAction2,
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: cs.secondaryContainer.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.arrow_forward,
                                  size: 14, color: cs.secondary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  l10n.emergencyDscWait,
                                  style: GoogleFonts.dmSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: cs.onSecondaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DscAction extends StatelessWidget {
  final String number;
  final String text;
  const _DscAction({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final em = cs;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: em.criticalColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: em.criticalColor,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _StepSignal extends StatelessWidget {
  final double pulseValue;
  const _StepSignal({required this.pulseValue});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final em = cs;
    final borderOpacity = 0.3 + 0.7 * (1 - pulseValue);
    final shadowBlur = 10 * (1 - pulseValue);
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: em.criticalColor.withValues(alpha: borderOpacity),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: em.criticalColor.withValues(alpha: 0.2 * (1 - pulseValue)),
            blurRadius: shadowBlur,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Stack(
          children: [
            Positioned(
              left: 0, top: 0, bottom: 0,
              child: Container(width: 6, color: em.criticalColor),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 16, 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: em.criticalColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.radio, color: cs.onError, size: 22),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          // Protocol step labels and radio script kept in English — international maritime standard (SOLAS/IMO)
                          'STEP 2: SIGNAL',
                          style: GoogleFonts.dmSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                            color: em.criticalColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'MAYDAY, MAYDAY, MAYDAY',
                          style: GoogleFonts.dmSans(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                            letterSpacing: -0.5,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepIdentification extends StatelessWidget {
  final String vesselName;
  final String callSign;
  final String mmsi;
  const _StepIdentification({
    required this.vesselName,
    required this.callSign,
    required this.mmsi,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return _StepCard(
      step: 3,
      // "IDENTIFICATION" is a protocol step label — kept in English per SOLAS/IMO standard
      label: 'IDENTIFICATION',
      icon: Icons.sailing,
      iconBg: cs.secondaryContainer,
      iconColor: cs.onSecondaryContainer,
      borderColor: cs.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.emergencyIdentifyVessel,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              style: GoogleFonts.dmSans(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
              children: [
                const TextSpan(text: 'THIS IS YACHT '),
                _underlinedSpan(vesselName, cs),
                const TextSpan(text: ' '),
                _underlinedSpan(vesselName, cs),
                const TextSpan(text: ' '),
                _underlinedSpan(vesselName, cs),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.maydayStateThreeTimes,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              style: GoogleFonts.dmSans(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
              children: [
                const TextSpan(text: 'CALLSIGN '),
                _underlinedSpan(callSign, cs),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              style: GoogleFonts.dmSans(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
              children: [
                const TextSpan(text: 'MMSI '),
                _underlinedSpan(mmsi, cs),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              style: GoogleFonts.dmSans(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
              children: [
                const TextSpan(text: 'MAYDAY '),
                _underlinedSpan(vesselName, cs),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TextSpan _underlinedSpan(String text, ColorScheme cs) => TextSpan(
        text: text,
        style: TextStyle(
          color: cs.primary,
          decoration: TextDecoration.underline,
          decorationColor: cs.primary.withValues(alpha: 0.4),
          decorationThickness: 2,
        ),
      );
}

class _StepPosition extends StatelessWidget {
  final String? positionText;
  final bool positionError;

  const _StepPosition({
    required this.positionText,
    required this.positionError,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final em = cs;
    final l10n = context.l10n;

    final Widget positionWidget;
    if (positionError) {
      positionWidget = Row(
        children: [
          Icon(Icons.gps_off, size: 16, color: em.criticalColor),
          const SizedBox(width: 8),
          Text(
            l10n.emergencyPositionUnavailable,
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: em.criticalColor,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );
    } else if (positionText == null) {
      positionWidget = Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: cs.primary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            l10n.emergencyAcquiringGps,
            style: GoogleFonts.dmSans(
              fontSize: 14,
              color: cs.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );
    } else {
      positionWidget = Row(
        children: [
          Icon(Icons.gps_fixed, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              positionText!,
              style: GoogleFonts.dmSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      );
    }

    return _StepCard(
      step: 4,
      label: 'POSITION',
      icon: Icons.location_on,
      iconBg: cs.secondaryContainer,
      iconColor: cs.onSecondaryContainer,
      borderColor: cs.secondary,
      watermarkIcon: Icons.explore,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'POSITION:',
            style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: positionText != null
                  ? cs.primaryContainer.withValues(alpha: 0.4)
                  : cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: positionText != null
                    ? cs.primary.withValues(alpha: 0.3)
                    : cs.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: positionWidget,
          ),
        ],
      ),
    );
  }
}

class _StepDistress extends StatelessWidget {
  final double pulseValue;
  final int selectedIndex;
  final List<String> options;
  final ValueChanged<int> onSelect;

  const _StepDistress({
    required this.pulseValue,
    required this.selectedIndex,
    required this.options,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final em = cs;
    final borderOpacity = 0.3 + 0.7 * (1 - pulseValue);
    final shadowBlur = 10 * (1 - pulseValue);

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: em.criticalColor.withValues(alpha: borderOpacity),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: em.criticalColor.withValues(alpha: 0.2 * (1 - pulseValue)),
            blurRadius: shadowBlur,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Stack(
          children: [
            Positioned(
              left: 0, top: 0, bottom: 0,
              child: Container(width: 6, color: em.criticalColor),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: em.criticalColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.local_fire_department, color: cs.onError, size: 22),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'STEP 5: NATURE OF DISTRESS',
                          style: GoogleFonts.dmSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                            color: em.criticalColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'NATURE OF DISTRESS:',
                          style: GoogleFonts.dmSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: List.generate(options.length, (i) {
                            final selected = i == selectedIndex;
                            return GestureDetector(
                              onTap: () => onSelect(i),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: selected ? em.criticalColor : cs.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  options[i],
                                  style: GoogleFonts.dmSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: selected ? cs.onError : cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepCrew extends StatelessWidget {
  final int crewCount;
  const _StepCrew({required this.crewCount});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _StepCard(
      step: 6,
      // IMO GMDSS protocol term — kept in English per SOLAS/IMO standard.
      label: 'CREW STATUS',
      icon: Icons.groups,
      iconBg: cs.secondaryContainer,
      iconColor: cs.onSecondaryContainer,
      borderColor: cs.secondary,
      child: Text.rich(
        TextSpan(
          style: GoogleFonts.dmSans(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
          children: [
            const TextSpan(text: 'NUMBER OF PERSONS ON BOARD: '),
            TextSpan(
              text: crewCount > 0
                  ? crewCount.toString().padLeft(2, '0')
                  : '—',
              style: TextStyle(
                color: cs.primary,
                decoration: TextDecoration.underline,
                decorationColor: cs.primary.withValues(alpha: 0.4),
                decorationThickness: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepClosing extends StatelessWidget {
  const _StepClosing();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: cs.onPrimaryContainer, width: 6),
        ),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.onPrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.mic, color: cs.onPrimary, size: 22),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'STEP 7: CLOSING',
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: cs.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'OVER',
                style: GoogleFonts.dmSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: cs.onPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Reusable step card ───────────────────────────────────────────────────────

class _StepCard extends StatelessWidget {
  final int step;
  final String label;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final Color borderColor;
  final IconData? watermarkIcon;
  final Widget child;

  const _StepCard({
    required this.step,
    required this.label,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.borderColor,
    this.watermarkIcon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: borderColor, width: 4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          if (watermarkIcon != null)
            Positioned(
              right: -12,
              top: -12,
              child: Icon(
                watermarkIcon,
                size: 100,
                color: cs.onSurface.withValues(alpha: 0.04),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'STEP $step: $label',
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    child,
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Tips section ─────────────────────────────────────────────────────────────

class _TipsSection extends StatelessWidget {
  const _TipsSection();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.secondary.withValues(alpha: 0.2),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tips_and_updates, color: cs.secondary, size: 22),
              const SizedBox(width: 8),
              Text(
                l10n.emergencyCriticalTips,
                style: GoogleFonts.dmSans(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Tip(
            title: l10n.emergencyTipCalmTitle,
            body: l10n.emergencyTipCalmBody,
          ),
          const SizedBox(height: 10),
          _Tip(
            title: l10n.emergencyTipEnunciateTitle,
            body: l10n.emergencyTipEnunciateBody,
          ),
          const SizedBox(height: 10),
          _Tip(
            title: l10n.emergencyTipListenTitle,
            body: l10n.emergencyTipListenBody,
          ),
        ],
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  final String title;
  final String body;
  const _Tip({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_circle, color: cs.secondary, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: GoogleFonts.dmSans(
                fontSize: 14,
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
              children: [
                TextSpan(
                  text: '$title ',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                TextSpan(text: body),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
