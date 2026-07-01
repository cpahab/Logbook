import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../../../core/services/firestore_service.dart';
import '../../home/utils/filter_settings.dart';

class ThemeProvider extends ChangeNotifier {
  static const _boxName             = 'settings';
  static const _themeKey            = 'theme_mode';
  static const _titleKey            = 'logbuch_title';
  static const _weatherKey          = 'weather_url';
  static const _initialSyncDoneKey  = 'initial_cloud_sync_done';
  static const _lastRouteKey        = 'last_route';
  static const _lastRouteDateKey    = 'last_route_date';
  static const _vesselNameKey       = 'vessel_name';
  static const _vesselMmsiKey       = 'vessel_mmsi';
  static const _vesselCallSignKey   = 'vessel_call_sign';
  static const _lifeRaftKey         = 'life_raft_info';
  static const _epirbKey            = 'epirb_info';
  static const _fireSuppKey         = 'fire_supp_info';
  static const _vhf1LabelKey        = 'vhf_1_label';
  static const _vhf1DescKey         = 'vhf_1_desc';
  static const _vhf2LabelKey        = 'vhf_2_label';
  static const _vhf2DescKey         = 'vhf_2_desc';
  static const _vhf3LabelKey        = 'vhf_3_label';
  static const _vhf3DescKey         = 'vhf_3_desc';
  static const _vhf4LabelKey        = 'vhf_4_label';
  static const _vhf4DescKey         = 'vhf_4_desc';
  // Epoch-ms string: when settings were last changed on *this* device.
  static const _settingsModifiedKey = 'settings_modified_at_epoch';
  // Epoch-ms string: when UI state (month expansion) was last changed locally.
  static const _uiModifiedKey       = 'ui_modified_at_epoch';
  // Local-only (not cloud-synced) filter preferences.
  static const _filterModeKey              = 'filter_stationary_mode';
  static const _minStopMinutesKey          = 'filter_min_stop_minutes';
  static const _maxStopSpreadMKey          = 'filter_max_stop_spread_m';
  static const _detectColdStartKey         = 'filter_detect_cold_start';
  static const _coldStartSettleFactorKey   = 'filter_cold_start_settle_factor';
  static const _makingWayThresholdKnKey    = 'filter_making_way_threshold_kn';
  static const _topSpeedPercentileKey      = 'filter_top_speed_percentile';
  static const _maxSpeedKnKey              = 'filter_max_speed_kn';
  static const _showRawTrackKey            = 'debug_show_raw_track';
  static const _localeKey                  = 'locale';
  static const _lastUidKey                 = 'last_known_uid';
  static const _lastProjectIdKey           = 'last_known_project_id';

  late Box<String> _box;
  FirestoreService? _firestore;
  StreamSubscription<Map<String, String>?>? _settingsSub;
  StreamSubscription<Map<String, bool>?>?   _uiSub;

  ThemeMode _mode = ThemeMode.system;
  Locale _locale = const Locale('de');
  StationaryMode _filterMode        = StationaryMode.speed;
  double _minStopMinutes            = 5.0;
  double _maxStopSpreadM            = 30.0;
  bool   _detectColdStart           = true;
  double _coldStartSettleFactor     = 3.0;
  double _makingWayThresholdKn      = 1.0;
  double _topSpeedPercentile        = 0.99;
  double _maxSpeedKn                = 12.0;
  bool   _showRawTrack              = true;
  String _title = 'Logbuch';
  String _weatherUrl = '';
  String _vesselName = '';
  String _vesselMmsi = '';
  String _vesselCallSign = '';
  String _lifeRaftInfo = '';
  String _epirbInfo = '';
  String _fireSuppInfo = '';
  String _vhf1Label = 'Channel 16';
  String _vhf1Desc  = 'Distress · 156.800 MHz';
  String _vhf2Label = 'Channel 67';
  String _vhf2Desc  = 'Ship to Ship · 156.375 MHz';
  String _vhf3Label = 'Channel 06';
  String _vhf3Desc  = 'Search & Rescue · 156.300 MHz';
  String _vhf4Label = 'Channel 13';
  String _vhf4Desc  = 'Bridge to Bridge · 156.650 MHz';

