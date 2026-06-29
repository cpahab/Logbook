import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../home/data/home_repository.dart';
import '../../home/domain/crew_member.dart';
import '../../home/widgets/nav_bar.dart';
import '../../settings/domain/theme_provider.dart';
import '../../../l10n/l10n_extension.dart';
import '../../../app/theme/theme_extensions.dart';
import '../data/emergency_repository.dart';
import '../domain/emergency_contact.dart';

class EmergencyManifestScreen extends StatefulWidget {
  const EmergencyManifestScreen({super.key});

  @override
  State<EmergencyManifestScreen> createState() => _EmergencyManifestScreenState();
}

class _EmergencyManifestScreenState extends State<EmergencyManifestScreen> {
  bool _editMode = false;

  void _showAddContactDialog() {
    final repo = context.read<EmergencyRepository>();
    showDialog<EmergencyContact>(
      context: context,
      builder: (_) => const _AddContactDialog(),
    ).then((contact) {
      if (contact != null) repo.addContact(contact);
    });
  }

  void _showAddFrequencyDialog() {
    final vessel = context.read<ThemeProvider>();
    final labels = [vessel.vhf1Label, vessel.vhf2Label, vessel.vhf3Label, vessel.vhf4Label];
    final nextSlot = labels.indexWhere((l) => l.isEmpty) + 1;
    if (nextSlot == 0) return;
    showDialog<({String label, String desc})?>(
      context: context,
      builder: (_) => const _AddFrequencyDialog(),
    ).then((result) {
      if (result != null) vessel.setVhfEntry(nextSlot, result.label, result.desc);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final em = Theme.of(context).extension<LogbookEmergencyColors>()!;
    final l10n = context.l10n;
    final vessel = context.watch<ThemeProvider>();
    final emergency = context.watch<EmergencyRepository>();
    final today = DateTime.now();
    final homeRepo = context.read<HomeRepository>();
    final todayCrew = homeRepo.getEntry(today)?.crew ?? [];
    final crew = todayCrew.isNotEmpty ? todayCrew : homeRepo.lastCrew;

    final vhfLabels = [vessel.vhf1Label, vessel.vhf2Label, vessel.vhf3Label, vessel.vhf4Label];
    final canAddFrequency = vhfLabels.any((l) => l.isEmpty);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          l10n.emergencyManifestTitle.toUpperCase(),
          style: GoogleFonts.newsreader(
            color: cs.primary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _editMode ? Icons.check_rounded : Icons.edit_outlined,
              color: _editMode ? cs.primary : cs.onSurfaceVariant,
            ),
            tooltip: _editMode ? l10n.emergencyManifestEditDoneTooltip : l10n.emergencyManifestEditPageTooltip,
            onPressed: () => setState(() => _editMode = !_editMode),
          ),
        ],
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
          // ── Quick Actions ───────────────────────────────────────────────────
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _QuickActionCard(
                  label: l10n.emergencyProtocolBadge,
                  title: l10n.emergencyRadioProtocolShort,
                  icon: Icons.record_voice_over,
                  iconBg: cs.primary,
                  iconFg: cs.onPrimary,
                  borderColor: cs.primary,
                  cardBg: cs.surfaceContainerLowest,
                  trailingIcon: Icons.arrow_forward_ios,
                  trailingColor: cs.primary,
                  onTap: () => context.push('/emergency/mayday'),
                )),
                const SizedBox(width: 12),
                Expanded(child: _QuickActionCard(
                  label: l10n.emergencyVisualAidBadge,
                  title: l10n.emergencyGuideShort,
                  icon: Icons.sos,
                  iconBg: em.criticalColor,
                  iconFg: cs.onError,
                  borderColor: em.criticalColor,
                  cardBg: em.criticalBgColor,
                  trailingIcon: Icons.flare,
                  trailingColor: em.criticalColor,
                  onTap: () => context.push('/emergency/distress'),
                )),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Emergency Contacts ──────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SectionHeader(icon: Icons.contact_emergency, label: l10n.emergencyContactsSection),
              if (_editMode)
                _AddIconButton(onTap: _showAddContactDialog),
            ],
          ),
          const SizedBox(height: 8),
          _ContactsCard(contacts: emergency.contacts, editMode: _editMode),
          const SizedBox(height: 20),

          // ── Vessel Safety Info ──────────────────────────────────────────────
          _SectionHeader(icon: Icons.directions_boat, label: l10n.emergencyVesselSafetySection),
          const SizedBox(height: 8),
          _VesselSafetyCard(vessel: vessel, editMode: _editMode),
          const SizedBox(height: 20),

          // ── Coast Guard Frequencies ─────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SectionHeader(icon: Icons.settings_input_antenna, label: l10n.emergencyFrequenciesSection),
              if (_editMode && canAddFrequency)
                _AddIconButton(onTap: _showAddFrequencyDialog),
            ],
          ),
          const SizedBox(height: 8),
          _FrequenciesCard(vessel: vessel, editMode: _editMode),
          const SizedBox(height: 20),

          // ── Crew Medical Overview ───────────────────────────────────────────
          Row(
            children: [
              _SectionHeader(icon: Icons.medical_services, label: l10n.emergencyCrewMedicalSection),
              const SizedBox(width: 6),
              Tooltip(
                message: l10n.emergencyCrewAutoNote,
                triggerMode: TooltipTriggerMode.tap,
                showDuration: const Duration(seconds: 4),
                child: Icon(Icons.info_outline, size: 14, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (crew.isEmpty)
            _EmptyCrewHint()
          else
            Column(
              children: crew
                  .map((m) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _CrewMedicalCard(member: m),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }
}

// ─── Quick Action Card ────────────────────────────────────────────────────────

class _QuickActionCard extends StatelessWidget {
  final String label;
  final String title;
  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final Color borderColor;
  final Color cardBg;
  final IconData trailingIcon;
  final Color trailingColor;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.label,
    required this.title,
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.borderColor,
    required this.cardBg,
    required this.trailingIcon,
    required this.trailingColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: iconFg, size: 24),
                ),
                Icon(trailingIcon, color: trailingColor, size: 18),
              ],
            ),
            const Spacer(),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: borderColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: GoogleFonts.newsreader(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: borderColor == Theme.of(context).colorScheme.error
                    ? Theme.of(context).colorScheme.onErrorContainer
                    : borderColor,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Section Header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _AddIconButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddIconButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: context.l10n.add,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.add, size: 16, color: cs.onPrimaryContainer),
        ),
      ),
    );
  }
}

