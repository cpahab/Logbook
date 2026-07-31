import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../home/data/home_repository.dart';
import '../../home/domain/crew_member.dart';
import '../../settings/domain/theme_provider.dart';
import '../../../l10n/l10n_extension.dart';
import '../../../app/route_names.dart';
import '../../../app/theme/theme_extensions.dart';
import '../../../core/widgets/add_icon_button.dart';
import '../../../core/widgets/danger_outlined_button.dart';
import '../../../core/widgets/nav_bar.dart';
import '../../../core/widgets/reorderable_list_card.dart';
import '../../../core/widgets/undo_delete_snackbar.dart';
import '../data/emergency_repository.dart';
import '../domain/emergency_contact.dart';

/// Emergency Manifest: the crew's single-page safety reference — quick links
/// into the MAYDAY protocol and visual-signals guide, emergency contacts,
/// vessel safety equipment info, coast guard VHF channels, and a live
/// crew-medical summary sourced from today's (or the most recent) crew list.
/// An edit-mode toggle in the app bar switches contacts/vessel-info/
/// frequency cards between read view and inline-editable fields.
class EmergencyManifestScreen extends StatefulWidget {
  const EmergencyManifestScreen({super.key});

  @override
  State<EmergencyManifestScreen> createState() => _EmergencyManifestScreenState();
}

class _EmergencyManifestScreenState extends State<EmergencyManifestScreen> {
  bool _editMode = false;
  late EmergencyRepository _emergencyRepo;
  late ThemeProvider _vessel;

  @override
  void initState() {
    super.initState();
    // The live Firestore listeners alone aren't reliable enough here — their
    // underlying stream can go stale while this device was backgrounded, so
    // a change made on another device could otherwise sit unseen until a
    // full app relaunch. Re-checking on every visit to this screen closes
    // that gap without needing one.
    context.read<EmergencyRepository>().refreshContacts();
    context.read<ThemeProvider>().refreshVesselSettings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _emergencyRepo = context.read<EmergencyRepository>();
    _vessel = context.read<ThemeProvider>();
  }

  @override
  void dispose() {
    // Safety net: if the user navigates away while still in edit mode
    // (e.g. via the bottom nav, without tapping the done checkmark), flush
    // the deferred sync and resume the live listeners here instead — an
    // edit session that never ends would otherwise defer its sync forever
    // and leave both listeners permanently paused.
    if (_editMode) {
      _emergencyRepo.endEditingAndSync();
      _vessel.endVesselSafetyEditingAndSync();
    }
    super.dispose();
  }

  /// Shows the add-contact dialog and, if confirmed, saves the new contact.
  void _showAddContactDialog() {
    final repo = context.read<EmergencyRepository>();
    showDialog<EmergencyContact>(
      context: context,
      builder: (_) => const _AddContactDialog(),
    ).then((contact) {
      if (contact != null) repo.addContact(contact);
    });
  }

  /// Shows the add-frequency dialog for the next free VHF slot (there are
  /// exactly 4) and saves the entry if confirmed. No-ops if all 4 are full.
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
    final em = cs;
    final l10n = context.l10n;
    final vessel = context.watch<ThemeProvider>();
    final emergency = context.watch<EmergencyRepository>();
    final today = DateTime.now();
    final homeRepo = context.watch<HomeRepository>();
    final todayCrew = homeRepo.getEntry(today)?.crew ?? [];
    final rawCrew = todayCrew.isNotEmpty ? todayCrew : homeRepo.lastCrew;
    // Resolve each person's personal/medical fields from their live roster
    // record (if they have one), so editing the roster in Settings is
    // reflected here immediately instead of showing whatever was copied
    // into this day's entry when they were added.
    final crew =
        rawCrew.map((m) => homeRepo.rosterMemberById(m.id) ?? m).toList();

