import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/route_names.dart';
import '../../../app/theme/theme_extensions.dart';
import '../../../core/widgets/card_shell.dart';
import '../../../core/widgets/nav_bar.dart';
import '../../../l10n/l10n_extension.dart';

/// Static reference guide for non-radio distress signals (pyrotechnics, hand
/// signals, flag "NC", sound signals, EPIRB/SART), ending with a card
/// linking into the live MAYDAY radio-protocol checklist. Purely
/// informational — no user data is read or written on this screen.
class EmergencyScreen extends StatelessWidget {
  const EmergencyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: cs.primary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          l10n.emergencyGuideTitle,
          style: Theme.of(context).textTheme.dialogTitle.copyWith(fontWeight: FontWeight.w600, color: cs.primary),
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
          Text(
            l10n.emergencyGuideIntro,
            style: Theme.of(context).textTheme.fieldHintCompact.copyWith(height: 1.6, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 20),

          // -- Visual signals section: pyrotechnic + hand-signal cards, flag NC --
          _SectionHeader(title: l10n.emergencyVisualSignals),
          const SizedBox(height: 12),
          const IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _PyrotechnicCard()),
                SizedBox(width: 12),
                Expanded(child: _HandSignalCard()),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const _FlagSignalCard(),
          const SizedBox(height: 20),
          // -- end visual signals section --

          // -- Sound signals section: gunshot + foghorn cards --
          _SectionHeader(title: l10n.emergencySoundSignals),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _SoundCard(
                  icon: Icons.crisis_alert,
                  title: l10n.emergencyGunTitle,
                  subtitle: l10n.emergencyGunSubtitle,
                  watermarkIcon: Icons.volume_up,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SoundCard(
                  icon: Icons.air,
                  title: l10n.emergencyFoghornTitle,
                  subtitle: l10n.emergencyFoghornSubtitle,
                  watermarkIcon: Icons.campaign,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // -- end sound signals section --

          // -- Electronic signals section: EPIRB + SART items --
          _SectionHeader(title: l10n.emergencyElectronicSignals),
          const SizedBox(height: 12),
          Column(
            children: [
              _ElectronicItem(
                icon: Icons.satellite_alt,
                iconBg: cs.secondaryContainer,
                iconColor: cs.onSecondaryContainer,
                title: l10n.emergencyEpirbTitle,
                subtitle: l10n.emergencyEpirbSubtitle,
              ),
              const SizedBox(height: 12),
              _ElectronicItem(
                icon: Icons.radar,
                iconBg: cs.primaryContainer,
                iconColor: cs.onPrimaryContainer,
                title: l10n.emergencySartTitle,
                subtitle: l10n.emergencySartSubtitle,
              ),
            ],
          ),
          const SizedBox(height: 20),
          // -- end electronic signals section --

          // -- MAYDAY radio-protocol CTA card --
          const _MaydayCard(),
        ],
      ),
    );
  }
}

/// Small-caps eyebrow label used above each signal-type section on this screen.
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall!.copyWith(
        color: cs.secondary,
      ),
    );
  }
}

/// Opens [assetPath] full-screen, pannable/zoomable, dismissed by tapping
/// anywhere — same pattern as day_detail_screen.dart's photo viewer.
void _viewImage(BuildContext context, String assetPath) {
  showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.zero,
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: InteractiveViewer(
          child: Image.asset(assetPath),
        ),
      ),
    ),
  );
}

