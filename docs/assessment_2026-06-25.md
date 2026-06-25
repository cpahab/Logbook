
# Logbook App — Assessment Report

**Date:** 2026-06-25
**Branch:** `claude/version-tag-status-94c3n6`
**Version:** 1.0.21+21
**Re-assessed:** 2026-06-25 (second pass)

---

## 1. Executive Summary

The app is well-structured and architecturally sound. The core data model (logbooks, daily entries, GPX tracks, crew, timeline) is clean and the offline-first sync strategy using Hive + Firestore is robust. The theming system uses Material 3 correctly with a maritime colour palette (Deep Navy / Captain's Gold / Seafoam).

`dart analyze` returns **zero issues**. Storage rules now enforce membership. Account deletion has a proper offline guard. Emergency screen content is largely localised. Multiple navigation and UX issues from the original assessment have been fixed.

The most significant outstanding issues are: hardcoded German strings written into Firestore (timeline vessel-status notes use `'Motoröl:'`, `'Kraftstoff:'`, `'Kiel: Unten/Oben'`), a dead button in EmergencyScreen, N+1 Firestore reads in `listLogbooks`, and keel state displayed in German on-screen without going through `l10n`.

Issues are rated **Critical** (data loss / security / wrong behaviour), **Major** (visible inconsistency that affects user confidence or correct operation), or **Minor** (polish / housekeeping).

---

## 2. Previous Findings — Status

### 2.1 `participantsList` vs `crew` — dual crew model [Minor] — PARTIAL

`DayEntry.participantsList` (Hive field index 13) is retired and the index is annotated `// @HiveField(13) participantsList — retired, do not reuse index`. Writing is stopped. Old Firestore documents that contain `participantsList` still carry the stale key, but `_toMap` in `firestore_service.dart` does not emit it. No user-visible impact; no migration needed.

**Status:** PARTIAL — writing stopped; old documents carry stale field. No user-visible impact.

---

### 2.2 Stored stats in `DayEntry` never updated [Minor] — OPEN

`DayEntry` still carries `distanceNm`, `avgSpeedKnots`, `maxSpeedKnots`, `totalDurationSeconds`, and `movingDurationSeconds` (Hive fields 6–10). The repository does not write these back after GPX computation. All remain 0 in Firestore. The UI uses live-computed stats from `computeDailyStats`, so there is no visual impact today, but these fields are dead weight in the schema.

**Recommendation:** Either remove from `_toMap` or populate during `saveEntry` when a track is present.

---

### 2.3 [FIXED] `deleteLogbook` leaves Firebase Storage files

`LogbookService.deleteLogbook` now calls `StorageService.deleteLogbookFolder(logbookId)` in a best-effort `try/catch` after Firestore cleanup. Storage rules enforce membership, so orphaned files are inaccessible even if deletion fails transiently.

---

### 2.4 [FIXED] `ThemeProvider.logbookCode` is dead code

`logbookCode` and `reconcileLogbookId` are no longer present in `ThemeProvider`. Confirmed by grep across codebase.

---

### 2.5 Stats bento "Days at Sea" counts GPX-track days only [Minor] — OPEN

`HomeScreen._buildStatsBento` (line 269) iterates `repo.dailyTracks.keys`, which only contains days with an imported or recorded GPX track. Days where the user wrote logbook entries but did not record a GPX track are excluded from the count. The stat label is `l10n.statSailingDays` which translates as just "Days" — ambiguous. A user who logs every day at sea as a text entry will see 0 or a systematically lower count.

**Recommendation:** Expand the count to also include `_dayBox.values` where the entry has navigation data (`fromHarbor`, `toHarbor`, or non-empty `timeline`). Alternatively, rename the stat to "Tracked days" and add a tooltip.

---

### 2.6 [FIXED] Settings logbook list not real-time

`SettingsScreen` now wraps the list in a `RefreshIndicator` whose `onRefresh` calls `_refreshLogbooks`. Pull-to-refresh is available and any error is shown via a snackbar (previously a silent catch, now FIXED — see 8.6).

---

## 3. Theming & Styling Issues

### 3.1 [FIXED] Global AppBar theme is never applied

`light_theme.dart` now defines `appBarTheme` with surface background and primary foreground, matching actual screen rendering.

---

### 3.2 [FIXED] `theme_extensions.dart` is an empty stub

`theme_extensions.dart` now contains two fully implemented `ThemeExtension` subclasses:

- `LogbookTimelineColors` — `crewAccent`, `dividerColor`, `cardShadowColor`
- `LogbookEmergencyColors` — `criticalColor`, `criticalBgColor`, `criticalMutedColor`, `cardShadowColor`

Both are registered in `light_theme.dart` and `dark_theme.dart` and are used throughout the emergency and day-detail screens.

---

### 3.3 Light vs dark `cardTheme` elevation inconsistency [Minor] — OPEN

Light theme: `CardThemeData(elevation: 1)`. Dark theme: `CardThemeData(elevation: 2)`. Cards in dark mode still carry more shadow than light mode.

---

### 3.4 [FIXED] `HomeScreen` AppBar height 72px vs 56px

The vessel name is now displayed as a `Text` widget in the body `Column`, and all screens share the default AppBar height. The visual jump on back-navigation is eliminated.

---

### 3.5 [FIXED] `centerTitle` inconsistent across screens

The global `appBarTheme` now sets `centerTitle: true`, which propagates to all AppBars that do not explicitly override it.

---

## 4. Language / Localisation Inconsistencies

### 4.1 Emergency feature is partially un-localised [Major] — PARTIAL

Emergency screen section headers, card titles, sound signal texts, EPIRB/SART descriptions, and MAYDAY card content go through `context.l10n`. However, several strings intentionally remain hardcoded in `mayday_screen.dart` with inline SOLAS/IMO comments:

- `'STEP 1: DSC DISTRESS ALERT'`, `'STEP 2: SIGNAL'`, `'STEP 5: NATURE OF DISTRESS'`, `'STEP 7: CLOSING'`
- `'THIS IS YACHT '`, `'CALLSIGN '`, `'MMSI '`, `'MAYDAY '`, `'POSITION:'`, `'NATURE OF DISTRESS:'`
- Distress options: `'SINKING / FLOODING'`, `'FIRE'`, `'ABANDONING SHIP'`

One string lacks a SOLAS comment: `'CREW STATUS'` at `mayday_screen.dart` line 911 (`_StepCrew` widget). This should either receive a SOLAS comment or be localised.

**Status:** PARTIAL — radio script protocol text intentionally English per SOLAS; informational content is localised; one string (`'CREW STATUS'`) is unlabelled.

---

### 4.2 [FIXED] Add/Edit dialogs mix German and English

All four dialog types (`_AddContactDialog`, `_EditContactDialog`, `_AddFrequencyDialog`, `_EditFrequencyDialog`) now use `context.l10n` for their field labels. Finding 8.1 from the previous re-assessment is also now FIXED (see below).

**Status:** FIXED — `l10n.emergencyContactRoleHint` and `l10n.emergencyContactPhoneLabel` are used in both add and edit dialogs.

---

### 4.3 [FIXED] `MaydayScreen` AppBar title says "Emergency Manifest"

`MaydayScreen` now uses `context.l10n.maydayScreenTitle` for its AppBar title ("Radio Protocol" / "Funkprotokoll").

---

### 4.4 Hardcoded German strings written into Firestore [Major] — NEW / OPEN

`HomeRepository.addTimelineEntry` (lines 428–438) and `_editVesselStatus` in `day_detail_screen.dart` (lines 2352–2358) write German-language labels directly into `TimelineEntry.vesselStatusNote`, which is stored in Firestore:

```dart
// home_repository.dart lines 429–430
if (d.oilLevel != null) parts.add('Motoröl: ${d.oilLevel}%');
if (d.fuelLevel != null) parts.add('Kraftstoff: ${d.fuelLevel}%');

// home_repository.dart line 438
vesselStatusNote: d.keelDown! ? 'Kiel: Unten' : 'Kiel: Oben'

// day_detail_screen.dart lines 2352, 2358
vesselStatusNote: 'Motoröl: $oilVal% · Kraftstoff: $fuelVal%'
vesselStatusNote: keelVal! ? 'Kiel: Unten' : 'Kiel: Oben'
```

These persisted strings are displayed verbatim in the timeline (`day_detail_screen.dart` line 1211: `t.vesselStatusNote!`). If the user switches the app language to English, historical entries still show German labels. New entries written while in English mode also receive German labels, since the repository layer has no access to the locale.

A similar but lower-priority issue exists at `day_detail_screen.dart` line 2311 (the vessel-status edit dialog preview), where the keel position is shown as `'Unten'`/`'Oben'` on-screen.

The `_buildEntryText` helper (line 3341–3350) used for PDF/tooltip generation also uses German labels: `'Wind: …'`, `'See: …'`, `'Wetter: …'`, `'Gross: …'`, `'Fock: …'`, `'Motor: An/Aus'`, `'Kiel: Unten/Oben'`.

**File:** `lib/features/home/data/home_repository.dart`, lines 429–430 and 438.
**File:** `lib/features/home/presentation/day_detail_screen.dart`, lines 1649, 2311, 2352, 2358, 3341–3350.

**Recommendation (persisted notes):** Adopt language-neutral sentinel tokens (e.g. `oil:75·fuel:60`, `keel:down`) that the display layer translates via a small parser — the same pattern already in use for `crew:…` notes. This avoids language lock-in in Firestore while keeping the data semantically rich.

**Recommendation (on-screen only):** Replace `'UNTEN'`/`'OBEN'` at line 1649 with `l10n.keelDownLabel`/`l10n.keelUpLabel` (add ARB keys if missing), and replace `'Unten'`/`'Oben'` in the edit dialog at line 2311 similarly.

---

### 4.5 `buildCrewNote` stores English `(Skipper)` in Firestore [Minor] — OPEN

`HomeRepository.buildCrewNote` (line 669) writes `'crew:Alice (Skipper) · Bob'` into Firestore:

```dart
e.key == 0 ? '${e.value.name} (Skipper)' : e.value.name
```

The display function `_crewNoteDisplay` strips the `crew:` prefix and uses `l10n.dataCrewNote` for the section label, but the `(Skipper)` role annotation is stored as-is and shown verbatim. A German-locale user sees `(Skipper)` in their timeline because the English word is baked into Firestore.

An ARB key `labelSkipper` already exists (`"Skipper"` in EN, `"Skipper"` in DE — same word). For most European languages this is acceptable. However, the `(Skipper)` tag in the raw stored string is English-only by design choice.

**File:** `lib/features/home/data/home_repository.dart`, line 669.

**Recommendation:** Adopt the same sentinel pattern as the crew note prefix: store `crew:role=0:Alice · Bob`, and render the role in the display function using `l10n.labelSkipper`. Alternatively, since "Skipper" is the same in both supported locales, document this as an explicit exception.

---

### 4.6 `forceSync` throws a hardcoded German exception message [Minor] — OPEN

`HomeRepository.forceSync` (line 518) throws:

```dart
throw Exception('Cloud-Sync nicht verfügbar.');
```

This exception propagates to the UI. If the caller shows it in a snackbar or dialog, German text appears regardless of locale.

**File:** `lib/features/home/data/home_repository.dart`, line 518.

**Recommendation:** Replace with an app-level error type (enum or custom exception class) and let the UI translate it via `l10n`.

---

## 5. UX / Navigation Issues

### 5.1 Non-functional button in `EmergencyScreen` [Major] — OPEN

`EmergencyScreen` still has a dead `account_circle_outlined` `IconButton` with `onPressed: () {}` in its AppBar (lines 37–40 of `emergency_screen.dart`). Pressing it does nothing.

**Recommendation:** Remove the button or implement it (e.g., navigate to the crew/settings page or show a quick-view of emergency contacts).

---

### 5.2 [FIXED] Navigation stack accumulates on bottom nav

All bottom-nav peer-tab destinations now use `context.go` on all four tab screens (`HomeScreen`, `TracksScreen`, `SettingsScreen`, `EmergencyManifestScreen`, `MaydayScreen`). `DayDetailScreen` still uses `context.push` for non-journal tabs (lines 222–224), which is the accepted documented exception.

---

### 5.3 [FIXED] "All years" view has no matching pill

`HomeScreen._buildYearPills` now renders an "All" chip at the start of the pill row and highlights it when `_showAllYears` is `true`.

---

### 5.4 [FIXED] Crew medical data source has no navigation link

`_EmptyCrewHint` now contains an `OutlinedButton.icon` that navigates to the day entry when one exists.

---

### 5.5 [FIXED] GPS permission may not be requested before MAYDAY screen

`MaydayScreen.initState` now calls `GpsConsentService.requestIfNeeded(context)` in a `postFrameCallback`.

---

### 5.6 [FIXED] Vessel name triple-repetition in MAYDAY step 3 is not explained

`_StepIdentification` now renders `Text(l10n.maydayStateThreeTimes, ...)` as an annotation.

---

### 5.7 `_buildCrewRosterSection` bypasses GoRouter [Minor] — OPEN

`SettingsScreen._buildCrewRosterSection` (line 1530) opens `CrewRosterScreen` via `Navigator.push(context, MaterialPageRoute(...))`, bypassing GoRouter. This means the back button on Android relies on the native navigator stack rather than GoRouter's back stack. Deep-link URLs cannot reach `CrewRosterScreen` directly.

Similarly, `day_detail_screen.dart` line 2118 opens `_DayMapFullScreen` via `Navigator.push`. This is a transient overlay so the impact is low, but is inconsistent with the rest of the navigation.

**Files:** `lib/features/settings/presentation/settings_screen.dart`, line 1530. `lib/features/home/presentation/day_detail_screen.dart`, line 2118.

**Recommendation:** Either register these as named GoRouter routes, or document the deliberate exclusion.

---

### 5.8 Oil-level scale label uses hardcoded `'MIN'` while fuel uses `l10n` [Minor] — OPEN

`_vesselStatCell` in `day_detail_screen.dart` (line 1719):

```dart
isFuel ? context.l10n.vesselEmptyLabel.toUpperCase() : 'MIN',
```

The fuel gauge's lower bound uses `l10n.vesselEmptyLabel` ("Empty") while the oil gauge uses the hardcoded string `'MIN'`. The `vesselFullLabel` is used consistently for both right-side labels. The oil side should use a localised key (e.g. add `vesselOilMinLabel` = "MIN" / "MIN" to both ARB files, or simply reuse `vesselEmptyLabel`).

**File:** `lib/features/home/presentation/day_detail_screen.dart`, line 1719.

---

## 6. Data / Security Notes

### 6.1 [FIXED] Storage rules are authentication-only, no membership check

`storage.rules` now implements `isMember(logbookId)` via a `firestore.exists(...)` cross-service check, mirroring the Firestore rules. Only logbook members may read or write files.

---

### 6.2 [FIXED] Account deletion offline guard / silent cleanup errors

1. `SettingsScreen` now checks connectivity before showing the account-deletion dialog.
2. `deleteUserAndAllLogbooks` now accumulates failures and throws `Exception('$failures Firestore document(s) could not be deleted.')` if any logbook fails to delete.
3. The settings screen catches this exception and shows a `showDialog` explaining partial cleanup.

The inner `catch (_) {}` on per-logbook iteration in `deleteUserAndAllLogbooks` (line 287) still swallows individual errors into the `failures` counter without surfacing which logbooks failed. This is acceptable given the counter-throw, but means the user cannot retry a specific logbook.

---

### 6.3 Firestore `listLogbooks` performs N+1 sequential reads [Minor] — OPEN

`LogbookService.listLogbooks` (lines 63–91) fetches one `users/{uid}` document, then for each logbook ID in the array performs two additional sequential reads: `logbooks/{id}` and `logbooks/{id}/members/{uid}`. For a user with 5 logbooks this is 1 + 5×2 = 11 sequential round trips.

This is only called from the Settings screen on pull-to-refresh or screen mount, so the performance impact is low in typical use. However, it will degrade noticeably on slow connections or with many logbooks.

**File:** `lib/core/services/logbook_service.dart`, lines 63–91.

**Recommendation:** Embed the role directly in the `logbooks/{logbookId}` document as `roles/{uid}` map, or embed `role` in the user document's `logbooks` array, to eliminate the extra round trips.

---

### 6.4 `deleteLogbook` meta-doc deletion uses silent `catch (_) {}` per doc [Minor] — OPEN

`LogbookService.deleteLogbook` (lines 217–221) deletes known meta documents in a loop with a silent catch per doc:

```dart
for (final id in ['settings', 'contacts', 'ui', 'crew_roster']) {
  try { await logbookRef.collection('meta').doc(id).delete(); } catch (_) {}
}
```

If any meta document fails to delete (e.g. a Firestore permission error), the failure is silently swallowed and the logbook is still considered deleted. Orphaned meta documents remain on Firestore.

**File:** `lib/core/services/logbook_service.dart`, lines 217–221.

**Recommendation:** Use a batch delete for all meta docs, and include any batch error in the caller's error chain.

---

### 6.5 `firestore_service.dart` silently skips malformed documents [Minor] — OPEN

`_parseDocChanges` and `_parseDocs` (lines 264 and 278) wrap per-document parsing in `catch (_) {}`. A malformed or schema-incompatible Firestore document is silently dropped, with no log statement. During debugging or after a Firestore schema migration, silently missing entries are hard to diagnose.

**File:** `lib/core/services/firestore_service.dart`, lines 264 and 278.

**Recommendation:** Log the error (at minimum `debugPrint`) before continuing.

---

### 6.6 `shareCodes` collection allows any signed-in user to read all codes [Minor] — OPEN

The Firestore rule for `shareCodes/{code}` allows `read: if isSignedIn()`. This means any authenticated user can read any share code document (including those for logbooks they are not a member of) if they know or guess the share code. Since share codes are only accessible by document ID (not listable), the attack surface is a brute-force guess of the 8-character code.

The code alphabet (`ABCDEFGHJKLMNPQRSTUVWXYZ23456789`, 32 chars, 8 chars) gives 32^8 ≈ 1 trillion combinations — effectively brute-force resistant. This is therefore low-risk but worth documenting.

**File:** `firestore.rules`, line 22.

---

## 7. Code Quality

### 7.1 [FIXED] `_EditContactDialog` has hardcoded English field labels (was Finding 8.1)

`_EditContactDialog` (lines 645 and 652) now uses `context.l10n.emergencyContactRoleHint` and `context.l10n.emergencyContactPhoneLabel`, matching the add dialog.

---

### 7.2 Contact name field `'Name'` not localised [Nitpick] — OPEN (was Finding 8.2)

Both `_AddContactDialog` (line 548) and `_EditContactDialog` (line 638) use the bare string `'Name'` as a field label, not going through `l10n`. While "Name" is the same in English and German, it is not going through the l10n system. If a third locale is added, there is no ARB key to update.

**File:** `lib/features/emergency/presentation/emergency_manifest_screen.dart`, lines 548 and 638.

---

### 7.3 [FIXED] `_refreshLogbooks` in `SettingsScreen` swallows errors silently (was Finding 8.6)

`_refreshLogbooks` now shows a snackbar (`l10n.authErrorGeneric`) when the fetch fails. The spinner is dismissed correctly in both success and failure paths.

---

### 7.4 `TracksScreen` fullscreen map uses `Navigator.push` (was Finding 8.4) [Minor] — OPEN

`TracksScreen._buildMapSection` opens `_TracksMapFullScreen` via `Navigator.push(context, MaterialPageRoute(...))`, bypassing GoRouter. The fullscreen view is transient, so the impact is low, but it is inconsistent.

**File:** `lib/features/tracks/presentation/tracks_screen.dart`, line 546.

---

### 7.5 `_departureBearing` / `_distanceM` duplicated between `TracksScreen` and `_TracksMapFullScreen` (was Finding 8.5) [Minor] — OPEN

Both `_TracksScreenState` and `_TracksMapFullScreenState` define private static copies of `_departureBearing`, `_distanceM`, and `_trackBearing` (identical implementations). Any fix must be applied in two places.

**File:** `lib/features/tracks/presentation/tracks_screen.dart`, lines 26–67 and ~1019–1051.

**Recommendation:** Extract to a file-private top-level utility function or a separate `track_math.dart` file.

---

### 7.6 [FIXED] `/emergency/distress` route existence (was Finding 8.7)

`/emergency/distress` IS registered in `lib/app/router.dart` (line 79) as `EmergencyScreen`. The previous concern was unfounded.

---

### 7.7 Duplicate ARB keys `statSailingDays` and `statDays` [Nitpick] — OPEN

Both `app_en.arb` and `app_de.arb` define `"statSailingDays": "Days"` and `"statDays": "Days"` with identical translations. `statSailingDays` is used in `home_screen.dart` and `tracks_screen.dart` for a stat label, while `statDays` is used as a unit suffix in `tracks_screen.dart`. The duplication is harmless but clutters the ARB file.

**File:** `lib/l10n/app_en.arb`, lines 23–24.

---

## 8. Summary Table

| # | Area | Issue | Severity | Status |
| --- | --- | --- | --- | --- |
| 2.1 | Logic | Dual crew model (`participantsList` + `crew`) | Minor | PARTIAL |
| 2.2 | Logic | Stored stats in DayEntry never updated from GPX | Minor | OPEN |
| 2.3 | Logic | deleteLogbook doesn't clean Firebase Storage | Major | **FIXED** |
| 2.4 | Logic | ThemeProvider.logbookCode is dead code | Minor | **FIXED** |
| 2.5 | Logic | "Days at Sea" counts GPX-track days only | Minor | OPEN |
| 2.6 | Logic | Settings logbook list not real-time | Minor | **FIXED** |
| 3.1 | Theme | Global AppBar theme never applied | Major | **FIXED** |
| 3.2 | Theme | theme_extensions.dart is empty stub | Minor | **FIXED** |
| 3.3 | Theme | Light/dark cardTheme elevation differs | Minor | OPEN |
| 3.4 | Theme | HomeScreen toolbar 72px vs 56px | Minor | **FIXED** |
| 3.5 | Theme | centerTitle inconsistent | Minor | **FIXED** |
| 4.1 | L10n | Emergency feature partially un-localised | Major | PARTIAL |
| 4.2 | L10n | Add/Edit dialogs mix German and English | Major | **FIXED** |
| 4.3 | L10n | MaydayScreen AppBar title wrong | Major | **FIXED** |
| 5.1 | UX | Dead button in EmergencyScreen | Major | OPEN |
| 5.2 | UX | Navigation stack accumulates on bottom nav | Major | **FIXED** |
| 5.3 | UX | "All years" has no pill to deselect | Minor | **FIXED** |
| 5.4 | UX | Crew empty-state has no navigation link | Minor | **FIXED** |
| 5.5 | UX | GPS permission timing inconsistency | Minor | **FIXED** |
| 5.6 | UX | MAYDAY triple-name not annotated | Minor | **FIXED** |
| 6.1 | Security | Storage rules have no membership check | Minor | **FIXED** |
| 6.2 | Security | Account delete swallows cleanup errors | Minor | **FIXED** |

**Fixed:** 13 of 22 original issues
**Partial:** 2
**Still open:** 7

---

## 9. Fresh Findings

### F-1 Hardcoded German strings persisted to Firestore in vessel-status notes [Major]

**Files:** `lib/features/home/data/home_repository.dart` lines 429–430, 438; `lib/features/home/presentation/day_detail_screen.dart` lines 2352, 2358.

`HomeRepository.addTimelineEntry` (called when the user adds a first timeline entry) auto-generates snapshot timeline entries using hardcoded German labels:

```dart
// home_repository.dart:429–430
if (d.oilLevel != null) parts.add('Motoröl: ${d.oilLevel}%');
if (d.fuelLevel != null) parts.add('Kraftstoff: ${d.fuelLevel}%');

// home_repository.dart:438
vesselStatusNote: d.keelDown! ? 'Kiel: Unten' : 'Kiel: Oben'
```

`_editVesselStatus` in `day_detail_screen.dart` does the same when the user saves updated vessel status:

```dart
// day_detail_screen.dart:2352
vesselStatusNote: 'Motoröl: $oilVal% · Kraftstoff: $fuelVal%'
// day_detail_screen.dart:2358
vesselStatusNote: keelVal! ? 'Kiel: Unten' : 'Kiel: Oben'
```

These strings are stored verbatim in Firestore and displayed verbatim in the timeline (line 1211). An English-locale user sees German in their logbook. Historical entries cannot be retroactively relabelled if the user changes language.

**Severity:** Major — user-facing text in the primary data view is language-locked at write time.

**Recommendation:** Adopt the sentinel pattern already in use for crew notes. For example:

- Store `vs:oil=75,fuel=60` and `vs:keel=down`.
- Add a `_vesselStatusDisplay(String note, AppLocalizations l10n)` function that parses the sentinel and returns a localised string.
- This is a one-time migration pattern; legacy entries can be detected by the absence of the `vs:` prefix.

---

### F-2 Keel state displayed in hardcoded German on-screen [Major]

**File:** `lib/features/home/presentation/day_detail_screen.dart`, lines 1649 and 2311.

Line 1649 (vessel status card in the main day view):

```dart
entry.keelDown! ? 'UNTEN' : 'OBEN'
```

Line 2311 (vessel status edit dialog preview):

```dart
keelVal == null ? '—' : (keelVal! ? 'Unten' : 'Oben')
```

Both strings are on-screen only (not persisted), but are German regardless of locale. ARB keys for this exist (`entryDialogKeelLabel` = "Keel"), but no `keelDownLabel` / `keelUpLabel` keys are defined.

**Severity:** Major — German text displayed in an English-locale app for a commonly visible field.

**Recommendation:** Add ARB keys `vesselKeelDown` = "Down" / "Unten" and `vesselKeelUp` = "Up" / "Oben". Replace hardcoded strings with `l10n.vesselKeelDown` and `l10n.vesselKeelUp`.

---

### F-3 `buildCrewNote` stores English `(Skipper)` annotation in Firestore [Minor]

**File:** `lib/features/home/data/home_repository.dart`, line 669.

```dart
e.key == 0 ? '${e.value.name} (Skipper)' : e.value.name
```

The `crew:` prefix is handled as a sentinel with localised display, but `(Skipper)` is stored as raw English text within the name field. It appears verbatim in the timeline for both locales. For the two supported locales (DE/EN), "Skipper" is identical, so the practical impact is currently zero. If a third locale is added (e.g. French — "Capitaine"), the stored annotation will remain in English.

**Severity:** Minor — no visible impact with current EN/DE support; document as a known limitation or extend the sentinel pattern.

---

### F-4 `forceSync` exception message hardcoded German [Minor]

**File:** `lib/features/home/data/home_repository.dart`, line 518.

```dart
throw Exception('Cloud-Sync nicht verfügbar.');
```

This message may surface in error dialogs or logs depending on how callers handle it.

**Severity:** Minor — visible only if the caller renders the exception message directly.

**Recommendation:** Replace with a typed exception or an error code. Example: define `class SyncUnavailableException implements Exception {}` and handle it in the UI with `l10n`.

---

### F-5 `_buildEntryText` helper uses German labels throughout [Minor]

**File:** `lib/features/home/presentation/day_detail_screen.dart`, lines 3341–3350.

`_buildEntryText` is a top-level helper used for PDF export and the timeline tooltip text. It constructs German-labelled strings:

```dart
if (t.wind?.isNotEmpty == true) cond.add('Wind: ${t.wind!}');
if (t.sea?.isNotEmpty  == true) cond.add('See: ${t.sea!}');
if (t.weather?.isNotEmpty == true) cond.add('Wetter: ${t.weather!}');
if (t.grossState?.isNotEmpty == true) sails.add('Gross: ${t.grossState}');
if (t.fockState?.isNotEmpty  == true) sails.add('Fock: ${t.fockState}');
if (t.motorOn  != null) sails.add('Motor: ${t.motorOn! ? 'An' : 'Aus'}');
if (t.keelDown != null) sails.add('Kiel: ${t.keelDown! ? 'Unten' : 'Oben'}');
```

This function is not passed an `AppLocalizations` instance because it is a top-level function (not a widget method). Wind/sea/weather fields are free text entered by the user so their labels are the localisation concern. The sails and motor states are structured data.

**Severity:** Minor — PDF exports will always use German field labels regardless of locale.

**Recommendation:** Pass `AppLocalizations l10n` as a parameter to `_buildEntryText`, or move it to a method inside `_DayDetailScreenState` where `context.l10n` is accessible.

---

### F-6 Oil-level scale lower bound hardcoded as `'MIN'` [Minor]

**File:** `lib/features/home/presentation/day_detail_screen.dart`, line 1719.

```dart
isFuel ? context.l10n.vesselEmptyLabel.toUpperCase() : 'MIN',
```

The fuel gauge lower bound uses `l10n.vesselEmptyLabel`. The oil gauge lower bound uses the hardcoded string `'MIN'`. The `vesselFullLabel` is used for both right-side labels. The asymmetry is inconsistent — both should use the same l10n pattern.

**Severity:** Minor — cosmetic inconsistency.

**Recommendation:** Either reuse `vesselEmptyLabel` for oil, or add `vesselOilMinLabel` to both ARB files.

---

### F-7 `listLogbooks` performs N+1 sequential Firestore reads [Minor]

**File:** `lib/core/services/logbook_service.dart`, lines 63–91.

For each logbook ID in the user's `logbooks` array, two sequential round-trips are made: one to `logbooks/{id}` and one to `logbooks/{id}/members/{uid}`. For N logbooks this is 1 + 2N reads. Called only on settings mount and pull-to-refresh, so low-frequency; but on slow connections the spinner will be visible for noticeably longer.

**Severity:** Minor — performance on slow connections; acceptable for current scale.

**Recommendation:** Embed `role` inside the user's `logbooks` array entries (change from array of strings to array of `{id, role}` maps), eliminating the per-logbook member read. The logbook name and shareCode still require one `logbooks/{id}` read per logbook, but halving the round trips is already a meaningful improvement.

---

### F-8 `'CREW STATUS'` label in MaydayScreen lacks a SOLAS comment [Nitpick]

**File:** `lib/features/emergency/presentation/mayday_screen.dart`, line 911.

`_StepCrew` uses `'CREW STATUS'` as a hardcoded English label without an inline comment explaining the SOLAS/IMO rationale (unlike the other hardcoded strings in the same file). This breaks the established self-documentation pattern.

**Severity:** Nitpick — no runtime impact.

**Recommendation:** Add comment `// IMO GMDSS protocol term — kept in English per SOLAS.` or localise via ARB.

---

### F-9 Duplicate ARB keys `statSailingDays` / `statDays` [Nitpick]

**File:** `lib/l10n/app_en.arb`, lines 23–24 (`lib/l10n/app_de.arb` similarly).

Both keys translate to "Days" / "Tage". `statSailingDays` is the label; `statDays` is used as a unit suffix. The duplication is harmless but adds confusion when updating translations.

**Severity:** Nitpick — no runtime impact.

---

---

## 11. Scoped Re-assessment — 2026-06-25

### Subsystem: PDF Export

**File:** `lib/features/home/utils/pdf_exporter.dart`

---

#### F-11-PDF-1 — All section labels, column headers, and route text are hardcoded German [Major]

`buildVoyagePdf` is a top-level async function with no `BuildContext` or locale parameter, so it cannot call `l10n`. Every user-visible string in the document is hardcoded German:

| Location | Hardcoded string |
|---|---|
| Line 124 | `'TAGEBUCH'` |
| Line 136 | `'NOTIZEN'` |
| Line 215 | `'Passage nach $to'` / `'Abfahrt von $from'` |
| Line 228 | `'Abfahrt von $from'` |
| Line 238 | `'DATUM'` |
| Lines 260–264 | `'DISTANZ'`, `'Ø FAHRT'`, `'MAX'`, `'FAHRZEIT'`, `'STOPPS'` |
| Line 286 | `'STATISTIK'` |
| Line 319 | `'CREW'` |
| Line 349 | `'SKIPPER'` / `'BESATZUNG'` |
| Lines 381–388 | `'Zeit'`, `'Kurs'`, `'kn'`, `'Wind'`, `'See'`, `'Motor'`, `'Segel'`, `'Bemerkungen'` |
| Line 429 | `'AN'` / `'AUS'` for motor state |
| Line 443 | `'LOGBUCH-EINTRÄGE'` |
| Line 532 | `'Seite ${ctx.pageNumber} von ${ctx.pagesCount}'` |
| Line 561 | `'KURS & TRACK'` |

**Recommendation:** Add a `PdfStrings` value-object parameter to `buildVoyagePdf` (e.g. `PdfStrings strings`) populated from `l10n` at the call site in `day_detail_screen.dart` (line 2724). The call site already has `BuildContext`, so strings can be extracted there before the `await`. The function stays pure-Dart and testable.

---

#### F-11-PDF-2 — Date format hardcoded to `de_CH` locale [Major]

Line 216:
```dart
final dateStr = DateFormat('d. MMM yyyy', 'de_CH').format(date);
```
This always renders the date in Swiss German regardless of the user's language setting. An English-locale user would see `"15. Jun 2026"` instead of `"Jun 15, 2026"`.

**Recommendation:** Accept `String locale` in the `PdfStrings` bundle (or as a direct parameter) and pass `tp.localeString` from the call site.

---

#### F-11-PDF-3 — `_fetchTile` silently swallows all errors [Minor]

Line 639:
```dart
} catch (_) {
  return null;
}
```
Network errors during tile download are expected and the null fallback is correct, but losing the exception silently makes debugging hard (e.g. API key errors, rate-limit 429s). 

**Recommendation:** Log the error in debug mode: `if (kDebugMode) debugPrint('Tile $z/$tx/$ty failed: $_');`.

---

#### F-11-PDF-4 — `sailAbbr` logic uses German string literals stored in Hive [Minor]

Lines 398–401:
```dart
if (s.contains('Voll') || s.contains('Gesetzt')) return 'VG';
if (s.contains('1.') || s.contains('R1'))        return 'R1';
if (s.contains('2.') || s.contains('R2'))        return 'R2';
```
The abbreviation logic depends on `grossState` / `fockState` values being in German. If the stored strings ever differ (e.g. from a future English chip set), the abbreviation silently returns `'—'`. This is a latent fragility, not a current crash risk.

**Recommendation:** Use sentinel constants for sail states (like the existing `vs:` / `crew:` pattern) so the abbreviation table is locale-independent.

---

### Subsystem: Crew Roster

**File:** `lib/features/home/screens/crew_roster_screen.dart`

---

#### F-11-CREW-1 — `'BG '` prefix on blood type is hardcoded German [Minor]

Line 101:
```dart
if (member.bloodType != null) parts.add('BG ${member.bloodType}');
```
`BG` is the German abbreviation for _Blutgruppe_ (blood group). An English UI user sees `BG A+` where they would expect `Blood group: A+` or simply `A+`.

**Recommendation:** Use `l10n.crewBloodGroupPrefix(member.bloodType!)` or at minimum just output the raw value (`member.bloodType!`) since the preceding field label already contextualises it.

---

#### F-11-CREW-2 — No `if (!mounted) return` after the `await showDialog` in `_confirmDelete` [Minor]

Line 144:
```dart
if (!context.mounted || confirmed != true) return;
repo.deleteRosterMember(member.id!);
```
The `context.mounted` check here is on a `StatelessWidget` method receiving a `BuildContext` passed in via parameter, not a `State` object. `BuildContext.mounted` is only available for elements; the check is valid, but the method also calls `Navigator.pop(context, true)` (line 139) on a potentially-stale context passed from `_edit`. If the widget is disposed between the two dialog `await`s, the deletion proceeds but any scaffold messenger call would throw.

**Severity:** Minor — the mounted check does protect the delete call. Acceptable as-is; just note that the context chain passes through two levels of `await showDialog`.

**Recommendation:** No immediate change required, but document the two-level dialog chain in a comment.

---

#### F-11-CREW-3 — Screen is clean otherwise [Informational]

All user-visible strings go through `context.l10n`. Navigation uses `Navigator.of(context).pop()` correctly. `FloatingActionButton` has `tooltip` set (line 76). Error handling is provided by the confirm dialog. No logic bugs found.

---

### Subsystem: Timeline Entry Dialog

**File:** `lib/features/home/widgets/add_timeline_entry_dialog.dart`

---

#### F-11-TL-1 — Keel chip labels `'Unten'` / `'Oben'` are hardcoded German [Major]

Lines 438–441:
```dart
_stateChip('Unten', _keelDown == true, ..., cs),
...
_stateChip('Oben', _keelDown == false, ..., cs),
```
The ARB keys `vesselKeelDown` ("Down" / "Unten") and `vesselKeelUp` ("Up" / "Oben") exist and are used elsewhere (e.g. on the day card). These chips bypass l10n.

**Recommendation:** Replace with `l10n.vesselKeelDown` and `l10n.vesselKeelUp`.

---

#### F-11-TL-2 — Sail state chip options are hardcoded German [Major]

Lines 396 and 405:
```dart
options: const ['Voll gesetzt', '1. Reff', '2. Reff', 'Niedergeholt'],
options: const ['Voll gesetzt', '1. Reff', '2. Reff', 'Eingerollt'],
```
These strings are stored directly in `TimelineEntry.grossState` / `fockState` in Hive. Localising the chips requires a two-step approach: keep the stored sentinel values locale-neutral but display them via l10n.

**Recommendation:** Store sentinel values (e.g. `'full'`, `'reef1'`, `'reef2'`, `'furled'`, `'lowered'`) and translate to display strings via an l10n lookup function. The PDF `sailAbbr` function (finding F-11-PDF-4) will benefit from this at the same time.

---

#### F-11-TL-3 — Speed hint `'kts'` unit label is not localised [Nitpick]

Line 210: `unit: 'kts'`. The unit is an abbreviation and is acceptable in English, but `kn` is used everywhere else in the app (speed fields in timeline table headers, stats display). Inconsistency only; not a l10n gap.

**Recommendation:** Change `'kts'` to `'kn'` for consistency with the rest of the UI.

---

#### F-11-TL-4 — `'KN'` wind unit label is hardcoded [Nitpick]

Line 334: `'KN'` rendered as an inline unit label.

**Recommendation:** Same as above — use `'kn'` (lower-case) consistent with rest of the app.

---

### Subsystem: Crew Member Add Dialog

**File:** `lib/features/home/widgets/add_crew_member_dialog.dart`

No issues found. All user-visible strings go through `context.l10n`. No hardcoded German. `Colors.black.withValues(alpha: 0.04)` (line 290) is used for a card shadow — this is conventional and not a theming concern. Dispose is complete. Input validation (name must not be empty, line 49) is correct.

---

### Subsystem: Stats Computation

**Files:** `lib/features/home/utils/compute_daily_stats.dart`, `lib/features/home/presentation/home_screen.dart`

---

#### F-11-STATS-1 — "Days at Sea" counts GPX-track days only (confirmed open issue 2.5) [Major]

`home_screen.dart` lines 270–279: the `daysAtSea` counter iterates `repo.dailyTracks` (GPX-backed `DailyTrack` objects). A day that has logbook entries but no uploaded GPX track (e.g. a manual log of an entry on anchor, or an entry made before GPS logging was started) does not increment the counter. This is a known limitation that was documented as open issue 2.5.

**Recommendation:** Count a day as "at sea" if _either_ `repo.dailyTracks[day]` contains points with `distanceNm > 0` OR the corresponding `DayEntry.distanceNm > 0`. This also allows entries synced from Firestore (no local GPX) to be counted.

---

#### F-11-STATS-2 — `DailyStats` values in `DayEntry` (fields 6–10) are stale/unused by the stats display [Minor]

`DayEntry` persists `distanceNm`, `totalDurationSeconds`, `movingDurationSeconds`, `avgSpeedKnots`, `maxSpeedKnots` (HiveFields 6–10). However, all stats displayed in the UI are re-computed on demand from raw track points via `computeDailyStats(track.points, ...)`. The Hive-stored stats appear to be written during GPX import but are never read back for display. This creates a redundancy: the fields take up space and could show stale values if the filter settings (e.g. making-way threshold) change.

**Recommendation:** Either remove the persisted stats fields (breaking change requiring migration) or add a comment clarifying they are legacy fields kept for Firestore sync compatibility.

---

#### F-11-STATS-3 — `computeDailyStats` correctness: no issues [Informational]

The algorithm is correctly ported: Haversine distance, p99 max-speed, separate making-way averaging, anchor-stop exclusion. No off-by-one or null-dereference risks found.

---

### Subsystem: Hive Schema Safety

**Files:** `day_entry.dart/.g.dart`, `timeline_entry.dart/.g.dart`, `crew_member.dart/.g.dart`

---

#### F-11-HIVE-1 — Retired field indices are correctly tombstoned [Informational]

`DayEntry` documents retired field indices 3, 11–14 with comments (`// @HiveField(3) hasGpx — retired`). `TimelineEntry` tombstones indices 7–12. These are never written, so old objects lacking them deserialise safely via the `fields[N] as Type?` nullable cast pattern in the generated adapters. No gap found.

---

#### F-11-HIVE-2 — New nullable fields (`keelDown`, `photos`, `vesselStatusNote`) are safe on old objects [Informational]

The generated adapters read these with `fields[N] as bool?`, `(fields[N] as List?)?.cast<String>()`, etc. If the field is absent in an old persisted record, `fields[N]` is `null` and the nullable cast is safe. The `DayEntry` constructor defaults `photos` to `<String>[]` and `keelDown` to `null`. No migration risk.

---

#### F-11-HIVE-3 — No explicit migration path; relies on Hive's field-map format [Minor]

Hive uses a field-map serialisation (each field prefixed by its index byte), so unknown fields in old data are silently dropped and missing fields default to `null` in the constructor. This is correct for nullable and defaulted fields. However, there is no code to migrate non-nullable fields that were added later. Specifically: if `distanceNm` (field 6, `double`, non-nullable, default `0.0`) were absent in a very old record created before that field existed, Hive would pass `null` to a `double` parameter and throw a `TypeError` at runtime.

In practice, `distanceNm` has been present since v1 and all currently stored records should have it. No immediate bug risk, but the absence of a migration harness means future non-nullable additions carry risk.

**Recommendation:** Document the invariant in a code comment: _"All non-nullable fields must have existed since the initial release or carry a Dart default value. Never add a required non-nullable `@HiveField` without a migration."_

---

#### F-11-HIVE-4 — `DayEntry.g.dart` writer declares `writeByte(17)` — count verified correct [Informational]

Indices written: 0, 1, 2, 4, 5, 6, 7, 8, 9, 10, 15, 16, 17, 18, 19, 20, 21 = 17 fields. Count matches. `TimelineEntry.g.dart` declares `writeByte(12)`: indices 0–6, 13–17 = 12 fields. Count matches.

---

### Subsystem: Auth Screens

**Files:** `login_screen.dart`, `register_screen.dart`, `forgot_password_screen.dart`

---

#### F-11-AUTH-1 — `too-many-requests` and `user-disabled` Firebase errors fall through to generic message [Minor]

`AuthService.codeToKey` (line 101–117 of `auth_service.dart`) maps only six error codes. The unmapped codes `too-many-requests` (rate-limited) and `user-disabled` (admin-disabled account) both fall through to `authErrorGeneric`. On a rate-limited login attempt, the user sees a generic error with no guidance to wait before retrying.

**Recommendation:** Add `'too-many-requests': 'authErrorTooManyRequests'` and `'user-disabled': 'authErrorUserDisabled'` to `codeToKey`, with corresponding ARB keys and strings like _"Too many sign-in attempts. Please wait a moment and try again."_

---

#### F-11-AUTH-2 — `_signIn` / `_signInGoogle` / `_signInApple` swallow non-Firebase errors silently [Minor]

`login_screen.dart` lines 72 and 87:
```dart
} catch (_) {
  _showError(genericError);
}
```
The generic error is shown, which is the correct fallback. However, using `catch (_)` discards the error object, making crash diagnostics impossible. The `FirebaseAuthException` branch above captures structured errors. The catch-all here is safe for users but opaque in production.

**Recommendation:** Change to `catch (e)` and log in debug mode: `if (kDebugMode) debugPrint('Auth error: $e');`.

---

#### F-11-AUTH-3 — `register_screen.dart` missing `if (!mounted) return` after Google sign-in await [Minor]

`register_screen.dart` line 74:
```dart
await auth.signInWithGoogle();
if (mounted) context.go('/');
```
The `mounted` check is present. However, unlike `login_screen.dart`, `_showError` in `register_screen.dart` (line 37) also checks `if (!mounted) return`. This is consistent and correct. No bug.

---

#### F-11-AUTH-4 — Auth screens are otherwise clean [Informational]

All user-visible strings use `l10n`. Form validators use localised error strings. `_loading` guard prevents double-submit. `dispose()` releases all controllers. The `ForgotPasswordScreen` correctly shows a confirmation view after email is sent rather than navigating away.

---

### Subsystem: Widgets (KeelIcon, NavBar)

**Files:** `lib/features/home/widgets/keel_icon.dart`, `lib/features/home/widgets/nav_bar.dart`

---

#### F-11-NAV-1 — Three of four nav tab labels are hardcoded strings [Major]

`nav_bar.dart` lines 97, 100–101:
```dart
_tab(context, cs, NavTab.journal,  Icons.auto_stories,      'Journal'),
_tab(context, cs, NavTab.settings, Icons.settings_outlined, 'Einstellungen'),
_tab(context, cs, NavTab.safety,   Icons.health_and_safety, 'Sicherheit'),
```
`NavTab.map` already uses `context.l10n.tracksTitle` (line 98). The other three tabs use hardcoded strings, two of which are German. `settingsTitle` and `emergencyTitle` ARB keys already exist (`lib/l10n/app_en.arb` lines 144 and surrounding); `appTitle` exists but is "Logbook" not "Journal".

**Recommendation:**
- `NavTab.journal` → `l10n.appTitle` (or add a dedicated `navJournal` ARB key)
- `NavTab.settings` → `l10n.settingsTitle`
- `NavTab.safety` → add ARB key `navSafety` ("Safety" / "Sicherheit") since no exact match exists

---

#### F-11-NAV-2 — `'Offline'` indicator label is hardcoded [Minor]

`nav_bar.dart` line 123:
```dart
'Offline',
```
The ARB key `offlineBanner` ("Offline — changes saved locally") exists but is a longer string used elsewhere. A short `offlineLabel` key ("Offline") should be added and used here.

**Recommendation:** Add `"offlineLabel": "Offline"` / `"Offline"` to both ARB files and use `context.l10n.offlineLabel` on line 123.

---

#### F-11-NAV-3 — Centre FAB has no `Tooltip` or `Semantics` label [Minor]

`nav_bar.dart` lines 146–163: the raised centre FAB is a `GestureDetector` wrapping a plain `Container` with an `Icon`. There is no `Tooltip`, `Semantics`, or `MergeSemantics` wrapper, so screen readers announce nothing meaningful for this control.

**Recommendation:** Wrap with `Tooltip(message: l10n.addEntryTooltip, child: Semantics(button: true, label: l10n.addEntryTooltip, child: GestureDetector(...)))`.

---

#### F-11-NAV-4 — `KeelIcon` has no accessibility annotation [Nitpick]

`keel_icon.dart`: `KeelIcon` is a `CustomPaint` widget with no `Semantics` wrapper. When rendered as a standalone status indicator in the UI (e.g. on the day card), screen readers cannot describe the keel state.

**Recommendation:** Wrap the `CustomPaint` at the call site or in `KeelIcon.build` with `Semantics(label: keelDown == null ? '' : keelDown! ? l10n.vesselKeelDown : l10n.vesselKeelUp)`. Since `KeelIcon` has no `BuildContext`, this is best done at the call site.

---

### Summary of New Findings (Pass 3)

| Severity | Count | Items |
|---|---|---|
| **Critical** | 0 | — |
| **Major** | 5 | PDF hardcoded German (F-11-PDF-1), PDF date locale (F-11-PDF-2), keel chips hardcoded (F-11-TL-1), sail state chips hardcoded (F-11-TL-2), nav bar tab labels hardcoded (F-11-NAV-1) |
| **Minor** | 8 | PDF `sailAbbr` fragility (F-11-PDF-4), PDF tile catch swallows errors (F-11-PDF-3), crew `BG` prefix (F-11-CREW-1), days-at-sea counting (F-11-STATS-1), stale persisted stats (F-11-STATS-2), Hive no migration harness (F-11-HIVE-3), auth `too-many-requests` (F-11-AUTH-1), auth catch swallows (F-11-AUTH-2), offline label (F-11-NAV-2), FAB no tooltip (F-11-NAV-3) |
| **Nitpick** | 3 | `'kts'` vs `'kn'` inconsistency (F-11-TL-3), `'KN'` wind unit (F-11-TL-4), `KeelIcon` no semantics (F-11-NAV-4) |

> **Note:** Minor count is 10 in the table rows above. Totals: 0 Critical · 5 Major · 10 Minor · 3 Nitpick = **18 new findings**.

---

## 10. What's Working Well

- **Offline-first sync** is thoughtfully designed: Hive local cache, incremental pull by `updatedAt`, debounced push, conflict resolution by modification timestamp.
- **GPS track filtering pipeline** (`trim_track.dart`) is a sophisticated 6-pass algorithm that handles real-world GPS noise well.
- **Multi-logbook architecture** with `shareCode` lookup pattern is clean. Firestore security rules correctly model ownership vs. guest membership. Storage rules now match.
- **Emergency manifest** pulling live crew from today's entry (or fallback to last crew) is a thoughtful UX decision.
- **Theme extensions** are properly implemented and used throughout the emergency and timeline screens, providing semantic colour tokens.
- **Crew sentinel pattern** (`crew:…`) correctly separates the stored representation from the localised display label — this pattern should be extended to vessel status notes.
- **Auto-snapshot of crew and vessel status on first timeline entry** is a smart "log it once" UX pattern.
- **PDF export** generates a well-structured A4 report with map thumbnail, stats, timeline, and crew columns.
- **Account deletion flow** now has an offline guard, user-friendly error handling, and no silent swallowing.
- **Dart static analysis** reports zero issues.
- **Firestore `deleteCollectionInChunks`** correctly chunks batch deletes at 400 docs to stay within Firestore limits.
- **GoRouter redirect guard** correctly handles unauthenticated deep-links to `/auth/login` and prevents signed-in users from staying on auth screens.