    final vhfLabels = [vessel.vhf1Label, vessel.vhf2Label, vessel.vhf3Label, vessel.vhf4Label];
    final canAddFrequency = vhfLabels.any((l) => l.isEmpty);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Text(l10n.emergencyManifestTitle),
        actions: [
          IconButton(
            icon: Icon(
              _editMode ? Icons.check_rounded : Icons.edit_outlined,
              color: _editMode ? cs.primary : cs.onSurfaceVariant,
            ),
            tooltip: _editMode ? l10n.emergencyManifestEditDoneTooltip : l10n.emergencyManifestEditPageTooltip,
            onPressed: () {
              final enteringEditMode = !_editMode;
              setState(() => _editMode = enteringEditMode);
              if (enteringEditMode) {
                emergency.beginEditing();
                vessel.beginVesselSafetyEditing();
              } else {
                emergency.endEditingAndSync();
                vessel.endVesselSafetyEditingAndSync();
              }
            },
          ),
        ],
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
          // ── Quick Actions ───────────────────────────────────────────────────
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _QuickActionCard(
                  label: l10n.emergencyProtocolBadge,
                  title: l10n.emergencyRadioProtocolShort,
                  icon: Icons.record_voice_over,
                  iconBg: em.criticalColor,
                  iconFg: cs.onError,
                  borderColor: em.criticalColor,
                  cardBg: em.criticalBgColor,
                  trailingIcon: Icons.arrow_forward_ios,
                  trailingColor: em.criticalColor,
                  onTap: () => context.pushNamed(AppRoute.mayday),
                )),
                const SizedBox(width: 12),
                Expanded(child: _QuickActionCard(
                  label: l10n.emergencyVisualAidBadge,
                  title: l10n.emergencyGuideShort,
                  icon: Icons.sos,
                  iconBg: cs.primary,
                  iconFg: cs.onPrimary,
                  borderColor: cs.primary,
                  cardBg: cs.surfaceContainerLowest,
                  trailingIcon: Icons.flare,
                  trailingColor: cs.primary,
                  onTap: () => context.pushNamed(AppRoute.emergencyGuide),
                )),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // ── end Quick Actions ──

          // ── Emergency Contacts ──────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SectionHeader(icon: Icons.contact_emergency, label: l10n.emergencyContactsSection),
              if (_editMode)
                AddIconButton(onTap: _showAddContactDialog),
            ],
          ),
          const SizedBox(height: 8),
          _ContactsCard(contacts: emergency.contacts, editMode: _editMode),
          const SizedBox(height: 20),
          // ── end Emergency Contacts ──

          // ── Vessel Safety Info ──────────────────────────────────────────────
          _SectionHeader(icon: Icons.directions_boat, label: l10n.emergencyVesselSafetySection),
          const SizedBox(height: 8),
          _VesselSafetyCard(vessel: vessel, editMode: _editMode),
          const SizedBox(height: 20),
          // ── end Vessel Safety Info ──

          // ── Coast Guard Frequencies ─────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SectionHeader(icon: Icons.settings_input_antenna, label: l10n.emergencyFrequenciesSection),
              if (_editMode && canAddFrequency)
                AddIconButton(onTap: _showAddFrequencyDialog),
            ],
          ),
          const SizedBox(height: 8),
          _FrequenciesCard(vessel: vessel, editMode: _editMode),
          const SizedBox(height: 20),
          // ── end Coast Guard Frequencies ──

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
          // ── end Crew Medical Overview ──
        ],
      ),
    );
  }
}

// ─── Quick Action Card ────────────────────────────────────────────────────────
/// One of the two top shortcut tiles (→ MAYDAY protocol, → visual signals guide).

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
              style: Theme.of(context).textTheme.labelSmall!.copyWith(fontSize: 10, color: borderColor),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w600, height: 1.25, color: borderColor == Theme.of(context).colorScheme.error
                    ? Theme.of(context).colorScheme.onErrorContainer
                    : borderColor),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Section Header ───────────────────────────────────────────────────────────
/// Small-caps eyebrow label with a leading icon, used above every card on this screen.
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: cs.secondary),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall!.copyWith(
            color: cs.secondary,
          ),
        ),
      ],
    );
  }
}

/// Small "EDIT" text+icon button shown on a row while in edit mode (contacts,
/// frequencies).
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
              style: Theme.of(context).textTheme.labelSmall!.copyWith(fontSize: 10, letterSpacing: 1, color: cs.primary),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Emergency Contacts Card ──────────────────────────────────────────────────
/// Card listing every saved emergency contact as tappable-to-call rows.
class _ContactsCard extends StatelessWidget {
  final List<EmergencyContact> contacts;
  final bool editMode;
  const _ContactsCard({required this.contacts, required this.editMode});