/// Flares/rocket-signal reference card (left half of the visual-signals row).
class _PyrotechnicCard extends StatelessWidget {
  const _PyrotechnicCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return _SignalCard(
      stripeColor: cs.error,
      icon: Icons.local_fire_department,
      iconColor: cs.error,
      badge: l10n.emergencyHighVisBadge,
      badgeBg: cs.errorContainer,
      badgeFg: cs.onErrorContainer,
      title: l10n.emergencyPyrotechnicTitle,
      subtitle: l10n.emergencyPyrotechnicSubtitle,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: GestureDetector(
          onTap: () => _viewImage(context, 'assets/images/distress/pyrotechnic.png'),
          child: Stack(
            children: [
              Image.asset(
                'assets/images/distress/pyrotechnic.png',
                height: 100,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
              Positioned(
                bottom: 4,
                right: 6,
                child: Text(
                  'edtech.com.sg',
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    fontSize: 7,
                    letterSpacing: 0,
                    color: Colors.white.withValues(alpha: 0.75),
                    shadows: const [Shadow(blurRadius: 2, color: Colors.black54)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Arms-raised distress hand-signal reference card (right half of the
/// visual-signals row).
class _HandSignalCard extends StatelessWidget {
  const _HandSignalCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return _SignalCard(
      stripeColor: cs.primary,
      icon: Icons.accessibility_new,
      iconColor: cs.primary,
      title: l10n.emergencyHandSignalTitle,
      subtitle: l10n.emergencyHandSignalSubtitle,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: GestureDetector(
          onTap: () => _viewImage(context, 'assets/images/distress/hand_signal.png'),
          child: Image.asset(
            'assets/images/distress/hand_signal.png',
            height: 100,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

/// Shared card shell for [_PyrotechnicCard]/[_HandSignalCard]: a colored
/// left stripe, icon + optional badge header row, title/subtitle, then a
/// slot for an illustration ([child]).
class _SignalCard extends StatelessWidget {
  final Color stripeColor;
  final IconData icon;
  final Color iconColor;
  final String? badge;
  final Color? badgeBg;
  final Color? badgeFg;
  final String title;
  final String subtitle;
  final Widget child;

  const _SignalCard({
    required this.stripeColor,
    required this.icon,
    required this.iconColor,
    this.badge,
    this.badgeBg,
    this.badgeFg,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CardShell(
      backgroundColor: cs.surfaceContainerLow,
      accentColor: stripeColor,
      bordered: true,
      shadowed: true,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 24),
                const Spacer(),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      badge!,
                      style: Theme.of(context).textTheme.microLabel.copyWith(letterSpacing: 0.5, color: badgeFg),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                color: cs.onSurfaceVariant,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
            const Spacer(),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

/// Flag "NC" (International Code of Signals distress flag) reference card.
class _FlagSignalCard extends StatelessWidget {
  const _FlagSignalCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CardShell(
      backgroundColor: cs.surfaceContainerLow,
      accentColor: cs.primary,
      bordered: true,
      shadowed: true,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flag, color: cs.primary, size: 24),
                const Spacer(),
                Text(
                  'Code: NC',
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(letterSpacing: 0, color: cs.primary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.emergencyFlagSignalTitle,
                        style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.l10n.emergencyFlagSignalSubtitle,
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                          color: cs.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.asset(
                    'assets/images/distress/flag_nc.png',
                    height: 64,
                    width: 80,
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


/// Compact card for one sound-signal method (gunshot / foghorn), with a
/// faint oversized watermark icon in the background corner.
class _SoundCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final IconData watermarkIcon;

  const _SoundCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.watermarkIcon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Stack(
        children: [
          Positioned(
            bottom: -16,
            right: -16,
            child: Icon(watermarkIcon, size: 80, color: cs.primary.withValues(alpha: 0.04)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: cs.primary, size: 24),
              const SizedBox(height: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall!.copyWith(fontSize: 11, height: 1.4, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Row-style list item for one electronic distress device (EPIRB / SART):
/// a colored icon tile plus title/subtitle.
class _ElectronicItem extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;

  const _ElectronicItem({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Prominent closing card that hands off from this static reference guide
/// into the live, step-by-step MAYDAY radio-protocol screen.
class _MaydayCard extends StatelessWidget {
  const _MaydayCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            bottom: -8,
            right: 8,
            child: Icon(Icons.anchor, size: 80, color: Colors.white.withValues(alpha: 0.05)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.radio, color: cs.secondary, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.emergencyRadioProtocolLabel,
                      style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                // MAYDAY within tip text is part of the instruction — kept as protocol reference
                l10n.emergencyRadioProtocolTip,
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: Colors.white.withValues(alpha: 0.8),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => context.pushNamed(AppRoute.mayday),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.secondary,
                    foregroundColor: cs.onSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const StadiumBorder(),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.launch, size: 18),
                  label: Text(
                    l10n.emergencyOpenChecklist,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
