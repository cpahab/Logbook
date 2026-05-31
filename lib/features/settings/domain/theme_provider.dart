import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

class ThemeProvider extends ChangeNotifier {
  static const _boxName = 'settings';
  static const _themeKey = 'theme_mode';
  static const _titleKey = 'logbuch_title';

  late Box<String> _box;
  ThemeMode _mode = ThemeMode.system;
  String _title = 'Logbuch';

  ThemeMode get themeMode => _mode;
  String get logbuchTitle => _title;

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
    _mode = _fromString(_box.get(_themeKey, defaultValue: 'system')!);
    _title = _box.get(_titleKey, defaultValue: 'Logbuch')!;
  }

  void setThemeMode(ThemeMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _box.put(_themeKey, _toString(mode));
    notifyListeners();
  }

  void setLogbuchTitle(String title) {
    final trimmed = title.trim().isEmpty ? 'Logbuch' : title.trim();
    if (_title == trimmed) return;
    _title = trimmed;
    _box.put(_titleKey, trimmed);
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