  /// Strips non-digit/non-`+` characters and launches the phone dialer.
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
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                  color: cs.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          : editMode
              ? ReorderableListCard<EmergencyContact>(
                  items: contacts,
                  padding: EdgeInsets.zero,
                  keyOf: (c) => ValueKey(c.key),
                  onReorder: (oldIndex, newIndex) {
                    final newOrder = List.of(contacts);
                    final c = newOrder.removeAt(oldIndex);
                    newOrder.insert(newIndex, c);
                    context.read<EmergencyRepository>().reorderContacts(newOrder);
                  },
                  itemBuilder: (context, c, i) => _ContactRow(
                    contact: c,
                    editMode: editMode,
                    reordering: true,
                    index: i,
                    onCall: () => _call(c.phone),
                    onEdit: () => _showEditContactDialog(context, c),
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

  /// Shows the edit-contact dialog and saves/deletes the contact per the result.
  void _showEditContactDialog(BuildContext context, EmergencyContact contact) {
    final repo = context.read<EmergencyRepository>();
    showDialog<EmergencyContact>(
      context: context,
      builder: (_) => _EditContactDialog(
        contact: contact,
        onDelete: () {
          repo.removeContact(contact);
          showUndoDeleteSnackBar(
            context,
            message: context.l10n.emergencyContactDeleted(contact.name),
            onUndo: () => repo.addContact(contact),
          );
        },
      ),
    ).then((updated) {
      if (updated != null) repo.updateContact(contact.key as int, updated);
    });
  }
}

/// One contact's name/role/phone with a tappable call button (and edit
/// button, in edit mode).
class _ContactRow extends StatelessWidget {
  final EmergencyContact contact;
  final bool editMode;
  final bool reordering;
  final int index;
  final VoidCallback onCall;
  final VoidCallback onEdit;
  const _ContactRow({
    required this.contact,
    required this.editMode,
    this.reordering = false,
    this.index = 0,
    required this.onCall,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final em = cs;
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
                  style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w600, color: cs.primary),
                ),
                Text(
                  [
                    if (contact.role.isNotEmpty) contact.role,
                    if (contact.phone.isNotEmpty) contact.phone,
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
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
          if (reordering) ...[
            const SizedBox(width: 10),
            ReorderableDragStartListener(
              index: index,
              child: Icon(Icons.drag_handle, color: cs.outline.withValues(alpha: 0.4)),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Add Contact Dialog ───────────────────────────────────────────────────────
/// Dialog for creating a new emergency contact (name/role/phone).
class _AddContactDialog extends StatefulWidget {
  const _AddContactDialog();

  @override
  State<_AddContactDialog> createState() => _AddContactDialogState();
}

class _AddContactDialogState extends State<_AddContactDialog> {
  final _nameCtrl = TextEditingController();
  final _roleCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  /// Guards against a duplicated tap on the Add button — observed after
  /// backgrounding the app (e.g. to check a phone number in another app)
  /// with this dialog still open, then returning and tapping Add: a single
  /// logical tap could otherwise still fire onPressed more than once and
  /// add the same contact repeatedly.
  bool _submitted = false;

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
      // Wraps title+content together in a properly height-bounded
      // SingleChildScrollView (unlike wrapping content alone, which isn't
      // given a bounded height to scroll within and just overflows) — needed
      // so the fields stay reachable once the keyboard leaves too little
      // room for all three on a small screen.
      scrollable: true,
      title: Text(context.l10n.emergencyAddContactTitle,
          style: Theme.of(context).textTheme.fieldValueProse.copyWith(color: cs.onSurface)),
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
            if (_submitted || _nameCtrl.text.trim().isEmpty) return;
            _submitted = true;
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
/// Dialog for editing (or deleting) an existing emergency contact.
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
  /// See _AddContactDialogState's identically-named field.
  bool _submitted = false;

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
      // See _AddContactDialog's comment on this flag.
      scrollable: true,
      title: Text(context.l10n.emergencyEditContactTitle,
          style: Theme.of(context).textTheme.fieldValueProse.copyWith(color: cs.onSurface)),
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
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.l10n.cancel, style: TextStyle(color: cs.onSurfaceVariant)),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: () {
                    if (_submitted || _nameCtrl.text.trim().isEmpty) return;
                    _submitted = true;
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
            const SizedBox(height: 16),
            DangerOutlinedButton(
              icon: Icons.delete_outline,
              label: context.l10n.delete,
              onPressed: () {
                if (_submitted) return;
                _submitted = true;
                Navigator.pop(context);
                widget.onDelete();
              },
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Vessel Safety Info Card ──────────────────────────────────────────────────
/// MMSI/call sign/life raft/EPIRB/fire suppression info, either as a read-only
/// summary or (in edit mode) inline text fields writing straight through to
/// [ThemeProvider].
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
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: widget.editMode ? _buildEditView(cs) : _buildReadView(cs),
    );
  }

  /// Inline-editable field layout (MMSI/call sign row, then one field per
  /// remaining safety item), each writing straight through on every keystroke.
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

  /// Read-only summary: identity fields (MMSI/call sign) side-by-side on wide
  /// layouts or stacked on narrow ones, then a list of populated safety items.
  Widget _buildReadView(ColorScheme cs) {
    final l10n = context.l10n;
    final v = widget.vessel;

    final idFields = [
      if (v.vesselMmsi.isNotEmpty)
        _InfoField(label: 'MMSI NUMBER', value: v.vesselMmsi, mono: true),
      if (v.vesselCallSign.isNotEmpty)
        _InfoField(label: 'CALL SIGN', value: v.vesselCallSign),
    ];
    final safetyItems = [
      if (v.lifeRaftInfo.isNotEmpty)
        _SafetyItem(
          icon: Icons.water,
          urgent: true,
          title: l10n.emergencyLifeRaft,
          detail: v.lifeRaftInfo,
        ),
      if (v.epirbInfo.isNotEmpty)
        _SafetyItem(
          icon: Icons.sensors,
          urgent: false,
          // EPIRB is an international maritime acronym — kept in English
          title: 'EPIRB Location',
          detail: v.epirbInfo,
        ),
      if (v.fireSuppInfo.isNotEmpty)
        _SafetyItem(
          icon: Icons.fire_extinguisher,
          urgent: true,
          title: l10n.emergencyFireSuppression,
          detail: v.fireSuppInfo,
        ),
    ];

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
            if (idFields.isNotEmpty)
              LayoutBuilder(
                builder: (context, constraints) {
                  if (idFields.length == 1 || constraints.maxWidth < 300) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (int i = 0; i < idFields.length; i++) ...[
                          if (i > 0) const SizedBox(height: 12),
                          idFields[i],
                        ],
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: idFields[0]),
                      const SizedBox(width: 20),
                      Expanded(child: idFields[1]),
                    ],
                  );
                },
              ),
            if (idFields.isNotEmpty && safetyItems.isNotEmpty)
              const SizedBox(height: 16),
            for (int i = 0; i < safetyItems.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              safetyItems[i],
            ],
            if (idFields.isEmpty && safetyItems.isEmpty)
              Text(
                l10n.emergencyNoSafetyData,
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    color: cs.onSurfaceVariant,
                    fontStyle: FontStyle.italic),
              ),
          ],
        ),
      ],
    );
  }
}

