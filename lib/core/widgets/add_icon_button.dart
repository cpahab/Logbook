import 'package:flutter/material.dart';

import '../../l10n/l10n_extension.dart';

/// Small circular "+" icon button for adding a new item to a compact list
/// section (e.g. next to a card's section header) — the consistent "add"
/// trigger shared by Emergency Contacts and VHF Frequencies. Not every list
/// in the app uses this: a dedicated full-screen list (Crew Roster) keeps
/// its own FloatingActionButton, and an inline-entry list (equipment
/// states) has no dialog to trigger in the first place — this widget is
/// specifically for "open a dialog to add one item" inside a shared
/// multi-section screen, where a FAB isn't a fit.
class AddIconButton extends StatelessWidget {
  final VoidCallback onTap;
  const AddIconButton({super.key, required this.onTap});

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
