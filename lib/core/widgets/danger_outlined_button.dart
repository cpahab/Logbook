import 'package:flutter/material.dart';

import '../../app/theme/theme_extensions.dart';

/// Full-width, error-colored outlined button for a destructive action inside
/// a dialog (remove/delete). Shared so every dialog's delete affordance
/// looks and reads the same — previously Crew Roster/per-day crew used this
/// exact style while Emergency Manifest's contact/frequency dialogs used an
/// unrelated small inline text button, an inconsistency this widget removes.
class DangerOutlinedButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const DangerOutlinedButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.error,
          side: BorderSide(color: cs.error.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: Theme.of(context).textTheme.fieldValueCompact,
        ),
        icon: Icon(icon, size: 20),
        label: Text(label),
      ),
    );
  }
}