/// Small labeled text field used in [_VesselSafetyCard]'s edit view.
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
          style: Theme.of(context).textTheme.labelSmall!.copyWith(fontSize: 10, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          onChanged: onChanged,
          style: Theme.of(context).textTheme.bodySmall!.copyWith(color: cs.onSurface),
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

/// Read-only label/value pair used for MMSI/call sign in [_VesselSafetyCard]'s
/// read view ([mono] gives MMSI its tracked-monospace-style digit spacing).
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
            style: Theme.of(context).textTheme.labelSmall!.copyWith(fontSize: 10, color: cs.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(
          value,
          style: mono
              ? Theme.of(context).textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w600, letterSpacing: 3, color: cs.primary)
              : Theme.of(context).textTheme.bodyLarge!.copyWith(fontSize: 17, fontWeight: FontWeight.w600, color: cs.primary),
        ),
      ],
    );
  }
}

/// Icon + title/detail card for one populated safety item (life raft, EPIRB,
/// fire suppression) in [_VesselSafetyCard]'s read view — same left-accent
/// card styling as [_FrequencyRow], so the two sections read consistently.
class _SafetyItem extends StatelessWidget {
  final IconData icon;
  final bool urgent;
  final String title;
  final String detail;
  const _SafetyItem(
      {required this.icon, required this.urgent,
       required this.title, required this.detail});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final em = cs;
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: urgent ? em.criticalColor : cs.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        fontWeight: FontWeight.w600,
                        color: urgent ? em.criticalColor : cs.onSurface)),
                Text(detail,
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        color: urgent ? cs.onErrorContainer : cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Coast Guard Frequencies Card ─────────────────────────────────────────────
/// Lists the vessel's up-to-4 saved VHF channel presets (empty slots hidden),
/// with slot 1 always styled as the "urgent" channel.
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
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
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

  /// Shows the edit dialog for the VHF preset in [slot] (1-4) and saves the
  /// result.
  void _showEditDialog(BuildContext context, int slot) {
    final v = context.read<ThemeProvider>();
    final labels = [v.vhf1Label, v.vhf2Label, v.vhf3Label, v.vhf4Label];
    final descs = [v.vhf1Desc, v.vhf2Desc, v.vhf3Desc, v.vhf4Desc];

    showDialog<({String label, String desc})?>(
      context: context,
      builder: (_) => _EditFrequencyDialog(
        initialLabel: labels[slot - 1],
        initialDesc: descs[slot - 1],
        onDelete: () => _deleteFrequency(context, v, slot),
      ),
    ).then((result) {
      if (result != null) v.setVhfEntry(slot, result.label, result.desc);
    });
  }

  /// Removes the preset in [slot], shifting later slots down so there's no
  /// gap (there's no per-slot "empty" concept beyond an empty label string),
  /// offering an "undo" snackbar action that re-inserts it at the same slot
  /// (shifting later slots back down to make room).
  void _deleteFrequency(BuildContext context, ThemeProvider v, int slot) {
    final labels = [v.vhf1Label, v.vhf2Label, v.vhf3Label, v.vhf4Label];
    final descs = [v.vhf1Desc, v.vhf2Desc, v.vhf3Desc, v.vhf4Desc];
    final removedLabel = labels[slot - 1];
    final removedDesc = descs[slot - 1];
    labels.removeAt(slot - 1);
    descs.removeAt(slot - 1);
    labels.add('');
    descs.add('');
    for (int i = 0; i < 4; i++) {
      v.setVhfEntry(i + 1, labels[i], descs[i]);
    }
    showUndoDeleteSnackBar(
      context,
      message: context.l10n.emergencyFrequencyDeleted(removedLabel),
      onUndo: () {
        final labels = [v.vhf1Label, v.vhf2Label, v.vhf3Label, v.vhf4Label];
        final descs = [v.vhf1Desc, v.vhf2Desc, v.vhf3Desc, v.vhf4Desc];
        labels.insert(slot - 1, removedLabel);
        descs.insert(slot - 1, removedDesc);
        // Only the first 4 are written back — this naturally drops the
        // trailing slot the delete above appended, undoing the shift.
        for (int i = 0; i < 4; i++) {
          v.setVhfEntry(i + 1, labels[i], descs[i]);
        }
      },
    );
  }
}

