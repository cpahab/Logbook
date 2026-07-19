import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:gpx/gpx.dart';
import 'package:hive/hive.dart';

import '../domain/day_entry.dart';
import '../domain/crew_member.dart';
import '../domain/timeline_entry.dart';
import '../domain/daily_track.dart';
import '../domain/track_point.dart';
import '../utils/gpx_parser.dart';
import '../../../core/services/firestore_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/utils/retry_with_backoff.dart';

/// Local (Hive) + cloud (Firestore/Storage) store for day entries, GPS
/// tracks, and the crew roster — the app's central data repository. Local
/// writes are always immediate and authoritative; Firestore pushes are
/// debounced and merge only the fields that changed, so two devices editing
/// the same day around the same time can't silently clobber each other's
/// unrelated edits (see [saveEntry] and [attachFirestore] for the full
/// sync strategy, including the per-entry `updatedAt` staleness comparison
/// that replaced an earlier global-timestamp comparison bug).
class HomeRepository extends ChangeNotifier {
  // ── Hive boxes ─────────────────────────────────────────────────────────────
  late Box<DayEntry> _dayBox;
  late Box<DailyTrack> _trackBox;
  late Box<CrewMember> _rosterBox;

  /// Stores small per-date sync bookkeeping, keyed by string:
  ///   'last_sync_at'              → epoch-ms of the last successful Firestore pull
  ///   'entry_{isoDate}_at'        → epoch-ms of the last *local* edit for that entry
  ///   'pending_delete_{isoDate}'  → a delete was requested for that date but
  ///                                 not yet confirmed pushed to Firestore/Storage
  ///                                 (see _pushPendingDelete) — retried on every
  ///                                 attachFirestore/forceSync/reattachAndSync.
  late Box<int> _syncStateBox;

  // ── In-memory caches ───────────────────────────────────────────────────────
  final Map<DateTime, DayEntry> _entries = {};
  final Map<DateTime, DailyTrack> dailyTracks = {};

  // ── Cloud services (null until attach* is called) ──────────────────────────
  FirestoreService? _firestore;
  StorageService? _storage;

  // ── Debounce timers (keyed by entry date) ──────────────────────────────────
  final Map<DateTime, Timer> _syncTimers = {};

  /// Field names accumulated across debounced saveEntry() calls to the same
  /// date, so a quick sequence of edits to different fields still pushes all
  /// of them once the debounce timer fires (rather than only the last call's
  /// fields).
  final Map<DateTime, Set<String>> _pendingSyncFields = {};

  // ── Real-time Firestore stream subscriptions ───────────────────────────────
  StreamSubscription<void>? _entrySub;
  StreamSubscription<void>? _rosterSub;

  // ── Public getters ─────────────────────────────────────────────────────────

  /// Every day entry, oldest first.
  List<DayEntry> get entries =>
      _entries.values.toList()..sort((a, b) => a.date.compareTo(b.date));

  /// The most recently logged oil/fuel level and keel position, each
  /// resolved independently (so if one field was never set on the latest
  /// entries, it falls back further back in time than the others).
  ({int? oilLevel, int? fuelLevel, bool? keelDown}) get lastVesselStatus {
    int? oil;
    int? fuel;
    bool? keel;
    for (final e in entries.reversed) {
      oil  ??= e.oilLevel;
      fuel ??= e.fuelLevel;
      keel ??= e.keelDown;
      if (oil != null && fuel != null && keel != null) break;
    }
    return (oilLevel: oil, fuelLevel: fuel, keelDown: keel);
  }

  /// The persistent crew roster (features/home/presentation/crew_roster_screen.dart),
  /// sorted alphabetically by name — distinct from any single day's crew list.
  List<CrewMember> get roster {
    final members = _rosterBox.values.toList();
    members.sort((a, b) => a.name.compareTo(b.name));
    return members;
  }

