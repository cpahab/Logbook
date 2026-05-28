import 'package:flutter/material.dart';

const _seed = Color(0xFF0D3B8E);

final ThemeData darkTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: Brightness.dark,
    primary: const Color(0xFF7DB3F0),
    secondary: const Color(0xFF48B0D8),
    tertiary: const Color(0xFF4CC9D4),
  ),
  appBarTheme: const AppBarTheme(
    centerTitle: false,
    elevation: 0,
    scrolledUnderElevation: 2,
  ),
  cardTheme: CardThemeData(
    elevation: 2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  ),
);