/// One VHF channel preset row; styled as an "urgent" (red) card for slot 1.
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
    final em = cs;
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
                    style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w600, color: urgent ? em.criticalColor : cs.primary)),
                Text(desc,
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
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
/// Dialog for adding a new VHF channel preset (channel label + description).
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
          style: Theme.of(context).textTheme.fieldValueProse.copyWith(color: cs.onSurface)),
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
/// Dialog for editing (or deleting) an existing VHF channel preset.
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
          style: Theme.of(context).textTheme.fieldValueProse.copyWith(color: cs.onSurface)),
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
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
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
            const SizedBox(height: 16),
            DangerOutlinedButton(
              icon: Icons.delete_outline,
              label: context.l10n.delete,
              onPressed: () {
                Navigator.pop(context);
                widget.onDelete();
              },
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Crew Medical Overview Card ───────────────────────────────────────────────
/// Tappable summary card for one crew member: name, blood-type badge, and
/// personal EPIRB note if set. Tapping opens [_CrewDetailSheet] with the
/// full medical record (allergies, conditions, remarks). Same left-accent
/// card styling as [_FrequencyRow]/[_SafetyItem], so all three sections read
/// consistently.
class _CrewMedicalCard extends StatelessWidget {
  final CrewMember member;
  const _CrewMedicalCard({required this.member});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final em = cs;
    final bloodType = member.bloodType ?? '';
    final personalEpirb = member.personalEpirb ?? '';

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showCrewDetail(context, member),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(8),
            border: Border(left: BorderSide(color: cs.primary, width: 4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      member.name,
                      style: Theme.of(context).textTheme.titleLarge!.copyWith(fontSize: 20, fontWeight: FontWeight.w500, color: cs.primary),
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
                              style: Theme.of(context).textTheme.labelSmall!.copyWith(fontSize: 8, letterSpacing: 0, color: cs.onErrorContainer)),
                          Text(bloodType,
                              style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onErrorContainer)),
                        ],
                      ),
                    ),
                ],
              ),
              if (personalEpirb.isNotEmpty)
                const SizedBox(height: 10),
              if (personalEpirb.isNotEmpty)
                _MedicalRow(
                    icon: Icons.sensors,
                    color: cs.secondary,
                    text: personalEpirb),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the full-medical-record bottom sheet for [member].
