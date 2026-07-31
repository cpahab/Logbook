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
    final screenHeight = MediaQuery.of(context).size.height;
    return AlertDialog(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      title: Text(
        widget.title,
        style: Theme.of(context).textTheme.fieldValueProse.copyWith(color: cs.onSurface),
      ),
      content: SizedBox(
        width: double.maxFinite,
        // A fixed minLines/maxLines range eats a disproportionate share of
        // a small screen once the AlertDialog chrome and keyboard are
        // accounted for, so size the field relative to the viewport instead.
        height: (screenHeight * 0.5).clamp(120.0, 400.0),
        child: TextField(
          controller: _ctrl,
          expands: true,
          maxLines: null,
          minLines: null,
          keyboardType: TextInputType.multiline,
          textAlignVertical: TextAlignVertical.top,
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
        // Forces Cancel/Save onto a single row rather than letting the
        // default AlertDialog action layout stack them (full-width Save
        // below Cancel) once they don't fit a narrow screen.
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  context.l10n.cancel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(context, _ctrl.text),
                icon: const Icon(Icons.anchor, size: 18),
                label: Text(
                  context.l10n.save,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