  ThemeMode get themeMode               => _mode;
  Locale    get locale                  => _locale;
  String    get localeString            => _locale.languageCode == 'de' ? 'de_CH' : 'en_GB';
  StationaryMode get filterMode         => _filterMode;
  double get minStopMinutes             => _minStopMinutes;
  double get maxStopSpreadM             => _maxStopSpreadM;
  bool   get detectColdStart            => _detectColdStart;
  double get coldStartSettleFactor      => _coldStartSettleFactor;
  double get makingWayThresholdKn       => _makingWayThresholdKn;
  double get topSpeedPercentile         => _topSpeedPercentile;
  double get maxSpeedKn                 => _maxSpeedKn;
  bool   get showRawTrack               => _showRawTrack;
  FilterSettings get filterSettings => FilterSettings(
    stationaryMode:        _filterMode,
    minStopMinutes:        _minStopMinutes,
    maxStopSpreadM:        _maxStopSpreadM,
    detectColdStart:       _detectColdStart,
    coldStartSettleFactor: _coldStartSettleFactor,
    makingWayThresholdKn:  _makingWayThresholdKn,
    topSpeedPercentile:    _topSpeedPercentile,
    maxSpeedKn:            _maxSpeedKn,
  );
  String get logbuchTitle          => _title;
  String get weatherUrl         => _weatherUrl;
  String get vesselName         => _vesselName;
  String get vesselMmsi         => _vesselMmsi;
  String get vesselCallSign     => _vesselCallSign;
  String get lifeRaftInfo       => _lifeRaftInfo;
  String get epirbInfo          => _epirbInfo;
  String get fireSuppInfo       => _fireSuppInfo;
  String get vhf1Label          => _vhf1Label;
  String get vhf1Desc           => _vhf1Desc;
  String get vhf2Label          => _vhf2Label;
  String get vhf2Desc           => _vhf2Desc;
  String get vhf3Label          => _vhf3Label;
  String get vhf3Desc           => _vhf3Desc;
  String get vhf4Label          => _vhf4Label;
  String get vhf4Desc           => _vhf4Desc;
  String? get lastKnownUid        => _box.get(_lastUidKey);
  void setLastKnownUid(String uid) => _box.put(_lastUidKey, uid);

  String? get lastKnownProjectId          => _box.get(_lastProjectIdKey);
  void setLastKnownProjectId(String id)   => _box.put(_lastProjectIdKey, id);

  /// Returns whether [monthKey] (format `"yyyy-M"`) is expanded.
  /// Defaults to [defaultOpen] when the user has never explicitly set it.
  bool getMonthExpanded(String monthKey, {bool defaultOpen = false}) {
    final stored = _box.get('mex_$monthKey');
    if (stored == null) return defaultOpen;
    return stored == 'true';
  }

  void setMonthExpanded(String monthKey, bool expanded) {
    _box.put('mex_$monthKey', expanded.toString());
    _box.put(_uiModifiedKey, DateTime.now().millisecondsSinceEpoch.toString());
    _firestore?.saveUiState(_monthExpandedMap).catchError((_) {});
    notifyListeners();
  }

  Map<String, bool> get _monthExpandedMap {
    final map = <String, bool>{};
    for (final k in _box.keys) {
      if (k is String && k.startsWith('mex_')) {
        map[k.substring(4)] = _box.get(k) == 'true';
      }
    }
    return map;
  }

