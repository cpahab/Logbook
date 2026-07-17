import 'package:flutter/material.dart';

import '../../../app/theme/theme_extensions.dart';
import '../../../l10n/l10n_extension.dart';

// Owns its TextEditingController so disposal is always tied to the widget
// lifecycle — avoids "controller used after dispose" when the dialog builder
// is invoked one final time during the closing animation.
class EditTextDialog extends StatefulWidget {
  final String title;
  final String? initialText;
  final String hintText;

  const EditTextDialog({
    super.key,
    required this.title,
    this.initialText,
    required this.hintText,
  });

  @override
  State<EditTextDialog> createState() => _EditTextDialogState();
}

class _EditTextDialogState extends State<EditTextDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      title: Text(
        widget.title,
        style: Theme.of(context).textTheme.fieldValueProse.copyWith(color: cs.onSurface),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: TextField(
          controller: _ctrl,
          minLines: 8,
          maxLines: 14,
          keyboardType: TextInputType.multiline,
          autofocus: true,
          style: TextStyle(color: cs.onSurface),
          decoration: InputDecoration(
            hintText: widget.hintText,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          icon: const Icon(Icons.anchor, size: 18),
          label: Text(context.l10n.saveChanges),
        ),
      ],
    );
  }
}