void _showCrewDetail(BuildContext context, CrewMember member) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _CrewDetailSheet(member: member),
  );
}

/// Bottom sheet listing every populated medical/personal field for one crew
/// member (blood group, allergies, conditions, personal EPIRB, remarks).
class _CrewDetailSheet extends StatelessWidget {
  final CrewMember member;
  const _CrewDetailSheet({required this.member});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    final rows = <(IconData, String, String)>[
      if (member.bloodType?.isNotEmpty == true)
        (Icons.bloodtype, l10n.crewFieldBloodGroup, member.bloodType!),
      if (member.allergies?.isNotEmpty == true)
        (Icons.heart_broken, l10n.crewFieldAllergies, member.allergies!),
      if (member.conditions?.isNotEmpty == true)
        (Icons.medication, l10n.crewFieldConditions, member.conditions!),
      if (member.personalEpirb?.isNotEmpty == true)
        (Icons.sensors, l10n.crewFieldPersonalEpirb, member.personalEpirb!),
      if (member.remarks?.isNotEmpty == true)
        (Icons.description, l10n.crewSectionRemarks, member.remarks!),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              member.name,
              style: Theme.of(context).textTheme.bodyLarge!.copyWith(fontSize: 24, fontWeight: FontWeight.w500, color: cs.primary),
            ),
            const SizedBox(height: 16),
            if (rows.isEmpty)
              Text(
                l10n.crewDetailNoInfo,
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    fontStyle: FontStyle.italic,
                    color: cs.onSurfaceVariant),
              )
            else
              ...rows.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(r.$1, size: 20,
                            color: r.$1 == Icons.bloodtype
                                ? cs.error
                                : cs.secondary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.$2.toUpperCase(),
                                style: Theme.of(context).textTheme.labelSmall!.copyWith(fontSize: 10, letterSpacing: 1.0, color: cs.mutedLabel),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                r.$3,
                                style: Theme.of(context).textTheme.fieldValueCompact.copyWith(color: cs.onSurface),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.primary,
                  side: BorderSide(color: cs.primary.withValues(alpha: 0.25)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(l10n.close),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Icon + text row used for the personal-EPIRB line in [_CrewMedicalCard].
class _MedicalRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _MedicalRow({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder shown when no crew is logged for today or the most recent
/// entry, with a shortcut to open that day's log if one exists.
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
            style: Theme.of(context).textTheme.bodySmall!.copyWith(
                color: cs.onSurfaceVariant,
                fontStyle: FontStyle.italic),
          ),
          if (latestEntry != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.pushNamed(
                  AppRoute.dayDetail,
                  pathParameters: {
                    'year': '${latestEntry.date.year}',
                    'month': '${latestEntry.date.month}',
                    'day': '${latestEntry.date.day}',
                  },
                ),
                icon: const Icon(Icons.auto_stories, size: 16),
                label: Text(l10n.emergencyOpenDayEntry),
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.primary,
                  side: BorderSide(color: cs.primary.withValues(alpha: 0.3)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  textStyle: Theme.of(context).textTheme.chipLabel,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