class _EditButton extends StatelessWidget {
  final VoidCallback onTap;
  const _EditButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Tooltip(
      message: l10n.edit,
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          children: [
            Icon(Icons.edit, size: 14, color: cs.primary),
            const SizedBox(width: 4),
            Text(
              l10n.edit.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: cs.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Emergency Contacts Card ──────────────────────────────────────────────────

class _ContactsCard extends StatelessWidget {
  final List<EmergencyContact> contacts;
  final bool editMode;
  const _ContactsCard({required this.contacts, required this.editMode});

  Future<void> _call(String phone) async {
    final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$digits');
    if (await canLaunchUrl(uri)) launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: contacts.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.l10n.emergencyNoContacts,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          : Column(
              children: contacts
                  .map((c) => _ContactRow(
                        contact: c,
                        editMode: editMode,
                        onCall: () => _call(c.phone),
                        onEdit: () => _showEditContactDialog(context, c),
                      ))
                  .toList(),
            ),
    );
  }

  void _showEditContactDialog(BuildContext context, EmergencyContact contact) {
    final repo = context.read<EmergencyRepository>();
    showDialog<EmergencyContact>(
      context: context,
      builder: (_) => _EditContactDialog(
        contact: contact,
        onDelete: () => repo.removeContact(contact),
      ),
    ).then((updated) {
      if (updated != null) repo.updateContact(contact.key as int, updated);
    });
  }
}

class _ContactRow extends StatelessWidget {
  final EmergencyContact contact;
  final bool editMode;
  final VoidCallback onCall;
  final VoidCallback onEdit;
  const _ContactRow({
    required this.contact,
    required this.editMode,
    required this.onCall,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final em = Theme.of(context).extension<LogbookEmergencyColors>()!;
    return Container(
      margin: const EdgeInsets.all(10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: cs.primary, width: 4)),
        boxShadow: [
          BoxShadow(
            color: em.cardShadowColor,
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.name,
                  style: GoogleFonts.newsreader(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
                Text(
                  '${contact.role} · ${contact.phone}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (contact.phone.isNotEmpty)
            GestureDetector(
              onTap: onCall,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.call, color: cs.onPrimaryContainer, size: 16),
              ),
            ),
          if (editMode) ...[
            const SizedBox(width: 10),
            _EditButton(onTap: onEdit),
          ],
        ],
      ),
    );
  }
}

// ─── Add Contact Dialog ───────────────────────────────────────────────────────

class _AddContactDialog extends StatefulWidget {
  const _AddContactDialog();

  @override
  State<_AddContactDialog> createState() => _AddContactDialogState();
}

class _AddContactDialogState extends State<_AddContactDialog> {
  final _nameCtrl = TextEditingController();
  final _roleCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _roleCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      title: Text(context.l10n.emergencyAddContactTitle,
          style: GoogleFonts.newsreader(fontSize: 18, fontWeight: FontWeight.w600, color: cs.onSurface)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            style: TextStyle(color: cs.onSurface),
            decoration: InputDecoration(labelText: context.l10n.emergencyContactNameLabel, labelStyle: TextStyle(color: cs.onSurfaceVariant)),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _roleCtrl,
            style: TextStyle(color: cs.onSurface),
            decoration: InputDecoration(labelText: context.l10n.emergencyContactRoleHint, labelStyle: TextStyle(color: cs.onSurfaceVariant)),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _phoneCtrl,
            style: TextStyle(color: cs.onSurface),
            decoration: InputDecoration(labelText: context.l10n.emergencyContactPhoneLabel, labelStyle: TextStyle(color: cs.onSurfaceVariant)),
            keyboardType: TextInputType.phone,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel, style: TextStyle(color: cs.onSurfaceVariant)),
        ),
        FilledButton.icon(
          onPressed: () {
            if (_nameCtrl.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              EmergencyContact(
                name: _nameCtrl.text.trim(),
                role: _roleCtrl.text.trim(),
                phone: _phoneCtrl.text.trim(),
              ),
            );
          },
          icon: const Icon(Icons.anchor, size: 18),
          label: Text(context.l10n.add),
        ),
      ],
    );
  }
}

