import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

class ThemeProvider extends ChangeNotifier {
  static const _boxName = 'settings';
  static const _themeKey = 'theme_mode';
  static const _titleKey = 'logbuch_title';
  static const _weatherKey = 'weather_url';
  static const _installationIdKey = 'installation_id';
  static const _initialSyncDoneKey = 'initial_cloud_sync_done';
  static const _lastRouteKey = 'last_route';
  static const _lastRouteDateKey = 'last_route_date';

  late Box<String> _box;
  ThemeMode _mode = ThemeMode.system;
  String _title = 'Logbuch';
  String _weatherUrl = '';
  late String _installationId;

  ThemeMode get themeMode => _mode;
  String get logbuchTitle => _title;
  String get weatherUrl => _weatherUrl;
  String get installationId => _installationId;

  /// True on first launch after the cloud sync feature was introduced.
  bool get needsInitialSync =>
      _box.get(_initialSyncDoneKey) == null;

  void markInitialSyncDone() => _box.put(_initialSyncDoneKey, 'true');
  void resetInitialSync() => _box.delete(_initialSyncDoneKey);

  /// Returns the last visited route if it was saved today, otherwise '/'.
  String get lastRouteToday {
    if (_box.get(_lastRouteDateKey) != _todayStr()) return '/';
    return _box.get(_lastRouteKey) ?? '/';
  }

  void saveLastRoute(String route) {
    _box.put(_lastRouteKey, route);
    _box.put(_lastRouteDateKey, _todayStr());
  }

  static String _todayStr() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
    _mode = _fromString(_box.get(_themeKey, defaultValue: 'system')!);
    _title = _box.get(_titleKey, defaultValue: 'Logbuch')!;
    _weatherUrl = _box.get(_weatherKey, defaultValue: '')!;

    final existing = _box.get(_installationIdKey);
    if (existing != null && existing.isNotEmpty) {
      _installationId = existing;
    } else {
      _installationId = const Uuid().v4();
      _box.put(_installationIdKey, _installationId);
    }
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
