import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

class ThemeProvider extends ChangeNotifier {
  static const _boxName = 'settings';
  static const _themeKey = 'theme_mode';
  static const _titleKey = 'logbuch_title';
  static const _weatherKey = 'weather_url';

  late Box<String> _box;
  ThemeMode _mode = ThemeMode.system;
  String _title = 'Logbuch';
  String _weatherUrl = '';

  ThemeMode get themeMode => _mode;
  String get logbuchTitle => _title;
  String get weatherUrl => _weatherUrl;

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
    _mode = _fromString(_box.get(_themeKey, defaultValue: 'system')!);
    _title = _box.get(_titleKey, defaultValue: 'Logbuch')!;
    _weatherUrl = _box.get(_weatherKey, defaultValue: '')!;
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

  void setWeatherUrl(String url) {
    final trimmed = url.trim();
    if (_weatherUrl == trimmed) return;
    _weatherUrl = trimmed;
    _box.put(_weatherKey, trimmed);
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