  /// Finds this person's current roster record by [id], if one exists.
  /// Used to resolve personal/medical fields to their latest known values
  /// wherever a day-entry's embedded crew copy (which is only a snapshot
  /// from whenever they were added) is displayed.
  CrewMember? rosterMemberById(String? id) {
    if (id == null) return null;
    for (final m in _rosterBox.values) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// The crew list from the most recent day entry that logged one, copied
  /// fresh (not aliased) — used to prefill a new day's crew.
  List<CrewMember> get lastCrew {
    for (final e in entries.reversed) {
      if (e.crew.isNotEmpty) {
        return e.crew
            .map((m) => CrewMember(
                  name: m.name,
                  bloodType: m.bloodType,
                  allergies: m.allergies,
                  conditions: m.conditions,
                  remarks: m.remarks,
                  id: m.id,
                  personalEpirb: m.personalEpirb,
                ))
            .toList();
      }
    }
    return [];
  }

  // ── Sync-state helpers ─────────────────────────────────────────────────────

  static String _syncKey(DateTime date) =>
      'entry_${date.toIso8601String()}_at';

  /// Records the current wall-clock time as the last local edit for [date].
  void _recordLocalEdit(DateTime date) =>
      _syncStateBox.put(_syncKey(date), DateTime.now().millisecondsSinceEpoch);

  /// Returns when [date]'s entry was last edited locally, or null if never.
  DateTime? _localEditTime(DateTime date) {
    final ms = _syncStateBox.get(_syncKey(date));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  void _clearLocalEdit(DateTime date) => _syncStateBox.delete(_syncKey(date));

  static const _pendingDeletePrefix = 'pending_delete_';
  static String _pendingDeleteKey(DateTime date) =>
      '$_pendingDeletePrefix${date.toIso8601String()}';

  /// Marks [date] as having a delete that hasn't been confirmed pushed to
  /// Firestore/Storage yet — see [_pushPendingDelete].
  void _recordPendingDelete(DateTime date) =>
      _syncStateBox.put(_pendingDeleteKey(date), 1);

  void _clearPendingDelete(DateTime date) =>
      _syncStateBox.delete(_pendingDeleteKey(date));

  Iterable<DateTime> _pendingDeleteDates() => _syncStateBox.keys
      .where((k) => k.toString().startsWith(_pendingDeletePrefix))
      .map((k) => DateTime.parse(
          k.toString().substring(_pendingDeletePrefix.length)));

  /// Test-only visibility into which dates still have an unconfirmed delete.
  @visibleForTesting
  Iterable<DateTime> get pendingDeleteDatesForTesting => _pendingDeleteDates();

  /// Attempts to push [date]'s deletion to Firestore (as a tombstone, see
  /// FirestoreService.deleteEntry) and Storage independently, only clearing
  /// the pending marker once both are confirmed (or don't apply / the
  /// Storage object is already gone — a missing object on delete is the
  /// desired end state, not a failure). Safe to call repeatedly: retried on
  /// every attachFirestore/forceSync/reattachAndSync until it succeeds.
  Future<void> _pushPendingDelete(DateTime date) async {
    var entryOk = _firestore == null;
    var trackOk = _storage == null;
    if (!entryOk) {
      try {
        await _firestore!.deleteEntry(date);
        entryOk = true;
      } catch (_) {}
    }
    if (!trackOk) {
      try {
        await _storage!.deleteTrack(date);
        trackOk = true;
      } on FirebaseException catch (e) {
        trackOk = e.code == 'object-not-found';
      } catch (_) {}
    }
    if (entryOk && trackOk) _clearPendingDelete(date);
  }

  /// The timestamp of the last successful pull from Firestore.
  /// Defaults to the Unix epoch so the first incremental pull fetches everything.
  DateTime get _lastSyncAt {
    final ms = _syncStateBox.get('last_sync_at');
    return ms == null
        ? DateTime.fromMillisecondsSinceEpoch(0)
        : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  void _setLastSyncAt() =>
      _syncStateBox.put('last_sync_at', DateTime.now().millisecondsSinceEpoch);

  // ── Initialization ─────────────────────────────────────────────────────────

  /// Opens every Hive box this repository owns and loads their contents
  /// into the in-memory caches. Must complete before any other method is called.
  ///
  /// [datasetSuffix] is null for the default dataset (today's exact box
  /// names — cloud users, or local mode before any local logbook is chosen)
  /// or a local logbook id for a non-default local logbook (see
  /// [switchLocalDataset] and `LocalLogbookService`).
  Future<void> init({String? datasetSuffix}) async {
    final opened = await _openBoxes(datasetSuffix);
    _dayBox       = opened.dayBox;
    _trackBox     = opened.trackBox;
    _rosterBox    = opened.rosterBox;
    _syncStateBox = opened.syncStateBox;

    for (final e in _dayBox.values) { _entries[e.date] = e; }
    for (final t in _trackBox.values) { dailyTracks[t.day] = t; }

    notifyListeners();
  }

  static Future<
      ({
        Box<DayEntry> dayBox,
        Box<DailyTrack> trackBox,
        Box<CrewMember> rosterBox,
        Box<int> syncStateBox
      })> _openBoxes(String? datasetSuffix) async {
    final s = datasetSuffix == null ? '' : '_$datasetSuffix';
    return (
      dayBox:       await Hive.openBox<DayEntry>('daily_entries$s'),
      trackBox:     await Hive.openBox<DailyTrack>('daily_tracks$s'),
      rosterBox:    await Hive.openBox<CrewMember>('crew_roster$s'),
      syncStateBox: await Hive.openBox<int>('entry_sync_state$s'),
    );
  }

  /// Switches this repository to a different local logbook's dataset. Opens
  /// [newLogbookId]'s boxes and swaps them in *before* closing the old ones,
  /// so [roster]/[rosterMemberById] — which read straight from the Hive box
  /// on every call, not from an in-memory cache — can never observe a closed
  /// box, even if a widget rebuild lands mid-switch. Only meaningful in
  /// local mode — cloud logbook switching instead overwrites the single
  /// default dataset via [reattachAndSync].
  Future<void> switchLocalDataset(String newLogbookId) async {
    await _entrySub?.cancel();
    _entrySub = null;
    await _rosterSub?.cancel();
    _rosterSub = null;
    for (final t in _syncTimers.values) { t.cancel(); }
    _syncTimers.clear();
    _pendingSyncFields.clear();

    final oldDayBox = _dayBox;
    final oldTrackBox = _trackBox;
    final oldRosterBox = _rosterBox;
    final oldSyncStateBox = _syncStateBox;

    final opened = await _openBoxes(newLogbookId.isEmpty ? null : newLogbookId);
    _dayBox       = opened.dayBox;
    _trackBox     = opened.trackBox;
    _rosterBox    = opened.rosterBox;
    _syncStateBox = opened.syncStateBox;

    _entries.clear();
    dailyTracks.clear();
    for (final e in _dayBox.values) { _entries[e.date] = e; }
    for (final t in _trackBox.values) { dailyTracks[t.day] = t; }

    notifyListeners();

    await oldDayBox.close();
    await oldTrackBox.close();
    await oldRosterBox.close();
    await oldSyncStateBox.close();
  }

  // ── Firestore attachment ───────────────────────────────────────────────────

  /// Attaches Firestore and starts syncing.
  ///
  /// On every call (startup or reconnect):
  ///   1. Push any entries edited locally since the last successful pull.
  ///   2. Pull all entries whose server `updatedAt` is newer than the last pull.
  ///      (First-ever sync with [initialSync]=true pushes all local entries and
  ///       pulls only missing ones, preserving data already on both devices.)
  ///   3. Subscribe to the Firestore collection for live updates while the app
  ///      is running.
  Future<void> attachFirestore(FirestoreService service,
      {bool initialSync = false}) async {
    _firestore = service;

    // Cancel any previous stream subscription (e.g. after reattach).
    await _entrySub?.cancel();
    _entrySub = null;

    if (initialSync) {
      try {
        // ── Step 0: retry any deletes that never got confirmed pushed ────────
        // Must run before Step 2's pull — otherwise a pull could re-fetch the
        // still-undeleted server doc and resurrect it locally before this
        // device's own tombstone has a chance to land.
        for (final date in _pendingDeleteDates().toList()) {
          await _pushPendingDelete(date);
        }

        // ── Step 1: push every local entry ───────────────────────────────────
        for (final e in _entries.values) {
          await service.saveEntry(e);
        }

        // ── Step 2: pull remote changes ──────────────────────────────────────
        // Conservative first sync: pull only entries absent locally to avoid
        // overwriting any data already present on this device.
        final remote = await service.fetchMissingEntries(_entries.keys.toSet());
        var changed = false;
        for (final e in remote) {
          if (await applyIncomingEntry(e)) changed = true;
        }
        if (changed) notifyListeners();

        _setLastSyncAt();
      } catch (_) {
        // Offline or timeout — local data remains available.
      }
    } else {
      await _refreshEntriesIncremental(service);
    }

    // ── Step 3: real-time listener ────────────────────────────────────────────
    // The stream emits the full collection on first subscription, then only
    // changed documents.  Both cases are handled by _applyRemoteEntries.
    _entrySub = service
        .entryChanges()
        .asyncMap(_applyRemoteEntries)
        .listen((_) {}, onError: (_) {});

    // ── Step 4: roster sync ───────────────────────────────────────────────────
    try {
      final remote = await service.fetchRoster();
      if (remote.isNotEmpty) {
        await _applyRemoteRoster(remote);
      }
    } catch (_) {}

    await _rosterSub?.cancel();
    _rosterSub = service
        .rosterChanges()
        .asyncMap(_applyRemoteRoster)
        .listen((_) {}, onError: (_) {});
  }

  /// The incremental (non-initial-sync) push-then-pull [attachFirestore]
  /// itself runs: push only entries locally edited since the last sync,
  /// pull only entries the server says changed since then, apply, and stamp
  /// the new sync time. Deliberately NOT [forceSync] — that unconditionally
  /// pushes every local entry and re-downloads everything, which is the
  /// right tool for a manual "something's wrong, force a full resync"
  /// action but far too expensive to run on every screen visit.
  Future<void> _refreshEntriesIncremental(FirestoreService service) async {
    try {
      final lastSync = _lastSyncAt;

      for (final date in _pendingDeleteDates().toList()) {
        await _pushPendingDelete(date);
      }

      for (final e in _entries.values) {
        final editAt = _localEditTime(e.date);
        if (editAt != null && editAt.isAfter(lastSync)) {
          await service.saveEntry(e);
        }
      }

      final remote = await service.fetchEntriesUpdatedSince(lastSync);
      var changed = false;
      for (final e in remote) {
        if (await applyIncomingEntry(e)) changed = true;
      }
      if (changed) notifyListeners();

      _setLastSyncAt();
    } catch (_) {
      // Offline or timeout — local data remains available.
    }
  }

  /// Re-runs the same incremental push-then-pull [attachFirestore] does on
  /// every non-initial sync, without touching the live listener
  /// subscriptions. Call when the Home screen opens: the live listener
  /// alone isn't reliable enough on its own — its underlying stream can go
  /// stale while this device was backgrounded — so this gives every screen
  /// visit a fresh, lightweight check instead of depending on it. Mirrors
  /// EmergencyRepository.refreshContacts/ThemeProvider.refreshVesselSettings.
  /// No-ops if Firestore isn't attached (offline/local mode).
  Future<void> refreshEntries() async {
    final service = _firestore;
    if (service == null) return;
    await _refreshEntriesIncremental(service);
  }

  /// Applies one incoming entry (from any fetch/pull path — initial sync,
  /// incremental sync, forceSync, reattach, or the live listener) to local
  /// state. This is the single place that interprets the tombstone fields:
  ///   - `deletedAt` set → remove the entry locally (it was deleted, possibly
  ///     on another device, or its own delete is only now confirmed).
  ///   - `trackDeletedAt` set and a local track exists for that date → remove
  ///     the local track too, and best-effort re-issue the Storage delete
  ///     (covers the device that deleted it never confirming that half).
  ///   - Otherwise → normal upsert.
  /// Skips entirely if an edit to this date is actively debounced (about to
  /// push) or — when [respectLocalEdit] is true — if our own unpushed local
  /// edit is newer than this specific incoming version (never compared
  /// against the global lastSync, so a pending edit to one date can't cause
  /// every other date's genuinely newer remote update to be ignored too).
  /// [respectLocalEdit] is false for forceSync, which is documented and
  /// intended to mean "remote wins unconditionally" for a deliberate,
  /// user-triggered reconciliation — only the debounce-timer skip still
  /// applies there, to avoid clobbering an edit mid-keystroke.
  ///
  /// Used by all four places that apply fetched/pushed entries to local
  /// state (attachFirestore's pull step, forceSync, reattachAndSync, and the
  /// live listener via [_applyRemoteEntries]) so their tombstone-interpretation
  /// logic can't drift apart from each other.
  @visibleForTesting
  Future<bool> applyIncomingEntry(DayEntry e, {bool respectLocalEdit = true}) async {
    if (_syncTimers.containsKey(e.date)) return false;
    if (respectLocalEdit) {
      final localEdit = _localEditTime(e.date);
      if (localEdit != null &&
          e.updatedAt != null &&
          localEdit.isAfter(e.updatedAt!)) {
        return false;
      }
    }

    var changed = false;
    if (e.deletedAt != null) {
      if (_entries.remove(e.date) != null) {
        await _dayBox.delete(e.date.toIso8601String());
        changed = true;
      }
    } else {
      _entries[e.date] = e;
      await _dayBox.put(e.date.toIso8601String(), e);
      changed = true;
    }

    if (e.trackDeletedAt != null && dailyTracks.containsKey(e.date)) {
      dailyTracks.remove(e.date);
      await _trackBox.delete(e.date.toIso8601String());
      _storage?.deleteTrack(e.date).catchError((_) {});
      changed = true;
    }

    return changed;
  }

  /// Applies a batch of entry changes received from Firestore's live
  /// listener. `removed` (real Firestore deletes) is effectively unused
  /// today — deleteEntry now writes a tombstone instead of physically
  /// deleting — but is still handled defensively in case a document is ever
  /// removed by some other means (e.g. manual console edit).
  Future<void> _applyRemoteEntries(
      ({List<DayEntry> upserted, List<DateTime> removed}) changes) async {
    var changed = false;
    for (final e in changes.upserted) {
      if (await applyIncomingEntry(e)) changed = true;
    }
    for (final date in changes.removed) {
      if (_syncTimers.containsKey(date)) continue;
      if (_entries.remove(date) != null) {
        await _dayBox.delete(date.toIso8601String());
        changed = true;
      }
    }
    if (changed) {
      _setLastSyncAt();
      notifyListeners();
    }
  }

  // ── Storage attachment ─────────────────────────────────────────────────────

  /// Attaches Firebase Storage and syncs GPX tracks: on [initialSync] uploads
  /// every local track, then always downloads any track present in the cloud
  /// but missing locally (e.g. imported on another device).
  Future<void> attachStorage(StorageService service,
      {bool initialSync = false}) async {
    _storage = service;
    try {
      if (initialSync) {
        for (final entry in dailyTracks.entries) {
          try {
            final bytes = _trackToGpxBytes(entry.value);
            await service.uploadTrack(entry.key, bytes);
          } catch (e, st) {
            // One bad track shouldn't stop the rest from uploading.
            // ignore: avoid_print
            debugPrint('[attachStorage] upload ${entry.key} failed: $e\n$st');
          }
        }
      }
      final cloudDates = await _listTrackDatesWithRetry(service);
      final missing = cloudDates
          .where((d) =>
              !dailyTracks.containsKey(d) && _entries[d]?.trackDeletedAt == null)
          .toList();
      for (final date in missing) {
        try {
          final bytes = await service.downloadTrack(date);
          if (bytes == null || bytes.isEmpty) continue;
          final points = (await compute(parseGpxBytes, bytes)).points;
          if (points.isEmpty) continue;
          await _saveTrack(date, '$date.gpx', points);
        } catch (e, st) {
          // One bad track shouldn't stop the rest from downloading.
          // ignore: avoid_print
          debugPrint('[attachStorage] download $date failed: $e\n$st');
        }
      }
    } catch (e, st) {
      // ignore: avoid_print
      debugPrint('[attachStorage] failed: $e\n$st');
    }
  }

  /// Serializes [track]'s points back into GPX file bytes for upload.
  static Uint8List _trackToGpxBytes(DailyTrack track) {
    final gpx = Gpx();
    gpx.trks = [
      Trk(trksegs: [
        Trkseg(
          trkpts: track.points
              .map((p) => Wpt(lat: p.lat, lon: p.lon, time: p.time.toUtc()))
              .toList(),
        ),
      ]),
    ];
    return Uint8List.fromList(utf8.encode(GpxWriter().asString(gpx)));
  }

  // ── Day entry management ───────────────────────────────────────────────────

  /// Creates a new (empty) day entry for [date], carrying forward the crew
  /// and vessel status (oil/fuel/keel) from the most recent prior day.
  /// No-ops if an entry for that date already exists.
  void addEntry(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    if (_entries.containsKey(normalized)) return;

    // Vessel status from the closest past day (never from future entries).
    int? oil, fuel;
    bool? keel;
    for (final e in entries.reversed) {
      if (!e.date.isBefore(normalized)) continue;
      oil  ??= e.oilLevel;
      fuel ??= e.fuelLevel;
      keel ??= e.keelDown;
      if (oil != null && fuel != null && keel != null) break;
    }

    final now = DateTime.now();
    final entry = DayEntry(
      date: normalized,
      timeline: [],
      crew: lastCrew,
      oilLevel:  oil,
      fuelLevel: fuel,
      keelDown:  keel,
      createdAt: now,
      updatedAt: now,
    );
    _entries[normalized] = entry;
    _dayBox.put(normalized.toIso8601String(), entry);
    _recordLocalEdit(normalized);
    _syncToFirestore(entry);
    notifyListeners();
  }

  /// Returns the entry for [date], or null if none exists yet.
  DayEntry? getEntry(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return _entries[normalized];
  }

  /// Moves an entry (and its GPX track, if any) from [oldDate] to [newDate].
  /// Returns false without changing anything if [newDate] is already taken.
  Future<bool> changeEntryDate(DateTime oldDate, DateTime newDate) async {
    final oldNorm = DateTime(oldDate.year, oldDate.month, oldDate.day);
    final newNorm = DateTime(newDate.year, newDate.month, newDate.day);
    if (oldNorm == newNorm) return true;
    if (_entries.containsKey(newNorm)) return false;

    final entry = _entries[oldNorm];
    if (entry == null) return false;

    entry.date = newNorm;
    _entries.remove(oldNorm);
    _entries[newNorm] = entry;
    await _dayBox.delete(oldNorm.toIso8601String());
    await _dayBox.put(newNorm.toIso8601String(), entry);

    // Transfer local-edit tracking to the new key.
    _clearLocalEdit(oldNorm);
    _recordLocalEdit(newNorm);

    final track = dailyTracks[oldNorm];
    if (track != null) {
      track.day = newNorm;
      dailyTracks.remove(oldNorm);
      dailyTracks[newNorm] = track;
      await _trackBox.delete(oldNorm.toIso8601String());
      await _trackBox.put(newNorm.toIso8601String(), track);

      if (_storage != null) {
        final bytes = _trackToGpxBytes(track);
        _storage!.uploadTrack(newNorm, bytes).catchError((_) {});
      }
    }

    _syncToFirestore(entry);
    notifyListeners();

    // The old date's entry/track deletion shares the same durability gap
    // (and fix) as removeEntry: recorded as pending and retried on every
    // future attachFirestore/forceSync/reattachAndSync until confirmed.
    _recordPendingDelete(oldNorm);
    await _pushPendingDelete(oldNorm);

    return true;
  }

  /// Deletes the entry for [date] (and its GPX track, if any) locally
  /// immediately, then durably pushes the deletion to Firestore/Storage —
  /// if that push fails or the app is offline, the date is marked pending
  /// and retried on every future attachFirestore/forceSync/reattachAndSync
  /// (see _pushPendingDelete), so the deleted data cannot resurrect on a
  /// later sync the way a bare fire-and-forget delete could.
  Future<void> removeEntry(DateTime date) async {
    final normalized = DateTime(date.year, date.month, date.day);

    _syncTimers[normalized]?.cancel();
    _syncTimers.remove(normalized);
    _clearLocalEdit(normalized);

    _entries.remove(normalized);
    await _dayBox.delete(normalized.toIso8601String());

    if (dailyTracks.containsKey(normalized)) {
      dailyTracks.remove(normalized);
      await _trackBox.delete(normalized.toIso8601String());
    }

    _recordPendingDelete(normalized);
    notifyListeners();
    await _pushPendingDelete(normalized);
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  /// Saves [entry] locally and schedules a debounced Firestore push.
  ///
  /// [changedFields] must name exactly the DayEntry/Firestore field keys this
  /// call actually mutated (e.g. `{'notes'}`, `{'oilLevel', 'fuelLevel'}`).
  /// Only those fields are pushed to Firestore (merged, not replaced), so
  /// editing one field on one device can never clobber a different field
  /// another device wrote concurrently to the same day.
  void saveEntry(DayEntry entry, {required Set<String> changedFields}) {
    final now = DateTime.now();
    entry.createdAt ??= now; // backfill for entries created before timestamping
    entry.updatedAt = now;
    entry.save();
    _recordLocalEdit(entry.date);
    notifyListeners();
    _debouncedSync(entry, changedFields);
  }

  /// Replaces all local entries/roster with [entries]/[roster] (from a
  /// parsed backup archive) and pushes the restored state to Firestore.
  ///
  /// Callers must have already validated the backup and called
  /// [clearLocalData] — this only repopulates, it doesn't wipe first. GPS
  /// tracks are restored separately via [replaceTrackPoints], since each
  /// entry may or may not have one.
  Future<void> restoreFromBackup({
    required List<DayEntry> entries,
    required List<CrewMember> roster,
  }) async {
    for (final e in entries) {
      final normalized = DateTime(e.date.year, e.date.month, e.date.day);
      _entries[normalized] = e;
      await _dayBox.put(normalized.toIso8601String(), e);
    }
    for (final m in roster) {
      m.id ??= _newId();
      await _rosterBox.put(m.id!, m);
    }
    notifyListeners();

    final fs = _firestore;
    if (fs != null) {
      for (final e in _entries.values) {
        await fs.saveEntry(e);
        _recordLocalEdit(e.date);
      }
    }
    _syncRosterToFirestore();
  }

  /// Deletes (tombstones) any cloud entry/track whose date isn't part of
  /// the current local state — call this once a restore has fully
  /// repopulated both entries ([restoreFromBackup]) *and* tracks
  /// ([replaceTrackPoints] for each restored entry), so this sees the
  /// complete restored picture.
  ///
  /// Without this, a restore only ever pushes what's *in* the backup; any
  /// entry or track that existed in the cloud but isn't part of the backup
  /// is never told to go away, and reappears the moment something re-syncs
  /// it (the live listener resubscribing, or a future incremental pull —
  /// restoreFromBackup's clearLocalData wipes the sync-state box, so the
  /// very next attachFirestore's "updated since last sync" query effectively
  /// becomes "fetch everything"). Restore is documented as a full replace,
  /// not a merge (see BackupService's generated README), so this is the
  /// correct, intended behavior — not an aggressive extra deletion.
  ///
  /// Best-effort: if offline, silently does nothing (nothing pending is
  /// recorded for cloud-only dates never learned about) — a manual
  /// forceSync once back online is the way to retry this reconciliation.
  /// Pure decision logic for [reconcileCloudAfterRestore]'s entry half:
  /// which dates exist on the server (and aren't already tombstoned) but
  /// are absent from [restoredDates] — these are the dates that must be
  /// tombstoned so they don't reappear. Separated out from the actual
  /// Firestore/Storage calls so it's directly unit-testable.
  @visibleForTesting
  static Set<DateTime> datesToTombstone(
    Iterable<DayEntry> serverEntries,
    Set<DateTime> restoredDates,
  ) =>
      {
        for (final e in serverEntries)
          if (e.deletedAt == null && !restoredDates.contains(e.date)) e.date,
      };

  Future<void> reconcileCloudAfterRestore() async {
    final fs = _firestore;
    if (fs != null) {
      try {
        final serverEntries = await fs.fetchAllEntries();
        for (final date in datesToTombstone(serverEntries, _entries.keys.toSet())) {
          _recordPendingDelete(date);
          await _pushPendingDelete(date);
        }
      } catch (_) {}
    }

    final st = _storage;
    if (st != null) {
      try {
        final serverTrackDates = await _listTrackDatesWithRetry(st);
        for (final date in serverTrackDates) {
          if (dailyTracks.containsKey(date)) continue; // restored, keep it
          final entry = _entries[date];
          if (entry != null && entry.deletedAt == null) {
            // The entry survived the restore but its track didn't —
            // tombstone just the track, same as removeGpx.
            entry.trackDeletedAt = DateTime.now();
            await _dayBox.put(date.toIso8601String(), entry);
            _recordLocalEdit(date);
            _syncToFirestore(entry, {'trackDeletedAt'});
          }
          await st.deleteTrack(date).catchError((_) {});
        }
      } catch (_) {}
    }
  }

  // ── Timeline management ────────────────────────────────────────────────────

  /// Adds [entry] to [day]'s timeline (auto-inserting a crew/vessel-status
  /// snapshot line first, if this is the day's first real timeline entry),
  /// keeps the timeline sorted by time, and re-derives the day's keel
  /// position from the updated timeline.
  void addTimelineEntry(DateTime day, TimelineEntry entry) {
    final normalized = DateTime(day.year, day.month, day.day);
    final d = _entries[normalized];
    if (d == null) return;

    final t = entry.time;

    // On the first real timeline entry, auto-snapshot crew and vessel status.
    // addEntry() already carries both forward from the previous day, so we
    // just read the current day's values — no need to look back ourselves.
    final hasCrewLog = d.timeline
        .any((e) => e.vesselStatusNote?.startsWith('crew:') == true);
    if (!hasCrewLog && d.crew.isNotEmpty) {
      d.timeline.add(TimelineEntry(
          time: t, vesselStatusNote: buildCrewNote(d.crew)));
    }

    final hasStatusLog = d.timeline.any((e) =>
        e.vesselStatusNote != null &&
        e.vesselStatusNote?.startsWith('crew:') != true);
    if (!hasStatusLog) {
      final parts = <String>[];
      if (d.oilLevel != null) parts.add('oil=${d.oilLevel}');
      if (d.fuelLevel != null) parts.add('fuel=${d.fuelLevel}');
      if (parts.isNotEmpty) {
        d.timeline.add(TimelineEntry(
            time: t, vesselStatusNote: 'vs:${parts.join(',')}'));
      }
      if (d.keelDown != null) {
        d.timeline.add(TimelineEntry(
            time: t,
            vesselStatusNote: d.keelDown! ? 'vs:keel=down' : 'vs:keel=up'));
      }
    }

    d.timeline.add(entry);
    d.timeline.sort((a, b) => a.time.compareTo(b.time));
    _dayBox.put(normalized.toIso8601String(), d);
    _recordLocalEdit(normalized);
    _syncToFirestore(d, {'timeline'});
    notifyListeners();
  }

  // ── GPX import ─────────────────────────────────────────────────────────────

  /// Parses a GPX [file] from disk and saves its track for [day].
  Future<void> importGpx(DateTime day, File file) async {
    final normalized = DateTime(day.year, day.month, day.day);
    final bytes = await file.readAsBytes();
    final points = (await compute(parseGpxBytes, bytes)).points;
    if (points.isEmpty) return;
    await _saveTrack(normalized, file.uri.pathSegments.last, points);
    _storage?.uploadTrack(normalized, bytes).catchError((_) {});
  }

  /// Parses raw GPX [bytes] (e.g. from a share-sheet import) and saves the
  /// track for [day].
  Future<void> importGpxFromBytes(
      DateTime day, Uint8List bytes, String fileName) async {
    final normalized = DateTime(day.year, day.month, day.day);
    final points = (await compute(parseGpxBytes, bytes)).points;
    if (points.isEmpty) return;
    await _saveTrack(normalized, fileName, points);
    _storage?.uploadTrack(normalized, bytes).catchError((_) {});
  }

  /// Replaces a day's track with [points] (e.g. after a merge), re-uploads.
  Future<void> replaceTrackPoints(DateTime day, List<TrackPoint> points) async {
    final normalized = DateTime(day.year, day.month, day.day);
    final fileName = '${normalized.toIso8601String().substring(0, 10)}.gpx';
    await _saveTrack(normalized, fileName, points);
    final track = dailyTracks[normalized];
    if (track != null) {
      _storage?.uploadTrack(normalized, _trackToGpxBytes(track)).catchError((_) {});
    }
  }

  /// Writes [points] as [day]'s track to Hive and the in-memory cache.
  Future<void> _saveTrack(
      DateTime normalized, String fileName, List<TrackPoint> points) async {
    final track = DailyTrack(day: normalized, fileName: fileName, points: points);
    dailyTracks[normalized] = track;
    await _trackBox.put(normalized.toIso8601String(), track);
    notifyListeners();
  }

  /// Deletes [day]'s GPX track locally and in Storage, durably. If a log
  /// entry exists for [day], the deletion is also recorded on it
  /// (trackDeletedAt) and pushed through the normal saveEntry pipeline, so
  /// it durably retries via the exact same mechanism any other edit already
  /// does (see removeEntry's doc comment for why that matters). If no entry
  /// exists for [day] (a track can be imported standalone), falls back to
  /// the same pending-delete tracking removeEntry uses, since there's no
  /// entry document to durably carry the tombstone on.
  Future<void> removeGpx(DateTime day) async {
    final normalized = DateTime(day.year, day.month, day.day);

    dailyTracks.remove(normalized);
    await _trackBox.delete(normalized.toIso8601String());
    _storage?.deleteTrack(normalized).catchError((_) {});

    final entry = _entries[normalized];
    if (entry != null) {
      entry.trackDeletedAt = DateTime.now();
      await _dayBox.put(normalized.toIso8601String(), entry);
      _recordLocalEdit(normalized);
      _syncToFirestore(entry, {'trackDeletedAt'});
      notifyListeners();
    } else {
      notifyListeners();
      _recordPendingDelete(normalized);
      await _pushPendingDelete(normalized);
    }
  }

  // ── Cross-correlation ──────────────────────────────────────────────────────

  /// Finds the GPS point on [day]'s track closest in time to [time] — used
  /// to correlate a timeline entry with its GPS position.
  TrackPoint? findClosestPoint(DateTime day, DateTime time) {
    final normalized = DateTime(day.year, day.month, day.day);
    final track = dailyTracks[normalized];
    if (track == null || track.points.isEmpty) return null;

    TrackPoint? best;
    Duration bestDiff = const Duration(days: 9999);
    for (final p in track.points) {
      final diff = p.time.toLocal().difference(time).abs();
      if (diff < bestDiff) { bestDiff = diff; best = p; }
    }
    return best;
  }

  // ── Full sync / re-attach ──────────────────────────────────────────────────

  /// Pushes every local entry to Firestore, then pulls every remote entry
  /// (remote wins for the same date).  Also syncs GPX tracks.
  Future<void> forceSync() async {
    final fs = _firestore;
    if (fs == null) throw Exception('Cloud sync unavailable.');

    // Retry any deletes that never got confirmed pushed, before pulling —
    // otherwise the pull below could re-fetch the still-undeleted server
    // doc and resurrect it locally.
    for (final date in _pendingDeleteDates().toList()) {
      await _pushPendingDelete(date);
    }

    // Push all local entries.
    for (final e in _entries.values) {
      await fs.saveEntry(e);
      _recordLocalEdit(e.date);
    }

    // Pull all remote entries (remote wins for conflicts on force-sync).
    final all = await fs.fetchAllEntries();
    var changed = false;
    for (final e in all) {
      if (await applyIncomingEntry(e, respectLocalEdit: false)) changed = true;
    }
    if (changed) notifyListeners();

    _setLastSyncAt();

    // GPX tracks.
    final st = _storage;
    if (st != null) {
      final cloudDates = await _listTrackDatesWithRetry(st);
      final missing = cloudDates
          .where((d) =>
              !dailyTracks.containsKey(d) && _entries[d]?.trackDeletedAt == null)
          .toList();
      for (final date in missing) {
        try {
          final bytes = await st.downloadTrack(date);
          if (bytes == null || bytes.isEmpty) continue;
          final points = (await compute(parseGpxBytes, bytes)).points;
          if (points.isEmpty) continue;
          await _saveTrack(date, '$date.gpx', points);
        } catch (e, stack) {
          // One bad track shouldn't stop the rest from downloading.
          // ignore: avoid_print
          debugPrint('[forceSync] track download $date failed: $e\n$stack');
        }
      }
    }
  }

  /// Wipes all local Hive data and in-memory caches without re-attaching.
  ///
  /// Call this before [attachFirestore] when a different user signs in, so that
  /// the previous user's entries are not uploaded to the new user's boat.
  Future<void> clearLocalData() async {
    await _entrySub?.cancel();
    _entrySub = null;
    await _rosterSub?.cancel();
    _rosterSub = null;
    for (final t in _syncTimers.values) { t.cancel(); }
    _syncTimers.clear();
    await _dayBox.clear();
    await _trackBox.clear();
    await _syncStateBox.clear();
    await _rosterBox.clear();
    _entries.clear();
    dailyTracks.clear();
    notifyListeners();
  }

  /// Switches to a different logbook: downloads the new logbook's data first,
  /// then replaces local state only on success. Returns `false` (leaving
  /// local state, _firestore, and _storage all untouched) if the download
  /// fails — callers MUST check this and abort the rest of the switch (not
  /// point the rest of the app at the new logbook) rather than assuming
  /// success, since a false return means this repository never actually
  /// switched away from whichever logbook it was already on.
  Future<bool> reattachAndSync(
      FirestoreService firestoreService, StorageService storageService) async {
    await _entrySub?.cancel();
    _entrySub = null;
    await _rosterSub?.cancel();
    _rosterSub = null;
    for (final t in _syncTimers.values) { t.cancel(); }
    _syncTimers.clear();

    // ── Step 1: download new logbook data before touching local state ──────────
    // The entry list must be fetched here, before anything local is cleared,
    // so a failure leaves existing local data intact instead of wiping it
    // with nothing confirmed to replace it. Retried with backoff: this is a
    // forced server read (Source.server), so right after joining/creating a
    // logbook, the security rule check for the membership doc just written
    // can transiently lag behind it.
    List<DayEntry> newEntries;
    try {
      newEntries = await retryWithBackoff(firestoreService.fetchAllEntries);
    } catch (_) {
      // Download failed — leave existing local data intact and abort. The
      // caller MUST check this false return and abort its own side of the
      // switch too (see the doc comment above) — this repository is still
      // pointed at whichever logbook it was already on.
      return false;
    }

    // The track-date list is fetched separately and treated as best-effort:
    // Storage's security rules check Firestore membership via a cross-service
    // firestore.exists(...) call, which can lag a moment behind the Firestore
    // write that just created that membership (e.g. right after creating or
    // joining a logbook) — a same-client Firestore read (fetchAllEntries
    // above) doesn't have this gap, but a Storage rule reading *into*
    // Firestore isn't guaranteed to see it instantly. Unlike Firestore reads,
    // Storage's listAll() has no offline cache and no built-in retry, so a
    // single transient hiccup here (not just the membership-propagation
    // case) would otherwise silently cost every track for this switch — a
    // few quick retries cover both without blocking the whole switch on
    // what's really a track-only issue; any tracks still missed are picked
    // up by the next attachStorage (next app launch) or forceSync, same as
    // any other missed track.
    final cloudTrackDates = await _listTrackDatesWithRetry(storageService);

    // Give any delete pending from the logbook being left one last chance to
    // push before its bookkeeping is wiped below.
    for (final date in _pendingDeleteDates().toList()) {
      await _pushPendingDelete(date);
    }

    // ── Step 2: download complete, now safe to replace local state ─────────────
    await _dayBox.clear();
    await _trackBox.clear();
    await _syncStateBox.clear();
    await _rosterBox.clear();
    _entries.clear();
    dailyTracks.clear();

    _firestore = firestoreService;
    _storage = storageService;

    for (final e in newEntries) {
      await applyIncomingEntry(e, respectLocalEdit: false);
    }
    _setLastSyncAt();

    for (final date in cloudTrackDates) {
      if (_entries[date]?.trackDeletedAt != null) continue;
      try {
        final bytes = await storageService.downloadTrack(date);
        if (bytes == null || bytes.isEmpty) continue;
        final points = (await compute(parseGpxBytes, bytes)).points;
        if (points.isEmpty) continue;
        await _saveTrack(date, '$date.gpx', points);
      } catch (_) {
        // One bad track (network hiccup, corrupt file) shouldn't cost every
        // other date's track — keep going instead of aborting the whole loop.
      }
    }

    notifyListeners();

    _entrySub = firestoreService
        .entryChanges()
        .asyncMap(_applyRemoteEntries)
        .listen((_) {}, onError: (_) {});

    try {
      final remoteRoster = await firestoreService.fetchRoster();
      if (remoteRoster.isNotEmpty) await _applyRemoteRoster(remoteRoster);
    } catch (_) {}

    _rosterSub = firestoreService
        .rosterChanges()
        .asyncMap(_applyRemoteRoster)
        .listen((_) {}, onError: (_) {});

    return true;
  }

  /// Lists [storageService]'s track dates, retrying with backoff on failure
  /// before giving up (returning `[]`) — Storage's listAll() has no offline
  /// cache and no built-in retry, unlike Firestore reads, so a single
  /// transient hiccup (or a membership-propagation lag, e.g. right after
  /// joining/creating a logbook) would otherwise cost every track for
  /// whichever caller has already decided this is best-effort. Used by
  /// [attachStorage], [forceSync], [reconcileCloudAfterRestore], and
  /// [reattachAndSync]. The delay this needs has proven variable in
  /// practice — a short retry window isn't always enough — so this backs
  /// off further before giving up, up to ~15 seconds total across all
  /// attempts.
  static Future<List<DateTime>> _listTrackDatesWithRetry(
      StorageService storageService) async {
    const delays = [
      Duration(milliseconds: 500),
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 7),
    ];
    for (final delay in delays) {
      try {
        return await storageService.listTrackDates();
      } catch (_) {
        await Future.delayed(delay);
      }
    }
    try {
      return await storageService.listTrackDates();
    } catch (_) {
      return [];
    }
  }

  // ── Crew roster CRUD ───────────────────────────────────────────────────────

  /// Adds or updates [m] in the roster (assigning a new id if it doesn't
  /// have one yet) and pushes the roster to Firestore.
  void saveRosterMember(CrewMember m) {
    m.id ??= _newId();
    _rosterBox.put(m.id!, m);
    unawaited(_syncRosterToFirestore());
    notifyListeners();
  }

  /// Saves an edit made to a crew member from outside the roster screen
  /// (e.g. editing a person on a specific day's crew list). If [m] has no id
  /// yet — crew added/edited before the roster link existed — this reuses an
  /// existing roster entry with the same name instead of creating a
  /// duplicate.
  void saveEditedRosterMember(CrewMember m) {
    if (m.id == null) {
      for (final r in _rosterBox.values) {
        if (r.name.trim().toLowerCase() == m.name.trim().toLowerCase()) {
          m.id = r.id;
          break;
        }
      }
    }
    saveRosterMember(m);
  }

  /// Removes the roster member with [id] and pushes the roster to Firestore.
  void deleteRosterMember(String id) {
    _rosterBox.delete(id);
    unawaited(_syncRosterToFirestore());
    notifyListeners();
  }

  /// Replaces the entire local roster with [members] (from a Firestore pull).
  Future<void> _applyRemoteRoster(List<CrewMember> members) async {
    await _rosterBox.clear();
    for (final m in members) {
      if (m.id != null) await _rosterBox.put(m.id!, m);
    }
    notifyListeners();
  }

  /// Pushes the full current roster to Firestore, retrying with backoff on
  /// failure before giving up. Roster sync replaces the server's whole list
  /// on every push (there's no per-member tombstone, unlike entries/tracks —
  /// see [_pushPendingDelete]), so a push that silently failed would leave
  /// the server holding a stale roster that could resurrect a just-deleted
  /// member (or drop a just-saved edit) the next time [_applyRemoteRoster]
  /// runs from the live [rosterChanges] listener.
  Future<void> _syncRosterToFirestore() async {
    final fs = _firestore;
    if (fs == null) return;
    const delays = [
      Duration(milliseconds: 500),
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 7),
    ];
    final members = _rosterBox.values.toList();
    for (final delay in delays) {
      try {
        await fs.saveRoster(members);
        return;
      } catch (_) {
        await Future.delayed(delay);
      }
    }
    try {
      await fs.saveRoster(members);
    } catch (_) {}
  }

  /// Generates a random 32-hex-char id for a new roster member.
  static String _newId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Builds the sentinel string auto-logged as a timeline entry's
  /// `vesselStatusNote` the first time a day gets a real timeline entry,
  /// recording who was aboard (first name flagged as skipper via `role=0:`).
  static String buildCrewNote(List<CrewMember> crew) {
    final parts = crew.asMap().entries.map((e) =>
        e.key == 0 ? 'role=0:${e.value.name}' : e.value.name).toList();
    // Stored prefix is a non-localised sentinel; display label is separate (see _crewNoteDisplay).
    return 'crew:${parts.join(' · ')}';
  }

  // ── Private Firestore helpers ──────────────────────────────────────────────

  // Coalesces rapid successive edits to the same day (e.g. typing in a text
  // field) into a single Firestore write instead of one per keystroke. Field
  // names accumulate across coalesced calls so nothing gets dropped from the
  // eventual push.
  void _debouncedSync(DayEntry entry, Set<String> changedFields) {
    _pendingSyncFields.putIfAbsent(entry.date, () => {}).addAll(changedFields);
    _syncTimers[entry.date]?.cancel();
    _syncTimers[entry.date] = Timer(const Duration(seconds: 2), () {
      final fields = _pendingSyncFields.remove(entry.date) ?? changedFields;
      _syncToFirestore(entry, fields);
      _syncTimers.remove(entry.date);
    });
  }

  // [changedFields] null means "replace the whole document" — only correct
  // for genuinely new documents or deliberate full resyncs (see saveEntry's
  // doc comment for why a live edit must always pass an explicit field set).
  void _syncToFirestore(DayEntry entry, [Set<String>? changedFields]) {
    _firestore?.saveEntry(entry, changedFields: changedFields).catchError((_) {});
  }

  @override
  void dispose() {
    _entrySub?.cancel();
    _rosterSub?.cancel();
    for (final t in _syncTimers.values) { t.cancel(); }
    super.dispose();
  }
}