// ─── Edit Contact Dialog ──────────────────────────────────────────────────────

class _EditContactDialog extends StatefulWidget {
  final EmergencyContact contact;
  final VoidCallback onDelete;
  const _EditContactDialog({required this.contact, required this.onDelete});

  @override
  State<_EditContactDialog> createState() => _EditContactDialogState();
}

class _EditContactDialogState extends State<_EditContactDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _roleCtrl;
  late final TextEditingController _phoneCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.contact.name);
    _roleCtrl = TextEditingController(text: widget.contact.role);
    _phoneCtrl = TextEditingController(text: widget.contact.phone);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _roleCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      title: Text(context.l10n.emergencyEditContactTitle,
          style: GoogleFonts.newsreader(fontSize: 18, fontWeight: FontWeight.w600, color: cs.onSurface)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            style: TextStyle(color: cs.onSurface),
            decoration: InputDecoration(labelText: context.l10n.emergencyContactNameLabel, labelStyle: TextStyle(color: cs.onSurfaceVariant)),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _roleCtrl,
            style: TextStyle(color: cs.onSurface),
            decoration: InputDecoration(labelText: context.l10n.emergencyContactRoleHint, labelStyle: TextStyle(color: cs.onSurfaceVariant)),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _phoneCtrl,
            style: TextStyle(color: cs.onSurface),
            decoration: InputDecoration(labelText: context.l10n.emergencyContactPhoneLabel, labelStyle: TextStyle(color: cs.onSurfaceVariant)),
            keyboardType: TextInputType.phone,
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            widget.onDelete();
          },
          style: TextButton.styleFrom(foregroundColor: cs.error),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_outline, size: 16, color: cs.error),
              const SizedBox(width: 4),
              Text(context.l10n.delete),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.cancel, style: TextStyle(color: cs.onSurfaceVariant)),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: () {
                if (_nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(
                  context,
                  EmergencyContact(
                    name: _nameCtrl.text.trim(),
                    role: _roleCtrl.text.trim(),
                    phone: _phoneCtrl.text.trim(),
                  ),
                );
              },
              child: Text(context.l10n.save),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Vessel Safety Info Card ──────────────────────────────────────────────────

class _VesselSafetyCard extends StatefulWidget {
  final ThemeProvider vessel;
  final bool editMode;
  const _VesselSafetyCard({required this.vessel, required this.editMode});

  @override
  State<_VesselSafetyCard> createState() => _VesselSafetyCardState();
}

class _VesselSafetyCardState extends State<_VesselSafetyCard> {
  late final TextEditingController _mmsiCtrl;
  late final TextEditingController _callSignCtrl;
  late final TextEditingController _lifeRaftCtrl;
  late final TextEditingController _epirbCtrl;
  late final TextEditingController _fireSuppCtrl;

  @override
  void initState() {
    super.initState();
    _mmsiCtrl     = TextEditingController(text: widget.vessel.vesselMmsi);
    _callSignCtrl = TextEditingController(text: widget.vessel.vesselCallSign);
    _lifeRaftCtrl = TextEditingController(text: widget.vessel.lifeRaftInfo);
    _epirbCtrl    = TextEditingController(text: widget.vessel.epirbInfo);
    _fireSuppCtrl = TextEditingController(text: widget.vessel.fireSuppInfo);
  }

  @override
  void didUpdateWidget(_VesselSafetyCard old) {
    super.didUpdateWidget(old);
    if (!old.editMode && widget.editMode) {
      _mmsiCtrl.text     = widget.vessel.vesselMmsi;
      _callSignCtrl.text = widget.vessel.vesselCallSign;
      _lifeRaftCtrl.text = widget.vessel.lifeRaftInfo;
      _epirbCtrl.text    = widget.vessel.epirbInfo;
      _fireSuppCtrl.text = widget.vessel.fireSuppInfo;
    }
  }

  @override
  void dispose() {
    _mmsiCtrl.dispose();
    _callSignCtrl.dispose();
    _lifeRaftCtrl.dispose();
    _epirbCtrl.dispose();
    _fireSuppCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: widget.editMode ? _buildEditView(cs) : _buildReadView(cs),
    );
  }

  Widget _buildEditView(ColorScheme cs) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _VesselEditField(
              // MMSI NUMBER and CALL SIGN are international maritime identifiers — kept in English per SOLAS/IMO standard
              label: 'MMSI NUMBER',
              controller: _mmsiCtrl,
              keyboardType: TextInputType.number,
              onChanged: widget.vessel.setVesselMmsi,
            )),
            const SizedBox(width: 12),
            Expanded(child: _VesselEditField(
              label: 'CALL SIGN',
              controller: _callSignCtrl,
              textCapitalization: TextCapitalization.characters,
              onChanged: widget.vessel.setVesselCallSign,
            )),
          ],
        ),
        const SizedBox(height: 12),
        _VesselEditField(
          label: l10n.emergencyLifeRaft.toUpperCase(),
          controller: _lifeRaftCtrl,
          onChanged: widget.vessel.setLifeRaftInfo,
        ),
        const SizedBox(height: 12),
        _VesselEditField(
          // EPIRB is an international maritime acronym — kept in English
          label: 'EPIRB LOCATION',
          controller: _epirbCtrl,
          onChanged: widget.vessel.setEpirbInfo,
        ),
        const SizedBox(height: 12),
        _VesselEditField(
          label: l10n.emergencyFireSuppression.toUpperCase(),
          controller: _fireSuppCtrl,
          onChanged: widget.vessel.setFireSuppInfo,
        ),
      ],
    );
  }

  Widget _buildReadView(ColorScheme cs) {
    final em = Theme.of(context).extension<LogbookEmergencyColors>()!;
    final l10n = context.l10n;
    final v = widget.vessel;
    return Stack(
      children: [
        Positioned(
          right: -8,
          top: -8,
          child: Icon(Icons.anchor, size: 100,
              color: cs.onSurface.withValues(alpha: 0.06)),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final fields = [
                  _InfoField(
                    label: 'MMSI NUMBER',
                    value: v.vesselMmsi.isNotEmpty ? v.vesselMmsi : '—',
                    mono: true,
                  ),
                  _InfoField(
                    label: 'CALL SIGN',
                    value: v.vesselCallSign.isNotEmpty ? v.vesselCallSign : '—',
                  ),
                ];
                if (constraints.maxWidth < 300) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [fields[0], const SizedBox(height: 12), fields[1]],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: fields[0]),
                    const SizedBox(width: 20),
                    Expanded(child: fields[1]),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            if (v.lifeRaftInfo.isNotEmpty)
              _SafetyItem(
                icon: Icons.water,
                iconColor: em.criticalColor,
                title: l10n.emergencyLifeRaft,
                detail: v.lifeRaftInfo,
              ),
            if (v.epirbInfo.isNotEmpty)
              _SafetyItem(
                icon: Icons.sensors,
                iconColor: cs.secondary,
                // EPIRB is an international maritime acronym — kept in English
                title: 'EPIRB Location',
                detail: v.epirbInfo,
              ),
            if (v.fireSuppInfo.isNotEmpty)
              _SafetyItem(
                icon: Icons.fire_extinguisher,
                iconColor: em.criticalColor,
                title: l10n.emergencyFireSuppression,
                detail: v.fireSuppInfo,
              ),
            if (v.vesselMmsi.isEmpty &&
                v.vesselCallSign.isEmpty &&
                v.lifeRaftInfo.isEmpty &&
                v.epirbInfo.isEmpty &&
                v.fireSuppInfo.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.emergencyNoSafetyData,
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                      fontStyle: FontStyle.italic),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _VesselEditField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final TextCapitalization textCapitalization;
  final ValueChanged<String> onChanged;

  const _VesselEditField({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.keyboardType = TextInputType.text,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          onChanged: onChanged,
          style: GoogleFonts.inter(fontSize: 13, color: cs.onSurface),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            filled: true,
            fillColor: cs.surfaceContainer,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: cs.outline),
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoField extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  const _InfoField({required this.label, required this.value, this.mono = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 10, fontWeight: FontWeight.w700,
                letterSpacing: 1.5, color: cs.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(
          value,
          style: mono
              ? GoogleFonts.inter(
                  fontSize: 16, fontWeight: FontWeight.w600,
                  letterSpacing: 3, color: cs.primary)
              : GoogleFonts.newsreader(
                  fontSize: 17, fontWeight: FontWeight.w600, color: cs.primary),
        ),
      ],
    );
  }
}

class _SafetyItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String detail;
  const _SafetyItem(
      {required this.icon, required this.iconColor,
       required this.title, required this.detail});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.inter(
                        fontSize: 14, fontWeight: FontWeight.w600,
                        color: cs.onSurface)),
                Text(detail,
                    style: GoogleFonts.inter(
                        fontSize: 13, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Coast Guard Frequencies Card ─────────────────────────────────────────────

class _FrequenciesCard extends StatelessWidget {
  final ThemeProvider vessel;
  final bool editMode;
  const _FrequenciesCard({required this.vessel, required this.editMode});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final allEntries = [
      (ch: vessel.vhf1Label, desc: vessel.vhf1Desc, urgent: true, slot: 1),
      (ch: vessel.vhf2Label, desc: vessel.vhf2Desc, urgent: false, slot: 2),
      (ch: vessel.vhf3Label, desc: vessel.vhf3Desc, urgent: false, slot: 3),
      (ch: vessel.vhf4Label, desc: vessel.vhf4Desc, urgent: false, slot: 4),
    ];
    final entries = allEntries.where((f) => f.ch.isNotEmpty).toList();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: entries.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(6),
              child: Text(
                context.l10n.emergencyNoFrequencies,
                style: GoogleFonts.inter(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                    fontStyle: FontStyle.italic),
              ),
            )
          : Column(
              children: entries
                  .map((f) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _FrequencyRow(
                          label: f.ch,
                          desc: f.desc,
                          urgent: f.urgent,
                          editMode: editMode,
                          onEdit: () => _showEditDialog(context, f.slot),
                        ),
                      ))
                  .toList(),
            ),
    );
  }

  void _showEditDialog(BuildContext context, int slot) {
    final v = context.read<ThemeProvider>();
    final labels = [v.vhf1Label, v.vhf2Label, v.vhf3Label, v.vhf4Label];
    final descs = [v.vhf1Desc, v.vhf2Desc, v.vhf3Desc, v.vhf4Desc];

    showDialog<({String label, String desc})?>(
      context: context,
      builder: (_) => _EditFrequencyDialog(
        initialLabel: labels[slot - 1],
        initialDesc: descs[slot - 1],
        onDelete: () => _deleteFrequency(v, slot),
      ),
    ).then((result) {
      if (result != null) v.setVhfEntry(slot, result.label, result.desc);
    });
  }

  void _deleteFrequency(ThemeProvider v, int slot) {
    final labels = [v.vhf1Label, v.vhf2Label, v.vhf3Label, v.vhf4Label];
    final descs = [v.vhf1Desc, v.vhf2Desc, v.vhf3Desc, v.vhf4Desc];
    labels.removeAt(slot - 1);
    descs.removeAt(slot - 1);
    labels.add('');
    descs.add('');
    for (int i = 0; i < 4; i++) {
      v.setVhfEntry(i + 1, labels[i], descs[i]);
    }
  }
}