  DateTime? get _uiModifiedAt {
    final v = _box.get(_uiModifiedKey);
    if (v == null) return null;
    final ms = int.tryParse(v);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  bool get needsInitialSync => _box.get(_initialSyncDoneKey) == null;
  void markInitialSyncDone() => _box.put(_initialSyncDoneKey, 'true');
  void resetInitialSync()    => _box.delete(_initialSyncDoneKey);

  /// Resets all synced vessel / VHF settings to defaults in memory and Hive,
  /// cancels live Firestore streams, and clears modification timestamps.
  /// Call before [attachFirestore] when a different user account signs in so
  /// that stale data is never pushed to the new account's Firestore.
  Future<void> clearVesselSettings() async {
    await _settingsSub?.cancel();
    _settingsSub = null;
    await _uiSub?.cancel();
    _uiSub = null;

    _vesselName = '';  _vesselMmsi = '';  _vesselCallSign = '';
    _lifeRaftInfo = ''; _epirbInfo = ''; _fireSuppInfo = '';
    _vhf1Label = 'Channel 16'; _vhf1Desc  = 'Distress · 156.800 MHz';
    _vhf2Label = 'Channel 67'; _vhf2Desc  = 'Ship to Ship · 156.375 MHz';
    _vhf3Label = 'Channel 06'; _vhf3Desc  = 'Search & Rescue · 156.300 MHz';
    _vhf4Label = 'Channel 13'; _vhf4Desc  = 'Bridge to Bridge · 156.650 MHz';

    for (final k in [
      _vesselNameKey, _vesselMmsiKey, _vesselCallSignKey,
      _lifeRaftKey, _epirbKey, _fireSuppKey,
      _vhf1LabelKey, _vhf1DescKey, _vhf2LabelKey, _vhf2DescKey,
      _vhf3LabelKey, _vhf3DescKey, _vhf4LabelKey, _vhf4DescKey,
      _settingsModifiedKey, _uiModifiedKey,
    ]) {
      _box.delete(k);
    }
    // Clear month-expansion UI state.
    final mexKeys = _box.keys.where((k) => k is String && k.startsWith('mex_')).toList();
    for (final k in mexKeys) { _box.delete(k); }

    notifyListeners();
  }

  // Restoring the exact screen the user left is convenient within the same
  // day, but a route saved on an earlier day would reopen a stale context
  // (e.g. an old day view) that's more confusing than starting at home.
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

  // ── Local modification timestamp ───────────────────────────────────────────

  /// When settings were last modified on this device (null = never modified locally).
  DateTime? get _settingsModifiedAt {
    final v = _box.get(_settingsModifiedKey);
    if (v == null) return null;
    final ms = int.tryParse(v);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  void _markSettingsModified() =>
      _box.put(_settingsModifiedKey, DateTime.now().millisecondsSinceEpoch.toString());

  // ── Init ───────────────────────────────────────────────────────────────────

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
    _mode                  = _fromString(_box.get(_themeKey, defaultValue: 'system')!);
    _locale                = _parseLocale(_box.get(_localeKey, defaultValue: 'de')!);
    _filterMode            = _parseFilterMode(_box.get(_filterModeKey, defaultValue: 'speed')!);
    _minStopMinutes        = double.tryParse(_box.get(_minStopMinutesKey,         defaultValue: '5.0')!)  ?? 5.0;
    _maxStopSpreadM        = double.tryParse(_box.get(_maxStopSpreadMKey,         defaultValue: '30.0')!) ?? 30.0;
    _detectColdStart       = (_box.get(_detectColdStartKey,       defaultValue: 'true')!)  != 'false';
    _coldStartSettleFactor = double.tryParse(_box.get(_coldStartSettleFactorKey,  defaultValue: '3.0')!)  ?? 3.0;
    _makingWayThresholdKn  = double.tryParse(_box.get(_makingWayThresholdKnKey,   defaultValue: '1.0')!)  ?? 1.0;
    _topSpeedPercentile    = double.tryParse(_box.get(_topSpeedPercentileKey,      defaultValue: '0.99')!) ?? 0.99;
    _maxSpeedKn            = double.tryParse(_box.get(_maxSpeedKnKey,              defaultValue: '12.0')!) ?? 12.0;
    _showRawTrack          = (_box.get(_showRawTrackKey, defaultValue: 'true')!) != 'false';
    _title       = _box.get(_titleKey,       defaultValue: 'Logbuch')!;
    _weatherUrl  = _box.get(_weatherKey,     defaultValue: '')!;
    _vesselName      = _box.get(_vesselNameKey,     defaultValue: '')!;
    _vesselMmsi      = _box.get(_vesselMmsiKey,     defaultValue: '')!;
    _vesselCallSign  = _box.get(_vesselCallSignKey,  defaultValue: '')!;
    _lifeRaftInfo    = _box.get(_lifeRaftKey,        defaultValue: '')!;
    _epirbInfo       = _box.get(_epirbKey,           defaultValue: '')!;
    _fireSuppInfo    = _box.get(_fireSuppKey,         defaultValue: '')!;
    _vhf1Label = _box.get(_vhf1LabelKey, defaultValue: 'Channel 16')!;
    _vhf1Desc  = _box.get(_vhf1DescKey,  defaultValue: 'Distress · 156.800 MHz')!;
    _vhf2Label = _box.get(_vhf2LabelKey, defaultValue: 'Channel 67')!;
    _vhf2Desc  = _box.get(_vhf2DescKey,  defaultValue: 'Ship to Ship · 156.375 MHz')!;
    _vhf3Label = _box.get(_vhf3LabelKey, defaultValue: 'Channel 06')!;
    _vhf3Desc  = _box.get(_vhf3DescKey,  defaultValue: 'Search & Rescue · 156.300 MHz')!;
    _vhf4Label = _box.get(_vhf4LabelKey, defaultValue: 'Channel 13')!;
    _vhf4Desc  = _box.get(_vhf4DescKey,  defaultValue: 'Bridge to Bridge · 156.650 MHz')!;

  }

  // ── Non-synced setters ─────────────────────────────────────────────────────

  void setThemeMode(ThemeMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _box.put(_themeKey, _toString(mode));
    notifyListeners();
  }

  void setLocale(Locale locale) {
    if (_locale == locale) return;
    _locale = locale;
    _box.put(_localeKey, locale.languageCode);
    notifyListeners();
  }

  void setFilterMode(StationaryMode mode) {
    if (_filterMode == mode) return;
    _filterMode = mode;
    _box.put(_filterModeKey, mode.name);
    notifyListeners();
  }

  void setMinStopMinutes(double v) {
    if (_minStopMinutes == v) return;
    _minStopMinutes = v;
    _box.put(_minStopMinutesKey, v.toString());
    notifyListeners();
  }

  void setMaxStopSpreadM(double v) {
    if (_maxStopSpreadM == v) return;
    _maxStopSpreadM = v;
    _box.put(_maxStopSpreadMKey, v.toString());
    notifyListeners();
  }

  void setDetectColdStart(bool v) {
    if (_detectColdStart == v) return;
    _detectColdStart = v;
    _box.put(_detectColdStartKey, v.toString());
    notifyListeners();
  }

  void setColdStartSettleFactor(double v) {
    if (_coldStartSettleFactor == v) return;
    _coldStartSettleFactor = v;
    _box.put(_coldStartSettleFactorKey, v.toString());
    notifyListeners();
  }

  void setMakingWayThresholdKn(double v) {
    if (_makingWayThresholdKn == v) return;
    _makingWayThresholdKn = v;
    _box.put(_makingWayThresholdKnKey, v.toString());
    notifyListeners();
  }

  void setTopSpeedPercentile(double v) {
    if (_topSpeedPercentile == v) return;
    _topSpeedPercentile = v;
    _box.put(_topSpeedPercentileKey, v.toString());
    notifyListeners();
  }

  void setMaxSpeedKn(double v) {
    if (_maxSpeedKn == v) return;
    _maxSpeedKn = v;
    _box.put(_maxSpeedKnKey, v.toString());
    notifyListeners();
  }

  void setShowRawTrack(bool v) {
    if (_showRawTrack == v) return;
    _showRawTrack = v;
    _box.put(_showRawTrackKey, v.toString());
    notifyListeners();
  }

  void resetFilterDefaults() {
    _filterMode           = StationaryMode.speed;
    _minStopMinutes       = 5.0;
    _maxStopSpreadM       = 30.0;
    _detectColdStart      = true;
    _coldStartSettleFactor = 3.0;
    _makingWayThresholdKn = 1.0;
    _topSpeedPercentile   = 0.99;
    _maxSpeedKn           = 12.0;
    _box
      ..put(_filterModeKey,            StationaryMode.speed.name)
      ..put(_minStopMinutesKey,        '5.0')
      ..put(_maxStopSpreadMKey,        '30.0')
      ..put(_detectColdStartKey,       'true')
      ..put(_coldStartSettleFactorKey, '3.0')
      ..put(_makingWayThresholdKnKey,  '1.0')
      ..put(_topSpeedPercentileKey,    '0.99')
      ..put(_maxSpeedKnKey,            '12.0');
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

  // ── Synced vessel / VHF setters ────────────────────────────────────────────

  void setVesselName(String v) {
    final t = v.trim();
    if (_vesselName == t) return;
    _vesselName = t;
    _box.put(_vesselNameKey, t);
    _pushSettings();
    notifyListeners();
  }

  void setVesselMmsi(String v) {
    final t = v.trim();
    if (_vesselMmsi == t) return;
    _vesselMmsi = t;
    _box.put(_vesselMmsiKey, t);
    _pushSettings();
    notifyListeners();
  }

  void setVesselCallSign(String v) {
    final t = v.trim();
    if (_vesselCallSign == t) return;
    _vesselCallSign = t;
    _box.put(_vesselCallSignKey, t);
    _pushSettings();
    notifyListeners();
  }

  void setLifeRaftInfo(String v) {
    final t = v.trim();
    if (_lifeRaftInfo == t) return;
    _lifeRaftInfo = t;
    _box.put(_lifeRaftKey, t);
    _pushSettings();
    notifyListeners();
  }

  void setEpirbInfo(String v) {
    final t = v.trim();
    if (_epirbInfo == t) return;
    _epirbInfo = t;
    _box.put(_epirbKey, t);
    _pushSettings();
    notifyListeners();
  }

  void setFireSuppInfo(String v) {
    final t = v.trim();
    if (_fireSuppInfo == t) return;
    _fireSuppInfo = t;
    _box.put(_fireSuppKey, t);
    _pushSettings();
    notifyListeners();
  }

  void setVhfEntry(int idx, String label, String desc) {
    final l = label.trim();
    final d = desc.trim();
    switch (idx) {
      case 1: _vhf1Label = l; _vhf1Desc = d; _box.put(_vhf1LabelKey, l); _box.put(_vhf1DescKey, d);
      case 2: _vhf2Label = l; _vhf2Desc = d; _box.put(_vhf2LabelKey, l); _box.put(_vhf2DescKey, d);
      case 3: _vhf3Label = l; _vhf3Desc = d; _box.put(_vhf3LabelKey, l); _box.put(_vhf3DescKey, d);
      case 4: _vhf4Label = l; _vhf4Desc = d; _box.put(_vhf4LabelKey, l); _box.put(_vhf4DescKey, d);
    }
    _pushSettings();
    notifyListeners();
  }

  // ── Firestore sync ─────────────────────────────────────────────────────────

  /// Attaches Firestore and starts syncing settings.
  ///
  /// Conflict resolution:
  ///   • [initialSync] = true  → push local as migration, then pull remote.
  ///   • Otherwise: compare the remote server `updatedAt` with the local
  ///     modification timestamp.  Whichever is newer wins.  If no remote data
  ///     exists yet, push local.
  ///
  /// A real-time stream listener is started so changes from another device
  /// appear immediately while the app is running.
  Future<void> attachFirestore(FirestoreService service,
      {bool initialSync = false}) async {
    _firestore = service;

    await _settingsSub?.cancel();
    _settingsSub = null;

    try {
      if (initialSync) {
        // Only push if the user has actually modified settings on this device.
        // A fresh install — or after clearVesselSettings() on account switch —
        // has no modification timestamp, so we skip the push and let
        // localMod stay null, which makes remoteIsNewer unconditionally true.
        if (_settingsModifiedAt != null) {
          await service.saveSettings(_toSettingsMap());
          _markSettingsModified();
        }
      }

      final (:data, :updatedAt) = await service.fetchSettingsWithMeta();

      if (data == null) {
        // Nothing on the server yet — push local.
        await service.saveSettings(_toSettingsMap());
        _markSettingsModified();
      } else {
        final localMod = _settingsModifiedAt;
        final remoteIsNewer = localMod == null ||
            (updatedAt != null && updatedAt.isAfter(localMod));

        if (remoteIsNewer) {
          _applyRemoteSettings(data);
        } else {
          // Local is newer — push it.
          await service.saveSettings(_toSettingsMap());
        }
      }
    } catch (_) {
      // Offline — continue with local data.
    }

    // Real-time listener: apply remote changes while the app is running.
    // Skip the echo that comes back from our own pushes by comparing values.
    _settingsSub = service.settingsChanges().listen((remote) {
      if (remote == null) return;
      if (_mapsEqual(_toSettingsMap(), remote)) return;
      _applyRemoteSettings(remote);
    }, onError: (_) {});

    // ── UI state (month expansion) sync ───────────────────────────────────────
    await _uiSub?.cancel();
    _uiSub = null;
    try {
      final (:data, :updatedAt) = await service.fetchUiStateWithMeta();
      if (data == null) {
        final local = _monthExpandedMap;
        if (local.isNotEmpty) await service.saveUiState(local);
      } else {
        final localMod = _uiModifiedAt;
        final remoteIsNewer = localMod == null ||
            (updatedAt != null && updatedAt.isAfter(localMod));
        if (remoteIsNewer) {
          _applyRemoteUiState(data);
        } else {
          await service.saveUiState(_monthExpandedMap);
        }
      }
    } catch (_) {}

    _uiSub = service.uiStateChanges().listen((remote) {
      if (remote == null) return;
      _applyRemoteUiState(remote);
    }, onError: (_) {});
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Map<String, String> _toSettingsMap() => {
        _vesselNameKey:      _vesselName,
        _vesselMmsiKey:      _vesselMmsi,
        _vesselCallSignKey:  _vesselCallSign,
        _lifeRaftKey:        _lifeRaftInfo,
        _epirbKey:           _epirbInfo,
        _fireSuppKey:        _fireSuppInfo,
        _vhf1LabelKey:       _vhf1Label,
        _vhf1DescKey:        _vhf1Desc,
        _vhf2LabelKey:       _vhf2Label,
        _vhf2DescKey:        _vhf2Desc,
        _vhf3LabelKey:       _vhf3Label,
        _vhf3DescKey:        _vhf3Desc,
        _vhf4LabelKey:       _vhf4Label,
        _vhf4DescKey:        _vhf4Desc,
      };

  void _pushSettings() {
    _markSettingsModified();
    _firestore?.saveSettings(_toSettingsMap()).catchError((_) {});
  }

  void _applyRemoteSettings(Map<String, String> r) {
    var changed = false;
    void apply(String key, String current, void Function(String) set) {
      final v = r[key];
      if (v != null && v != current) { set(v); changed = true; }
    }
    apply(_vesselNameKey,     _vesselName,     (v) { _vesselName = v;     _box.put(_vesselNameKey, v); });
    apply(_vesselMmsiKey,     _vesselMmsi,     (v) { _vesselMmsi = v;     _box.put(_vesselMmsiKey, v); });
    apply(_vesselCallSignKey, _vesselCallSign, (v) { _vesselCallSign = v;  _box.put(_vesselCallSignKey, v); });
    apply(_lifeRaftKey,       _lifeRaftInfo,   (v) { _lifeRaftInfo = v;    _box.put(_lifeRaftKey, v); });
    apply(_epirbKey,          _epirbInfo,      (v) { _epirbInfo = v;       _box.put(_epirbKey, v); });
    apply(_fireSuppKey,       _fireSuppInfo,   (v) { _fireSuppInfo = v;    _box.put(_fireSuppKey, v); });
    apply(_vhf1LabelKey,      _vhf1Label,      (v) { _vhf1Label = v;       _box.put(_vhf1LabelKey, v); });
    apply(_vhf1DescKey,       _vhf1Desc,       (v) { _vhf1Desc = v;        _box.put(_vhf1DescKey, v); });
    apply(_vhf2LabelKey,      _vhf2Label,      (v) { _vhf2Label = v;       _box.put(_vhf2LabelKey, v); });
    apply(_vhf2DescKey,       _vhf2Desc,       (v) { _vhf2Desc = v;        _box.put(_vhf2DescKey, v); });
    apply(_vhf3LabelKey,      _vhf3Label,      (v) { _vhf3Label = v;       _box.put(_vhf3LabelKey, v); });
    apply(_vhf3DescKey,       _vhf3Desc,       (v) { _vhf3Desc = v;        _box.put(_vhf3DescKey, v); });
    apply(_vhf4LabelKey,      _vhf4Label,      (v) { _vhf4Label = v;       _box.put(_vhf4LabelKey, v); });
    apply(_vhf4DescKey,       _vhf4Desc,       (v) { _vhf4Desc = v;        _box.put(_vhf4DescKey, v); });
    if (changed) notifyListeners();
  }

  void _applyRemoteUiState(Map<String, bool> remote) {
    var changed = false;
    for (final e in remote.entries) {
      final key = 'mex_${e.key}';
      final want = e.value.toString();
      if (_box.get(key) != want) {
        _box.put(key, want);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  static bool _mapsEqual(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (a[k] != b[k]) return false;
    }
    return true;
  }

  static Locale _parseLocale(String v) =>
      v == 'en' ? const Locale('en') : const Locale('de');

  static ThemeMode _fromString(String v) => switch (v) {
        'light' => ThemeMode.light,
        'dark'  => ThemeMode.dark,
        _       => ThemeMode.system,
      };

  static String _toString(ThemeMode m) => switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark  => 'dark',
        _               => 'system',
      };

  static StationaryMode _parseFilterMode(String v) =>
      StationaryMode.values.firstWhere(
        (m) => m.name == v,
        orElse: () => StationaryMode.speed,
      );
}
