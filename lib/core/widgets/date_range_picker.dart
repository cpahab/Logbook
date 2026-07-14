import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/settings/domain/theme_provider.dart';

/// Shows the OS date-range picker with the app's standard configuration
/// (earliest selectable date 2000, latest today, locale from
/// [ThemeProvider], text scaling clamped to avoid layout overflow at large
/// accessibility sizes). Returns null if the user cancels.
///
/// [initialRange] seeds the picker's starting selection — pass the
/// currently active range if there is one, else it defaults to the last
/// calendar month.
Future<DateTimeRange?> pickDateRange(
  BuildContext context, {
  required DateTimeRange? initialRange,
}) {
  final now = DateTime.now();
  final initial = initialRange ??
      DateTimeRange(
          start: DateTime(now.year, now.month - 1, now.day), end: now);
  return showDateRangePicker(
    context: context,
    firstDate: DateTime(2000),
    lastDate: now,
    initialDateRange: initial,
    locale: context.read<ThemeProvider>().materialLocale,
    builder: (context, child) => MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.0,
      child: child!,
    ),
  );
}