class _FrequencyRow extends StatelessWidget {
  final String label;
  final String desc;
  final bool urgent;
  final bool editMode;
  final VoidCallback onEdit;

  const _FrequencyRow({
    required this.label,
    required this.desc,
    required this.urgent,
    required this.editMode,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final em = Theme.of(context).extension<LogbookEmergencyColors>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: urgent ? em.criticalBgColor : cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: urgent ? em.criticalColor : cs.primary, width: 4),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.newsreader(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: urgent ? em.criticalColor : cs.primary)),
                Text(desc,
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        color: urgent ? cs.onErrorContainer : cs.onSurfaceVariant)),
              ],
            ),
          ),
          if (urgent && !editMode)
            Icon(Icons.warning_rounded, color: em.criticalColor, size: 20),
          if (editMode)
            _EditButton(onTap: onEdit),
        ],
      ),
    );
  }
}

// ─── Add Frequency Dialog ─────────────────────────────────────────────────────

class _AddFrequencyDialog extends StatefulWidget {
  const _AddFrequencyDialog();

  @override
  State<_AddFrequencyDialog> createState() => _AddFrequencyDialogState();
}

class _AddFrequencyDialogState extends State<_AddFrequencyDialog> {
  final _labelCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  @override
  void dispose() {
    _labelCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      title: Text(context.l10n.emergencyAddFrequencyTitle,
          style: GoogleFonts.newsreader(fontSize: 18, fontWeight: FontWeight.w600, color: cs.onSurface)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _labelCtrl,
            style: TextStyle(color: cs.onSurface),
            decoration: InputDecoration(labelText: context.l10n.emergencyFrequencyChannelLabel, labelStyle: TextStyle(color: cs.onSurfaceVariant)),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descCtrl,
            style: TextStyle(color: cs.onSurface),
            decoration: InputDecoration(labelText: context.l10n.emergencyFrequencyDescLabel, labelStyle: TextStyle(color: cs.onSurfaceVariant)),
            textInputAction: TextInputAction.done,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel, style: TextStyle(color: cs.onSurfaceVariant)),
        ),
        FilledButton(
          onPressed: () {
            if (_labelCtrl.text.trim().isEmpty) return;
            Navigator.pop(context,
                (label: _labelCtrl.text.trim(), desc: _descCtrl.text.trim()));
          },
          child: Text(context.l10n.add),
        ),
      ],
    );
  }
}

