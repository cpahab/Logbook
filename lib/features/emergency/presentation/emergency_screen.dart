import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../home/widgets/nav_bar.dart';

class EmergencyScreen extends StatelessWidget {
  const EmergencyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        foregroundColor: cs.primary,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.black12,
        centerTitle: false,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: cs.primary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Distress Signal Guide',
          style: GoogleFonts.newsreader(
            color: cs.primary,
            fontSize: 22,
            fontWeight: FontWeight.w600,
            fontStyle: FontStyle.italic,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.account_circle_outlined, color: cs.primary),
            onPressed: () {},
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        active: NavTab.safety,
        showFab: false,
        onSelect: (tab) {
          if (tab == NavTab.journal) context.go('/');
          if (tab == NavTab.map) context.push('/tracks');
          if (tab == NavTab.settings) context.push('/settings');
        },
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Text(
            'Quick reference guide for International Maritime Distress Signals. Ensure visibility and clear communication during an emergency.',
            style: GoogleFonts.inter(
              fontSize: 15,
              height: 1.6,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          const _SectionHeader(title: 'Visual Signals'),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Expanded(child: _PyrotechnicCard()),
              SizedBox(width: 12),
              Expanded(child: _HandSignalCard()),
            ],
          ),
          const SizedBox(height: 12),
          const _FlagSignalCard(),
          const SizedBox(height: 20),
          const _SectionHeader(title: 'Sound Signals'),
          const SizedBox(height: 12),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _SoundCard(
                  icon: Icons.crisis_alert,
                  title: 'Gun/Explosive',
                  subtitle: 'Fired at intervals of about a minute.',
                  watermarkIcon: Icons.volume_up,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _SoundCard(
                  icon: Icons.air,
                  title: 'Foghorn',
                  subtitle: 'Continuous sounding with any fog-signaling apparatus.',
                  watermarkIcon: Icons.campaign,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const _SectionHeader(title: 'Electronic Signals'),
          const SizedBox(height: 12),
          Builder(builder: (context) {
            final cs = Theme.of(context).colorScheme;
            return Column(
              children: [
                _ElectronicItem(
                  icon: Icons.satellite_alt,
                  iconBg: cs.secondaryContainer,
                  iconColor: cs.onSecondaryContainer,
                  title: 'EPIRB / PLB',
                  subtitle:
                      'Emergency Position Indicating Radio Beacon. Signals 406MHz to COSPAS-SARSAT satellites.',
                ),
                const SizedBox(height: 12),
                _ElectronicItem(
                  icon: Icons.radar,
                  iconBg: cs.primaryContainer,
                  iconColor: cs.onPrimaryContainer,
                  title: 'SART',
                  subtitle:
                      'Search and Rescue Transponder. Shows as a line of 12 dots on nearby X-band radars.',
                ),
              ],
            );
          }),
          const SizedBox(height: 20),
          const _MaydayCard(),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      title.toUpperCase(),
      style: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
        color: cs.outline,
      ),
    );
  }
}

class _PyrotechnicCard extends StatelessWidget {
  const _PyrotechnicCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _SignalCard(
      stripeColor: cs.error,
      icon: Icons.local_fire_department,
      iconColor: cs.error,
      badge: 'HIGH VIS',
      badgeBg: cs.errorContainer,
      badgeFg: cs.onErrorContainer,
      title: 'Pyrotechnic Signals',
      subtitle: 'Red flare (handheld/parachute) or Orange smoke.',
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Icon(
            Icons.local_fire_department,
            size: 40,
            color: cs.error.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}

class _HandSignalCard extends StatelessWidget {
  const _HandSignalCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _SignalCard(
      stripeColor: cs.primary,
      icon: Icons.accessibility_new,
      iconColor: cs.primary,
      title: 'Hand Signals',
      subtitle: 'Slowly and repeatedly raising and lowering arms outstretched to each side.',
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Center(
          child: Icon(Icons.pan_tool, size: 40, color: cs.outlineVariant),
        ),
      ),
    );
  }
}

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
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Positioned(
              left: 0, top: 0, bottom: 0,
              child: Container(width: 4, color: stripeColor),
            ),
            Padding(
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
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: badgeFg,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: GoogleFonts.newsreader(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  child,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlagSignalCard extends StatelessWidget {
  const _FlagSignalCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Positioned(
              left: 0, top: 0, bottom: 0,
              child: Container(width: 4, color: cs.primary),
            ),
            Padding(
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
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: cs.primary,
                        ),
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
                              'Flag Signals',
                              style: GoogleFonts.newsreader(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Square flag having above or below it a ball or anything resembling a ball, or flags November over Charlie.',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Row(
                        children: [
                          _FlagTile(letter: 'N', bg: Color(0xFF1A237E), fg: Colors.white),
                          SizedBox(width: 6),
                          _FlagTile(letter: 'C', bg: Colors.white, fg: Color(0xFF1A237E)),
                        ],
                      ),
                    ],
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

class _FlagTile extends StatelessWidget {
  final String letter;
  final Color bg;
  final Color fg;
  const _FlagTile({required this.letter, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 36,
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: const Color(0xFF73777F)),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

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
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

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
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: cs.outlineVariant),
        ],
      ),
    );
  }
}

class _MaydayCard extends StatelessWidget {
  const _MaydayCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
                  Icon(Icons.radio, color: cs.secondaryFixed, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Radio Protocol (MAYDAY)',
                      style: GoogleFonts.newsreader(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'VHF Channel 16. State "MAYDAY" three times, followed by Vessel Name and Position.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.8),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => context.push('/emergency/mayday'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.secondaryFixed,
                    foregroundColor: cs.onSecondaryFixed,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const StadiumBorder(),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.launch, size: 18),
                  label: Text(
                    'OPEN RADIO CHECKLIST',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
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
