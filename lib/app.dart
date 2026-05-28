import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app/router.dart';
import 'app/theme/light_theme.dart';
import 'app/theme/dark_theme.dart';
import 'features/settings/domain/theme_provider.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeProvider>().themeMode;

    return MaterialApp.router(
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
    );
  }
}