// ─── Edit Frequency Dialog ────────────────────────────────────────────────────

class _EditFrequencyDialog extends StatefulWidget {
  final String initialLabel;
  final String initialDesc;
  final VoidCallback onDelete;

  const _EditFrequencyDialog({
    required this.initialLabel,
    required this.initialDesc,
    required this.onDelete,
  });

  @override
  State<_EditFrequencyDialog> createState() => _EditFrequencyDialogState();
}

class _EditFrequencyDialogState extends State<_EditFrequencyDialog> {
  late final TextEditingController _labelCtrl;
  late final TextEditingController _descCtrl;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.initialLabel);
    _descCtrl = TextEditingController(text: widget.initialDesc);
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      title: Text(context.l10n.emergencyEditFrequencyTitle,
          style: GoogleFonts.newsreader(fontSize: 18, fontWeight: FontWeight.w600, color: cs.onSurface)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _labelCtrl,
            style: TextStyle(color: cs.onSurface),
            decoration: InputDecoration(labelText: context.l10n.emergencyFrequencyChannelLabel, labelStyle: TextStyle(color: cs.onSurfaceVariant)),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descCtrl,
            style: TextStyle(color: cs.onSurface),
            decoration: InputDecoration(labelText: context.l10n.emergencyFrequencyDescLabel, labelStyle: TextStyle(color: cs.onSurfaceVariant)),
            textInputAction: TextInputAction.done,
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            widget.onDelete();
          },
          style: TextButton.styleFrom(foregroundColor: cs.error),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_outline, size: 16, color: cs.error),
              const SizedBox(width: 4),
              Text(context.l10n.delete),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.cancel, style: TextStyle(color: cs.onSurfaceVariant)),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: () {
                Navigator.pop(context,
                    (label: _labelCtrl.text.trim(), desc: _descCtrl.text.trim()));
              },
              child: Text(context.l10n.save),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Crew Medical Overview Card ───────────────────────────────────────────────

