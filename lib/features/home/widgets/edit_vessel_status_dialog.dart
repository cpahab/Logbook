import 'package:flutter/material.dart';

import '../../../app/theme/theme_extensions.dart';
import '../../../l10n/l10n_extension.dart';

/// Shows the oil/fuel-slider + keel-toggle dialog. Returns the chosen
/// values, or `null` if the user cancelled.
Future<({int oil, int fuel, bool? keel})?> showEditVesselStatusDialog(
  BuildContext context, {
  required int initialOil,
  required int initialFuel,
  required bool? initialKeel,
}) async {
  int oilVal = initialOil;
  int fuelVal = initialFuel;
  bool? keelVal = initialKeel;
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text(
            context.l10n.vesselStatusTitle,
            style: Theme.of(context).textTheme.fieldValueProse.copyWith(color: cs.onSurface),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(context.l10n.vesselOilLabel, style: TextStyle(color: cs.onSurface)),
                  Text('$oilVal%',
                      style: Theme.of(ctx).textTheme.bodyMedium!.copyWith(
                          fontWeight: FontWeight.w600, color: cs.onSurface)),
                ],
              ),
              Slider(
                value: oilVal.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                onChanged: (v) => setS(() => oilVal = v.round()),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(context.l10n.vesselFuelLabel, style: TextStyle(color: cs.onSurface)),
                  Text('$fuelVal%',
                      style: Theme.of(ctx).textTheme.bodyMedium!.copyWith(
                          fontWeight: FontWeight.w600, color: cs.onSurface)),
                ],
              ),
              Slider(
                value: fuelVal.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                onChanged: (v) => setS(() => fuelVal = v.round()),
              ),
              const Divider(height: 24),
              Row(
                children: [
                  Text(context.l10n.entryDialogKeelLabel, style: TextStyle(color: cs.onSurface)),
                  const Spacer(),
                  Text(
                    keelVal == null ? '—' : (keelVal! ? context.l10n.vesselKeelDown : context.l10n.vesselKeelUp),
                    style: Theme.of(ctx).textTheme.bodyMedium!.copyWith(
                        fontWeight: FontWeight.w600, color: cs.onSurface),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: keelVal ?? false,
                    onChanged: (v) => setS(() => keelVal = v),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.anchor, size: 18),
              label: Text(context.l10n.saveChanges),
            ),
          ],
        );
      },
    ),
  );
  if (saved != true) return null;
  return (oil: oilVal, fuel: fuelVal, keel: keelVal);
}
