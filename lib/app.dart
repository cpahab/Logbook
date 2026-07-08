import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'app/theme/light_theme.dart';
import 'app/theme/dark_theme.dart';
import 'features/settings/domain/theme_provider.dart';
import 'l10n/app_localizations.dart';

/// Root widget. Wires the pre-built [router] into a `MaterialApp.router` and
/// wraps it with the light/dark themes and locale, both driven live by
/// [ThemeProvider] so a theme or language change anywhere in the app rebuilds
/// this widget immediately.
class Logbook extends StatelessWidget {
  final GoRouter router;
  const Logbook({super.key, required this.router});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ThemeProvider>();

    return MaterialApp.router(
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: provider.themeMode,
      locale: provider.materialLocale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