class _CrewMedicalCard extends StatelessWidget {
  final CrewMember member;
  const _CrewMedicalCard({required this.member});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final em = Theme.of(context).extension<LogbookEmergencyColors>()!;
    final bloodType = member.bloodType ?? '';
    final allergies = member.allergies ?? '';
    final conditions = member.conditions ?? '';

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: em.cardShadowColor,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
         child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 6,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [cs.tertiary, cs.primaryContainer],
                  stops: const [0.5, 0.5],
                  tileMode: TileMode.repeated,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                member.name,
                                style: GoogleFonts.newsreader(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w500,
                                    color: cs.primary),
                              ),
                              if (member.remarks?.isNotEmpty == true)
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainer,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    (member.remarks as String).toUpperCase(),
                                    style: GoogleFonts.inter(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                        color: cs.onSurfaceVariant),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (bloodType.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: em.criticalBgColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Column(
                              children: [
                                Text(context.l10n.emergencyBloodBadge,
                                    style: GoogleFonts.inter(
                                        fontSize: 8, fontWeight: FontWeight.w700,
                                        color: cs.onErrorContainer)),
                                Text(bloodType,
                                    style: GoogleFonts.inter(
                                        fontSize: 18, fontWeight: FontWeight.w700,
                                        color: cs.onErrorContainer)),
                              ],
                            ),
                          ),
                      ],
                    ),
                    if (allergies.isNotEmpty || conditions.isNotEmpty)
                      const SizedBox(height: 10),
                    if (allergies.isNotEmpty)
                      _MedicalRow(
                          icon: Icons.heart_broken,
                          color: cs.onErrorContainer,
                          text: allergies),
                    if (conditions.isNotEmpty)
                      _MedicalRow(
                          icon: Icons.medication,
                          color: em.criticalColor,
                          text: conditions),
                  ],
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

class _MedicalRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _MedicalRow({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCrewHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final homeRepo = context.read<HomeRepository>();
    final entries = homeRepo.entries;
    final latestEntry = entries.isNotEmpty ? entries.last : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.emergencyNoCrewHint,
            style: GoogleFonts.inter(
                fontSize: 13,
                color: cs.onSurfaceVariant,
                fontStyle: FontStyle.italic),
          ),
          if (latestEntry != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.push(
                  '/day/${latestEntry.date.year}/${latestEntry.date.month}/${latestEntry.date.day}',
                ),
                icon: const Icon(Icons.auto_stories, size: 16),
                label: Text(l10n.emergencyOpenDayEntry),
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.primary,
                  side: BorderSide(color: cs.primary.withValues(alpha: 0.3)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  textStyle: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
