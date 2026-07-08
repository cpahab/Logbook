import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../home/data/home_repository.dart';
import '../../home/widgets/nav_bar.dart';
import '../../settings/domain/theme_provider.dart';
import '../../../app/route_names.dart';
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
          context.l10n.emergencyRadioProtocolLabel,
          style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontSize: 18, fontWeight: FontWeight.w600, color: cs.onError),
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        active: NavTab.safety,
        showFab: false,
        onSelect: (tab) {
          if (tab == NavTab.journal) context.goNamed(AppRoute.home);
          if (tab == NavTab.map) context.goNamed(AppRoute.tracks);
          if (tab == NavTab.settings) context.goNamed(AppRoute.settings);
        },
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
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
        Divider(color: em.criticalMutedColor, thickness: 2),
        const SizedBox(height: 4),
        Text(
          l10n.emergencyFollowScript,
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontStyle: FontStyle.italic, fontWeight: FontWeight.w500, height: 1.5, color: cs.onSurfaceVariant),
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
                      color: em.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.crisis_alert, color: em.onErrorContainer, size: 22),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          // Maritime protocol step label — kept in English per SOLAS/IMO standard
                          'STEP 1: DSC DISTRESS ALERT',
                          style: Theme.of(context).textTheme.labelSmall!.copyWith(letterSpacing: 2, color: em.criticalColor),
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
                            color: em.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.arrow_forward,
                                  size: 14, color: em.onErrorContainer),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  l10n.emergencyDscWait,
                                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontSize: 13, fontWeight: FontWeight.w500, color: em.onErrorContainer),
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
              style: Theme.of(context).textTheme.labelSmall!.copyWith(letterSpacing: 0, color: em.criticalColor),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w600, height: 1.3, color: cs.onSurface),
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
                      color: em.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.radio, color: em.onErrorContainer, size: 22),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          // Protocol step labels and radio script kept in English — international maritime standard (SOLAS/IMO)
                          'STEP 2: SIGNAL',
                          style: Theme.of(context).textTheme.labelSmall!.copyWith(letterSpacing: 2, color: em.criticalColor),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'MAYDAY, MAYDAY, MAYDAY',
                          style: Theme.of(context).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5, height: 1.2, color: cs.onSurface),
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
      iconBg: cs.errorContainer,
      iconColor: cs.onErrorContainer,
      borderColor: cs.error,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.emergencyIdentifyVessel,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface),
              children: [
                const TextSpan(text: 'THIS IS YACHT '),
                _spokenValueSpan(vesselName, cs),
                const TextSpan(text: ' '),
                _spokenValueSpan(vesselName, cs),
                const TextSpan(text: ' '),
                _spokenValueSpan(vesselName, cs),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.maydayStateThreeTimes,
            style: Theme.of(context).textTheme.bodySmall!.copyWith(fontSize: 11, fontStyle: FontStyle.italic, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface),
              children: [
                const TextSpan(text: 'CALLSIGN '),
                _spokenValueSpan(callSign, cs),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface),
              children: [
                const TextSpan(text: 'MMSI '),
                _spokenValueSpan(mmsi, cs),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface),
              children: [
                const TextSpan(text: 'MAYDAY '),
                _spokenValueSpan(vesselName, cs),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Style for a "must be spoken" fill-in value (vessel name, callsign, MMSI,
/// position, crew count, nature of distress) — always red + underlined,
/// distinct from the plain/white fixed script phrases around it, so every
/// piece of the radio script that varies per-boat/per-situation reads
/// consistently regardless of which step it's in.
TextSpan _spokenValueSpan(String text, ColorScheme cs) => TextSpan(
      text: text,
      style: TextStyle(
        color: cs.error,
        decoration: TextDecoration.underline,
        decorationColor: cs.error.withValues(alpha: 0.4),
        decorationThickness: 2,
      ),
    );

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
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600, fontStyle: FontStyle.italic, color: em.criticalColor),
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
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontStyle: FontStyle.italic, color: cs.onSurfaceVariant),
          ),
        ],
      );
    } else {
      positionWidget = Row(
        children: [
          Icon(Icons.gps_fixed, size: 16, color: cs.error),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              positionText!,
              style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: cs.error,
                decoration: TextDecoration.underline,
                decorationColor: cs.error.withValues(alpha: 0.4),
                decorationThickness: 2,
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
      iconBg: cs.errorContainer,
      iconColor: cs.onErrorContainer,
      borderColor: cs.error,
      watermarkIcon: Icons.explore,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'POSITION: ',
            style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface),
          ),
          Expanded(child: positionWidget),
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
                      color: em.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.local_fire_department, color: em.onErrorContainer, size: 22),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'STEP 5: NATURE OF DISTRESS',
                          style: Theme.of(context).textTheme.labelSmall!.copyWith(letterSpacing: 2, color: em.criticalColor),
                        ),
                        const SizedBox(height: 4),
                        Text.rich(
                          TextSpan(
                            style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
                            children: [_spokenValueSpan(options[selectedIndex], cs)],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (var i = 0; i < options.length; i++)
                              if (i != selectedIndex)
                                GestureDetector(
                                  onTap: () => onSelect(i),
                                  child: Text(
                                    '(${options[i]})',
                                    style: Theme.of(context).textTheme.chipLabel.copyWith(color: cs.onSurfaceVariant),
                                  ),
                                ),
                          ],
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
      iconBg: cs.errorContainer,
      iconColor: cs.onErrorContainer,
      borderColor: cs.error,
      child: Text.rich(
        TextSpan(
          style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontSize: 20, fontWeight: FontWeight.w700, color: cs.onSurface),
          children: [
            const TextSpan(text: 'NUMBER OF PERSONS ON BOARD: '),
            _spokenValueSpan(
              crewCount > 0 ? crewCount.toString().padLeft(2, '0') : '—',
              cs,
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
    return _StepCard(
      step: 7,
      label: 'CLOSING',
      icon: Icons.mic,
      iconBg: cs.errorContainer,
      iconColor: cs.onErrorContainer,
      borderColor: cs.error,
      child: Text(
        'OVER',
        style: Theme.of(context).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface),
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
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(letterSpacing: 2, color: cs.error),
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
                style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontSize: 17, fontWeight: FontWeight.w600, color: cs.onSurface),
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
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(height: 1.5, color: cs.onSurfaceVariant),
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
