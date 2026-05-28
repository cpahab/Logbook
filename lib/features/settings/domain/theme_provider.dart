import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

class ThemeProvider extends ChangeNotifier {
  static const _boxName = 'settings';
  static const _themeKey = 'theme_mode';

  late Box<String> _box;
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get themeMode => _mode;

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
    _mode = _fromString(_box.get(_themeKey, defaultValue: 'system')!);
  }

  void setThemeMode(ThemeMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _box.put(_themeKey, _toString(mode));
    notifyListeners();
  }

  static ThemeMode _fromString(String v) => switch (v) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _toString(ThemeMode m) => switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        _ => 'system',
      };
}
