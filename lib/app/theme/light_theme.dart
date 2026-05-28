import 'package:flutter/material.dart';

const _seed = Color(0xFF0D3B8E);

final ThemeData lightTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: Brightness.light,
    primary: const Color(0xFF0D3B8E),
    secondary: const Color(0xFF0077B6),
    tertiary: const Color(0xFF2196A6),
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
