# Logbook App — Technical Documentation
**Date:** 2026-06-25  
**Version:** 1.0.21+21  
**Flutter SDK:** ^3.11.0  
**Firebase project:** logbook-auth-dev

---

## Table of Contents

1. [App Overview](#1-app-overview)
2. [Architecture](#2-architecture)
3. [Firestore Data Model](#3-firestore-data-model)
4. [Authentication Flow](#4-authentication-flow)
5. [Offline-First Sync Strategy](#5-offline-first-sync-strategy)
6. [Feature: Journal (Home Screen)](#6-feature-journal-home-screen)
7. [Feature: Day Detail](#7-feature-day-detail)
8. [Feature: Crew Management](#8-feature-crew-management)
9. [Feature: GPS Tracks Screen](#9-feature-gps-tracks-screen)
10. [Feature: Emergency Module](#10-feature-emergency-module)
11. [Feature: Settings](#11-feature-settings)
12. [GPS Track Filtering Pipeline](#12-gps-track-filtering-pipeline)
13. [Map Display](#13-map-display)
14. [PDF Export](#14-pdf-export)
15. [Theme System](#15-theme-system)
16. [Localisation](#16-localisation)
17. [Build & Deployment](#17-build--deployment)
18. [Known Platform Issues](#18-known-platform-issues)
19. [Existing Documentation Scripts](#19-existing-documentation-scripts)

---

## 1. App Overview

**Logbook** is an offline-first maritime logbook application for iOS, Android, and macOS. It records sailing voyages as daily entries containing:

- A timeline of navigational observations (course, speed, wind, sea state, sail state, motor state)
- Diary / narrative notes
- Crew manifest (with medical data for emergencies)
- Vessel status (oil level, fuel level, keel position)
- GPS tracks (GPX format) with computed voyage statistics
- Photos

Multiple users can share a single logbook via an 8-character share code (QR code or manual entry). Data is stored locally in Hive and synced to Cloud Firestore in real time.

---

## 2. Architecture

### 2.1 Package structure

```
lib/
├── app/
│   ├── app.dart                  # Root MaterialApp widget
│   ├── router.dart               # go_router configuration
│   └── theme/
│       ├── light_theme.dart
│       ├── dark_theme.dart
│       └── theme_extensions.dart # (stub — empty)
├── core/
│   ├── constants/
│   │   └── map_config.dart       # Tile server URL constant
│   └── services/
│       ├── auth_service.dart     # Firebase Auth wrapper (ChangeNotifier)
│       ├── logbook_service.dart  # Logbook identity & membership (Firestore)
│       ├── firestore_service.dart# DayEntry/settings/contacts sync
│       ├── storage_service.dart  # Firebase Storage (GPX tracks, photos)
│       ├── bootstrap_service.dart# First-run setup
│       └── gps_consent_service.dart
├── features/
│   ├── auth/presentation/        # Login, Register, ForgotPassword screens
│   ├── home/
│   │   ├── data/
│   │   │   └── home_repository.dart   # ChangeNotifier, Hive+Firestore
│   │   ├── domain/               # DayEntry, TimelineEntry, DailyTrack, TrackPoint, CrewMember
│   │   ├── presentation/
│   │   │   ├── home_screen.dart  # Journal list view
│   │   │   └── day_detail_screen.dart # ~3500-line single-day view
│   │   ├── screens/
│   │   │   └── crew_roster_screen.dart
│   │   ├── utils/
│   │   │   ├── trim_track.dart         # 6-pass GPS filter (993 lines)
│   │   │   ├── filter_settings.dart    # FilterSettings, StationaryMode enum
│   │   │   ├── track_correlation.dart  # Match timeline entries to GPS points
│   │   │   ├── compute_daily_stats.dart
│   │   │   ├── gpx_parser.dart / gpx_exporter.dart
│   │   │   ├── pdf_exporter.dart
│   │   │   └── photo_service.dart
│   │   └── widgets/              # NavBar, dialogs, keel icon, …
│   ├── emergency/                # EmergencyManifestScreen, MaydayScreen, EmergencyScreen
│   ├── settings/
│   │   ├── domain/theme_provider.dart  # ChangeNotifier for settings, vessel data
│   │   └── presentation/settings_screen.dart
│   └── tracks/presentation/tracks_screen.dart
└── l10n/
    ├── app_de.arb
    ├── app_en.arb
    └── l10n_extension.dart       # BuildContext.l10n shorthand
```

### 2.2 State Management

The app uses `provider` (`^6.1.2`) for all shared state. All providers are created once in `main.dart` and injected with `MultiProvider` at the root.

| Provider | Type | Purpose |
|----------|------|---------|
| `HomeRepository` | `ChangeNotifier` | All daily entries, tracks, crew roster. Hive + Firestore sync. |
| `ThemeProvider` | `ChangeNotifier` | App theme, locale, vessel settings, filter settings, month expansion. |
| `EmergencyRepository` | `ChangeNotifier` | Emergency contacts. Hive + Firestore sync. |
| `AuthService` | `ChangeNotifier` | Firebase Auth wrapper, `currentUser`. Also used as `GoRouter` refresh listenable. |
| `ValueNotifier<String?>` | `ValueNotifier` | Current active `logbookId`. Null until Firestore init completes. |

### 2.3 Navigation

Navigation uses `go_router ^17.2.3`. The router is constructed in `router.dart`:

```
/auth/login          → LoginScreen
/auth/register       → RegisterScreen
/auth/forgot-password→ ForgotPasswordScreen

/                    → HomeScreen (journal list)
/day/:year/:month/:day → DayDetailScreen  [?addEntry=1 opens timeline dialog]
/settings            → SettingsScreen
/tracks              → TracksScreen
/emergency           → EmergencyManifestScreen
/emergency/mayday    → MaydayScreen
/emergency/distress  → EmergencyScreen
```

The router uses `AuthService` as its `refreshListenable`. A redirect rule routes unauthenticated users to `/auth/login` and authenticated users away from `/auth/*` to `/`.

`ThemeProvider.lastRouteToday` persists the last-visited route to Hive so the app reopens to the same screen on the same calendar day (resets to `/` on a new day).

### 2.4 Local Storage — Hive

The app uses Hive 2.x for local persistence. Boxes:

| Box | Key type | Value type | Purpose |
|-----|----------|------------|---------|
| `daily_entries` | `String` (ISO date) | `DayEntry` | Journal entries |
| `daily_tracks` | `String` (ISO date) | `DailyTrack` | GPX tracks |
| `crew_roster` | `String` (member ID) | `CrewMember` | Shared crew roster |
| `entry_sync_state` | `String` | `int` (epoch ms) | Local edit timestamps + last-sync-at |
| `settings` | `String` | `String` | ThemeProvider key-value store |
| `emergency` | (numeric) | `EmergencyContact` | Emergency contacts |

Hive adapters are generated by `hive_generator` (via `build_runner`) for all domain classes.

---

## 3. Firestore Data Model

```
users/{uid}
  ├── activeLogbookId: String
  └── logbooks: String[]          # list of logbook IDs the user belongs to

logbooks/{logbookId}
  ├── name: String
  ├── ownerUid: String
  ├── shareCode: String           # 8-char alphanumeric code
  ├── createdAt: Timestamp
  │
  ├── members/{uid}
  │   ├── role: 'owner' | 'guest'
  │   └── joinedAt: Timestamp
  │
  ├── entries/{yyyy-MM-dd}       # one document per day
  │   ├── date: String           # 'yyyy-MM-dd'
  │   ├── fromHarbor: String?
  │   ├── toHarbor: String?
  │   ├── notes: String?         # diary / narrative
  │   ├── freeText: String?      # free-form notes
  │   ├── oilLevel: int?         # 0-100%
  │   ├── fuelLevel: int?        # 0-100%
  │   ├── keelDown: bool?
  │   ├── distanceNm: double     # legacy — always 0, not computed
  │   ├── avgSpeedKnots: double  # legacy — always 0, not computed
  │   ├── maxSpeedKnots: double  # legacy — always 0, not computed
  │   ├── totalDurationSeconds: int  # legacy
  │   ├── movingDurationSeconds: int # legacy
  │   ├── participantsList: String[] # legacy — use crew[] instead
  │   ├── photos: String[]       # Firebase Storage download URLs
  │   ├── crew: CrewMember[]
  │   │   ├── name: String
  │   │   ├── bloodType: String?
  │   │   ├── allergies: String?
  │   │   ├── conditions: String?
  │   │   └── remarks: String?
  │   ├── timeline: TimelineEntry[]
  │   │   ├── time: String (UTC ISO-8601)
  │   │   ├── course: double?    # degrees
  │   │   ├── speed: double?     # knots
  │   │   ├── wind: String?      # free text, e.g. "SW 15 kn"
  │   │   ├── sea: String?       # free text
  │   │   ├── weather: String?   # free text
  │   │   ├── remarks: String?
  │   │   ├── grossState: String? # main sail state
  │   │   ├── fockState: String?  # jib state
  │   │   ├── motorOn: bool?
  │   │   ├── keelDown: bool?
  │   │   └── vesselStatusNote: String?  # auto-generated sentinel notes
  │   └── updatedAt: Timestamp    # server timestamp for incremental sync
  │
  └── meta/
      ├── settings               # vessel name, MMSI, call sign, life raft, EPIRB, fire suppression, VHF 1-4
      ├── contacts               # emergency contacts list
      ├── ui                     # month-expansion state map
      └── crew_roster            # shared crew roster (name, blood type, allergies, conditions, remarks, id)

shareCodes/{8-char-code}
  └── logbookId: String          # lookup table for QR code join flow
```

### Security Rules Summary

```javascript
// Firestore rules (deployed to logbook-auth-dev)
// isSignedIn() → request.auth != null
// isMember(logbookId) → members/{uid} exists
// isOwner(logbookId) → members/{uid}.role == 'owner'

match /shareCodes/{code} {
  allow read: if isSignedIn();
  allow create: if isSignedIn();
  allow update, delete: if isSignedIn() && isMember(resource.data.logbookId);
}

match /logbooks/{logbookId} {
  allow read: if isMember(logbookId);
  allow create: if isSignedIn() && ownerUid == request.auth.uid;
  allow update, delete: if isOwner(logbookId);

  match /{collection}/{document=**} { allow read, write: if isMember(logbookId); }

  match /members/{uid} {
    allow write: if isOwner(logbookId);
    allow create: if isSignedIn() && uid == request.auth.uid && role == 'guest';
    allow read: if isMember(logbookId);
  }
}
```

### Storage Rules Summary

```
match /logbooks/{logbookId}/{allPaths=**} {
  allow read, write: if request.auth != null;
}
```

> **Note:** Storage rules only check authentication, not Firestore membership. See assessment report §6.1.

---

## 4. Authentication Flow

`AuthService` wraps Firebase Auth and supports three sign-in methods:

| Method | Implementation |
|--------|---------------|
| Email / Password | `signInWithEmailAndPassword`, `createUserWithEmailAndPassword` |
| Google | `google_sign_in` package, `GoogleAuthProvider.credential` |
| Apple | `sign_in_with_apple` package, `OAuthProvider('apple.com').credential` |

### Startup Sequence

```
main() async {
  1. Hive.initFlutter(), register Hive adapters
  2. HomeRepository.init()   → open Hive boxes, load local data
  3. EmergencyRepository.init()
  4. ThemeProvider.init()    → load settings from Hive
  5. Firebase.initializeApp()
  6. FirestoreService.configure()  → enable 50MB persistence cache
  7. If currentUser != null → _initFirestore(user, ...) [unawaited]
  8. authStateChanges.listen → call _initFirestore on null→user transition
  9. Connectivity.onConnectivityChanged → retry _initFirestore if logbookId == null
  10. buildRouter(lastRouteToday, authService)
  11. runApp(MultiProvider(...))
}
```

### `_initFirestore` (called after sign-in)

1. **Account switch detection:** Compare `themeProvider.lastKnownUid` with `user.uid`. If different, wipe all local Hive data and reset vessel settings (prevents previous user's data from polluting the new account's Firestore).
2. **Logbook resolution:** `LogbookService.getActiveLogbookId(uid)`. If null (new user), call `LogbookService.createLogbook(uid, 'My Logbook')`.
3. **Service construction:** `FirestoreService(logbookId:)`, `StorageService(logbookId:)`.
4. **Parallel attach:** `repo.attachFirestore`, `repo.attachStorage`, `themeProvider.attachFirestore`, `emergencyRepo.attachFirestore`.
5. **Initial sync flag:** `themeProvider.needsInitialSync` drives whether the attach uses conservative "push all local, pull missing" (first sync) or incremental "push edits since last sync, pull updates since last sync" (subsequent syncs).
6. Set `logbookIdNotifier.value = logbookId`.

### Offline Sign-In

Firebase Auth caches the auth token locally. If the device is offline, `FirebaseAuth.currentUser` returns the cached user and sign-in with the cached credential works. Fresh sign-in (new credentials) requires network. A warning is shown in the sign-out dialog when offline.

### Sign-Out Flow

1. `GoogleSignIn().signOut()` (no-op if not signed in with Google)
2. `FirebaseAuth.signOut()`
3. `AuthService.notifyListeners()` → GoRouter redirect fires → user lands on `/auth/login`

---

## 5. Offline-First Sync Strategy

### 5.1 DayEntry Sync (`HomeRepository`)

**Local writes:** Every mutation (`saveEntry`, `addTimelineEntry`, etc.) writes to Hive immediately and records the wall-clock time as the "local edit timestamp" (`entry_sync_state` box). A 2-second debounced Firestore push follows.

**On attach / reconnect (`attachFirestore`):**

1. **Push offline edits:** For each local entry whose edit timestamp is after `last_sync_at`, push to Firestore.
2. **Pull remote changes:** Fetch entries whose `updatedAt` server timestamp is after `last_sync_at`. Skip entries that were locally edited after `last_sync_at` (our pending write takes precedence).
3. Update `last_sync_at` to now.
4. **Subscribe to real-time stream:** `entryChanges()` emits `{upserted, removed}` on every Firestore document change. On each event, apply remote changes, skipping entries currently being debounced (user is actively editing).

**Conflict resolution:** Last-writer-wins by timestamp. The local edit timestamp vs. the Firestore `updatedAt` server timestamp determines which version prevails.

**Initial sync (first login or new device):**
- Push all local entries (migration path for devices that had data before cloud sync was configured).
- Pull only entries absent from local (`fetchMissingEntries`) to avoid overwriting existing data.

### 5.2 Settings Sync (`ThemeProvider`)

Vessel settings, VHF frequencies, and UI state (month expansion map) are stored in `logbooks/{logbookId}/meta/{settings,ui}`. The same last-writer-wins approach is used: a local `_settingsModifiedAt` epoch is compared against the server `updatedAt`. A real-time stream applies remote changes while the app is running, de-duplicated by map equality comparison.

### 5.3 GPX Tracks (`StorageService`)

GPX tracks are stored in Firebase Storage at `logbooks/{logbookId}/tracks/{date}.gpx`. They are not included in Firestore sync. On attach:
- List all track dates in Storage.
- Download any dates not present locally.
- Upload is done immediately when the user imports a GPX file.

### 5.4 Photos

Photos are stored at `logbooks/{logbookId}/photos/{yyyy-MM-dd}/{uuid}.jpg`. The download URLs are stored in `DayEntry.photos`. Upload happens immediately via `photo_service.dart` using `flutter_image_compress` and Firebase Storage.

---

## 6. Feature: Journal (Home Screen)

### Layout

The home screen (`HomeScreen`) is a single scrollable journal. Structure:
1. **AppBar:** App title + vessel name (italic, shown only if configured). White background, navy primary color.
2. **Year filter pills:** Horizontal scroll row. Newest year is auto-selected. Tap "ALL →" to show all entries.
3. **Stats bento:** Two cards — "Days at Sea" (count of days with GPS track and non-zero distance) and "Distance" (total nm across all displayed tracks).
4. **Timeline list:** Entries grouped by month. Month headers are collapsible (persisted to Firestore). Newest-first. Each entry card shows:
   - Date (uppercase weekday · d. MMM yyyy)
   - Route (from → to, if set)
   - Narrative excerpt (first line of notes or first timeline remark)
   - GPX stats (distance, avg speed, if a track exists)
   - Weather icons (sun/rain/cloud/storm) and wind icon (if wind > 5 kn)
5. **Bottom nav:** Journal (active) | FAB (add) | Tracks | Safety | Settings.

### Add Entry Flow

Tapping the FAB opens a two-option pill menu (slides up from bottom):
- **"New Day":** Opens a date picker. Already-existing dates are disabled. On confirm, creates a `DayEntry` and pushes to `/day/yyyy/mm/dd`.
- **"Add Entry":** Pushes to the most recent day detail with `?addEntry=1` to immediately open the timeline entry dialog.

### Month Collapse State

Month expansion state is a `Map<String, bool>` stored in Hive under `mex_{yyyy-M}` keys. It is synced to `logbooks/{logbookId}/meta/ui`. The newest month is open by default (`defaultOpen: isFirst`). State is synced across devices via `ThemeProvider.attachFirestore`.

---

## 7. Feature: Day Detail

`DayDetailScreen` is the largest file in the codebase (~3500 lines). It displays a full vertical-scroll view of one day's data.

### Sections (top to bottom)

| Section | Widget method | Content |
|---------|--------------|---------|
| Crew list | `_buildCrewList` | Crew chips with skipper role. Add/remove/reorder. |
| Diary / Reflection | `_buildReflection` | Quoted narrative (`entry.notes`). Newsreader italic display. |
| Notes | `_buildFreeText` | Plain `entry.freeText`. Inter font. |
| Photo strip | `_buildPhotoStrip` | Horizontal scroll of thumbnail images. Add/delete photos. |
| Route map | `_buildRouteMap` | Interactive `flutter_map` showing the GPX track with from/to harbor fields. |
| Log section | `_buildLogSection` | Chronological timeline entries. Auto-generated vessel status and crew notes at top. |
| Vessel status | `_buildVesselStatus` | Oil%, Fuel%, Keel position. |

### Timeline Entry Dialog

The `AddTimelineEntryDialog` widget collects:
- Time (HH:mm)
- Course (°)
- Speed (kn)
- Wind (free text, e.g. "SW 15 kn")
- Sea state (free text)
- Weather (free text)
- Gross/Fock sail state (enum: reef 0-3, furled, down)
- Motor on/off
- Keel position (if keel boat)
- Remarks (free text)

### Auto-Snapshot on First Timeline Entry

When `HomeRepository.addTimelineEntry` is called and it is the first real timeline entry for that day:
1. **Crew note:** If the day has crew members, a `TimelineEntry` with `vesselStatusNote = 'crew:Name1 (Skipper) · Name2'` is prepended (same timestamp as the user's entry).
2. **Vessel status notes:**
   - Oil and fuel: one combined note `'Motoröl: X% · Kraftstoff: Y%'` if either is set.
   - Keel: a separate note `'Kiel: Unten'` / `'Kiel: Oben'` if set.

These are only auto-logged if no crew note or status note is already in the timeline. Subsequent entries do not re-log.

### Timeline Display

Crew notes (starting with `'crew:'`) receive special rendering: the sentinel prefix is stripped, and the localised label `crew_label` is prepended. The legacy format `'Besatzung: '` is also handled for documents written before the sentinel was introduced.

### Day Carry-Forward

When `addEntry(date)` is called (creating a new day), the following are carried forward from the most recent past day:
- `crew` (last crew list)
- `participantsList` (legacy string list)
- `oilLevel`, `fuelLevel`, `keelDown` (from the nearest day that has each value, may be different days)

### Menu Actions (top-right `⋮`)

- Change date (moves entry to a new date, also moves the GPX track)
- Import GPX (file picker, `.gpx` files)
- Export GPX (shares the raw GPX file)
- Export PDF (generates and previews a voyage report — see §14)
- Delete GPX (removes track, keeps entry)
- Delete Day (removes entry + track)

---

## 8. Feature: Crew Management

### Two-level model

**Day entry crew** (`DayEntry.crew: List<CrewMember>`) — the crew for a specific day. Carried forward from the previous day. Stored in Firestore inside the day entry document.

**Shared crew roster** (`HomeRepository.roster: List<CrewMember>`) — a permanent list of frequently-sailed-with crew members, stored in `logbooks/{logbookId}/meta/crew_roster`. Synced in real time. Used as a picker source when adding crew to a day.

### `CrewMember` fields

```dart
name: String        // required
bloodType: String?  // e.g. "A+"
allergies: String?
conditions: String? // medical conditions / medications
remarks: String?    // passport number, other notes
id: String?         // roster ID (null on day-entry crew copies)
```

### Reordering (Skipper assignment)

The first crew member in `DayEntry.crew` is designated as Skipper. Crew can be reordered via `ReorderableListView` in the day detail. When the order changes and the timeline already has entries, a new crew note is automatically appended.

### Emergency Manifest connection

`EmergencyManifestScreen` reads crew from `homeRepo.getEntry(today)?.crew ?? homeRepo.lastCrew`. The crew medical information (blood type, allergies, conditions) is displayed in the "Crew Medical Overview" section.

---

## 9. Feature: GPS Tracks Screen

`TracksScreen` shows all imported GPX tracks on an interactive map, with a scrollable list below.

### Map

Uses `flutter_map ^8.0.0` with OpenStreetMap or satellite tile layers. Each day's track is rendered as one or more `Polyline` segments. Tracks are colour-coded using a golden-angle hue palette (index × 137.5°, starting at nautical blue 200°) to maximise perceptual separation between adjacent days.

### Track rendering

For each day, `buildDisplayModel(track.points, settings: filterSettings)` is called to get a `DisplayModel` (see §12). The model's `segments` list drives the polylines:

| Segment kind | Rendering |
|-------------|-----------|
| `moving` | Full-opacity polyline at selected width (5px if selected, 3px otherwise) |
| `stopEntry` / `stopExit` | Dashed-style polyline at 60% width and 40% / 26% opacity |
| `teleportBreak` | No polyline — the visual gap signals a jump |

Stop locations are shown as two concentric `CircleMarker` rings:
- Inner: 50th-percentile radius (CEP50), opacity 22%
- Outer: 95th-percentile radius (r95), opacity 7%

Departure arrows are placed at the start of each track's moving segment using a directional `Container` with `Transform.rotate`. The bearing is calculated as the haversine bearing from the start point to the first cumulative-500m point along the track (or the furthest point for short tracks).

### Date filter presets

| Preset | Range |
|--------|-------|
| 1 Year | -365 days to today |
| 1 Month | -30 days to today |
| 1 Week | -7 days to today |
| Custom | User-selected `DateTimeRange` via `showDateRangePicker` |

### Day list (bottom panel)

A scrollable list of displayed tracks. Tapping a row:
1. Sets `_selectedIndex` (highlights that track on the map)
2. Calls `_focusTrack` to fit the map camera to that track's bounds

Each row shows the date, from/to (if in the logbook entry), distance, average speed, and a coloured leading indicator matching the track colour.

---

## 10. Feature: Emergency Module

Three screens, accessed via the Safety tab (anchor icon in bottom nav).

### `EmergencyManifestScreen` (`/emergency`)

The landing safety screen. Sections:

**Quick Actions** — two cards:
- "Radio Protocol (MAYDAY)" → `/emergency/mayday`
- "Distress Signal Guide" → `/emergency/distress`

**Emergency Contacts** — stored in `EmergencyRepository`. Each contact has name, role, phone. Tapping the call button launches `tel:` URI. Edit mode (pencil icon in AppBar) enables add/edit/delete. Synced to `logbooks/{logbookId}/meta/contacts`.

**Vessel Safety Info** — MMSI, call sign, life raft location, EPIRB location, fire suppression. In edit mode, text fields write to `ThemeProvider` setters which push to `logbooks/{logbookId}/meta/settings`.

**Coast Guard Frequencies** — up to 4 VHF entries (label + description). First entry is marked as urgent (red border). Edit mode allows add/edit/delete. Also synced via `ThemeProvider` VHF getters/setters.

**Crew Medical Overview** — read from `homeRepo.getEntry(today)?.crew` or `homeRepo.lastCrew`. Shows blood type (red badge), allergies, medical conditions. Not editable here — crew is maintained in day entries.

### `MaydayScreen` (`/emergency/mayday`)

A step-by-step MAYDAY radio protocol checklist with a pulsing animation on urgent steps. Steps:
1. DSC Distress Alert (pulsing red)
2. "MAYDAY, MAYDAY, MAYDAY" (pulsing red)
3. Vessel identification (pre-fills from `ThemeProvider.vesselName`, `vesselCallSign`, `vesselMmsi`)
4. Position — acquires live GPS using `geolocator`, formatted as Degrees-Decimal-Minutes (DDM): `N 47° 30.456'  E 008° 18.123'`
5. Nature of distress — interactive chips: SINKING/FLOODING, FIRE, ABANDONING SHIP
6. Crew count — from today's crew or `lastCrew`
7. "OVER" (navy card)

Tips section covers calm communication, slow speech, and listening intervals.

### `EmergencyScreen` (`/emergency/distress`)

A reference guide for International Maritime Distress Signals:
- Visual Signals: Pyrotechnic (with asset image), Hand Signals (asset image), Flag NC
- Sound Signals: Gun/Explosive, Foghorn
- Electronic Signals: EPIRB/PLB, SART
- A "Radio Protocol (MAYDAY)" card linking to `MaydayScreen`

> **Note:** This screen is hardcoded in English and has a non-functional `account_circle` action button. See assessment §5.1.

---

## 11. Feature: Settings

`SettingsScreen` is a long scrollable settings page.

### Sections

**Vessel Information** — vessel name, MMSI, call sign. Text fields writing to `ThemeProvider` which syncs to `logbooks/{logbookId}/meta/settings`.

**Logbooks** — shows a list of all logbooks the user belongs to. Each row shows logbook name, role (owner/guest), and a QR code or share code. Tapping a logbook switches the active logbook (calls `_reinitFirestore`). Create logbook via bottom sheet. Join logbook via QR scan or manual code entry.

**Crew Roster** — launches `CrewRosterScreen` to manage the shared roster.

**App Settings** — language toggle (DE/EN), theme mode (System/Light/Dark), logbook title (shown in AppBar on home screen), weather URL (opens in browser from day detail).

**Track Filter Settings** — expandable section with sliders and toggles for the GPS filter parameters (see §12.2).

**Sync** — "Force Sync" button to trigger `HomeRepository.forceSync()`.

**Account** — sign out (with offline warning if device is offline), delete account (with confirmation and offline warning).

### Logbook Switching

When the user taps a different logbook:
1. `EmergencyRepository.clearLocalData()` — wipes local emergency contacts
2. `ThemeProvider.clearVesselSettings()` — resets vessel/VHF settings to defaults and cancels Firestore streams
3. `ThemeProvider.resetInitialSync()` — marks next attach as initial sync
4. `FirestoreService(logbookId:)` and `StorageService(logbookId:)` are constructed with the new ID
5. `HomeRepository.reattachAndSync(...)` — wipes all Hive data, pulls everything from the new logbook
6. `ThemeProvider.attachFirestore(...)` — loads vessel settings from new logbook
7. `EmergencyRepository.attachFirestore(...)` — loads contacts
8. `logbookIdNotifier.value = logbookId`

### Join via Share Code

1. User enters or scans an 8-char code (alphanumeric, uppercase, hyphens stripped)
2. `LogbookService.findByShareCode(code)` → looks up `shareCodes/{code}` → returns `logbookId`
3. Membership check: `isMember(logbookId, uid)` — if already a member, show snackbar
4. Confirmation dialog shows the logbook name
5. `LogbookService.joinLogbook(logbookId, uid)` — batch write: adds `members/{uid}` with `role: 'guest'`, updates `users/{uid}` with `activeLogbookId` and `logbooks[]`
6. Switch to new logbook via `_reinitFirestore`

---

## 12. GPS Track Filtering Pipeline

The pipeline is implemented in `trim_track.dart` (993 lines). It transforms raw GPS `TrackPoint` data into a `DisplayModel` suitable for map rendering and statistics.

### 12.1 Data Structures

```dart
class TrackPoint {
  final double lat, lon, speed;  // speed in m/s
  final DateTime time;
}

enum PointFlags {
  stationary,      // point is classified as stationary
  coldStart,       // point is in the cold-start settling period
  gapAhead,        // gap > 5 minutes to the next point
}

enum SegmentKind { moving, stopEntry, stopExit, teleportBreak }

class TrackSegment {
  final List<TrackPoint> points;
  final SegmentKind kind;
}

class StopMarker {
  final double lat, lon;
  final double cep50M;   // 50th-percentile circular error probable (metres)
  final double r95M;     // 95th-percentile radius
  final DateTime? arrival, departure;
}

class DisplayModel {
  final List<TrackSegment> segments;
  final List<StopMarker> stops;
  final TrackPoint? firstMovingPoint;
  final List<TrackPoint> rawMovingPoints;
  // helpers:
  List<TrackPoint> movingPoints() → flattened points from moving segments
}
```

### 12.2 Filter Settings

`FilterSettings` / `ThemeProvider.filterSettings`:

| Parameter | Default | Meaning |
|-----------|---------|---------|
| `stationaryMode` | `speed` | Algorithm for stop detection: `speed` or `spread` |
| `speedThresholdKn` | 0.5 kn | Points below this are stationary (speed mode) |
| `spreadThresholdM` | 6 m | Cluster radius for stationary detection (spread mode) |
| `window` | 5 | Median filter window for speed smoothing |
| `smoothWindow` | 3 | Point smoothing window |
| `minStopMinutes` | 5.0 min | Minimum duration for a stop to be rendered as anchor circle |
| `maxStopSpreadM` | 30 m | Maximum GPS spread during a stop (validates stop quality) |
| `detectColdStart` | true | Enable cold-start spike suppression |
| `coldStartSettleFactor` | 3.0 | Multiplier for initial-fix uncertainty |
| `makingWayThresholdKn` | 1.0 kn | Speed threshold for "making way" classification |
| `topSpeedPercentile` | 0.99 | Percentile cap for plausibility (removes outlier spikes) |

### 12.3 Six-Pass Algorithm

**Pass 1: Annotate with flags**

For each point, flags are assigned based on a sliding window median speed:
- Compute 5-point median speed (knots)
- If median speed < `speedThresholdKn` → `stationary`
- If speed exceeds `topSpeedPercentile` speed → treated as spike
- Compare point-to-point Haversine distance vs. max plausible distance at `makingWayThresholdKn`

**Pass 2: Spike detection**

Identifies GPS spikes: isolated points where the speed from the prior point to the spike and from the spike to the next point both exceed a plausibility threshold. These are flagged for exclusion from the display model.

**Pass 3: Re-annotate with gap awareness**

Same as Pass 1 but gaps (time difference > 5 minutes between consecutive points) are tracked. `gapAhead` flag is set. This ensures stationary classification near a gap isn't confused with a moving segment transition.

**Pass 4: Stationary segment detection**

Groups consecutive stationary points into segments. For each candidate stop segment:
1. Must have duration ≥ `minStopMinutes`
2. GPS spread (95th percentile of distances from median centroid) must be ≤ `maxStopSpreadM`

Validated stops produce `StopMarker` objects with:
- **Centroid**: median lat/lon of all stationary points
- **CEP50**: radius containing 50% of points (circle of probable position)
- **r95**: radius containing 95% of points
- **Arrival / departure** timestamps

**Pass 5: Cold-start flagging**

The first cluster of stationary or slow points at the beginning of the track (before sustained movement) is identified as the "cold start" — the period when the GPS receiver is acquiring a stable fix. These points are flagged `coldStart` and excluded from the display model to prevent the track from appearing to start far from the actual departure point.

The settling period ends when the first sustained `making_way` sequence is detected. The `coldStartSettleFactor` multiplies the expected fix accuracy to define the settling radius.

**Pass 6: Median smoothing**

Moving points (not flagged as stationary or cold-start) are smoothed using a `smoothWindow`-point median filter on both lat and lon independently. This removes GPS jitter without distorting the actual track shape.

### 12.4 Output Segments

After the six passes, the track is divided into segments:

- **`moving`**: non-stationary, non-cold-start points between gap or stop boundaries
- **`stopEntry`**: final few moving points approaching a validated stop (visual fade-in to anchor)
- **`stopExit`**: initial few moving points departing a validated stop (visual fade-out from anchor)
- **`teleportBreak`**: gap ≥ 5 minutes — no segment, just a missing polyline

### 12.5 `trimStationaryEnds` (simplified)

Used in the tracks screen for fitting map bounds and computing stats. Removes stationary points from the start and end of the track without full segmentation. Faster but less precise than `buildDisplayModel`.

### 12.6 `computeDailyStats`

Given a `List<TrackPoint>` and `FilterSettings`, computes:
- `distanceNm` — sum of Haversine distances between consecutive moving points (nm)
- `totalDuration` — time from first to last point
- `movingDuration` — time excluding stationary segments
- `avgSpeed` — distance / moving duration (kn)
- `avgOverGroundKn` — distance / total duration (kn)
- `maxSpeedKn` — highest smoothed speed across moving points
- `nStops` — count of validated stop markers

---

## 13. Map Display

### Tile Configuration

`MapConfig.tileUrl` (in `core/constants/map_config.dart`) provides the OpenStreetMap tile URL. The `_satelliteView` toggle in both `TracksScreen` and `DayDetailScreen` switches to a different tile provider.

### Day Detail Map (`_buildRouteMap`)

The day detail map shows the single day's track with:
- Track polylines (moving: full color; stop entry/exit: dashed/faded)
- Anchor circles at stop locations
- Departure arrow at track start
- Timeline correlations: tapping a timeline entry drops a temporary marker at the GPS position closest in time to that entry (using `track_correlation.dart`)
- "Dropped marker" with a dismiss timer (3 seconds, dismisses on next tap)
- From/To harbor input fields at top (inline editing)

`track_correlation.dart` uses a simple O(n) linear scan to find the `TrackPoint` whose timestamp is closest to each `TimelineEntry.time`.

### Interactions

- Double-tap: zoom in
- Long-press: coordinates are not currently captured (could be future improvement)
- Pinch: zoom
- Satellite toggle in top-right of map panel

---

## 14. PDF Export

`pdf_exporter.dart` uses the `pdf ^3.11.1` package to generate an A4 PDF document.

### Page Layout

```
┌──────────────────────────────────────────┐
│ VESSEL NAME (large bold)                  │
│ ─────────────────────────────────────────│
│ Route title    "Passage nach Porto"       │
│ ─────────────────────────────────────────│
│ TAGEBUCH                                  │
│ (narrative text, full width)              │
│ ─────────────────────────────────────────│
│ Photos (if any)                           │
│ ─────────────────────────────────────────│
│ NOTIZEN (free text)                       │
│ ─────────────────────────────────────────│
│ Track map (8/13)    │ Stats (5/13)        │
│ ─────────────────────────────────────────│
│ Timeline (8/13)     │ Crew list (5/13)   │
└──────────────────────────────────────────┘
```

### Font Handling

Uses Google Fonts via `PdfGoogleFonts` (downloaded and cached by the `printing` package):
- `NotoSansRegular`, `NotoSansBold`, `NotoSansItalic` for body text
- `NotoEmojiRegular` for emoji codepoints

Text runs are split into emoji/non-emoji chunks and rendered with the appropriate font using `_splitRuns` + `_richText`.

### Track Map

If a GPX track is present, `_renderTrackImage` renders the track onto an in-memory canvas using `dart:ui`. It:
1. Mercator-projects all track points to canvas coordinates
2. Draws a stroke path for the full track
3. Returns a PNG-encoded `Uint8List` embedded in the PDF

### Stats Block

Shows Distance, Average Speed (avg over ground), Max Speed, Moving Time, and Stop Count (if > 0), rendered as a 2-column grid of stat cards.

### Timeline Block

Shows each `TimelineEntry` with time, course/speed/wind if present, sail/motor state, and remarks. Auto-generated crew/vessel notes are rendered with a different style.

### Crew Block

Each crew member is listed with name, blood type, allergies, and conditions (if set).

### Export Flow

From `DayDetailScreen`:
1. `buildVoyagePdf(entry, stats, vesselName, trackPoints, photoBytes)` is awaited
2. `Printing.layoutPdf` is called to open the system print/share dialog

---

## 15. Theme System

### Colour Palette

**Light theme** (`light_theme.dart`):
| Role | Token | Hex | Name |
|------|-------|-----|------|
| Primary | `primary` | `#002444` | Deep Navy |
| Primary container | `primaryContainer` | `#1A3A5C` | |
| Secondary | `secondary` | `#725C10` | |
| Secondary container | `secondaryContainer` | `#FFE088` | Captain's Gold |
| Tertiary | `tertiary` | `#142435` | Dark Navy |
| Tertiary fixed dim | `tertiaryFixedDim` | `#B7C8DE` | Seafoam |
| Surface | `surface` | `#FAF9FA` | |
| Error | `error` | `#BA1A1A` | |

**Dark theme** (`dark_theme.dart`):
| Role | Token | Hex | Name |
|------|-------|-----|------|
| Primary | `primary` | `#7DB3F0` | Light Blue |
| Secondary | `secondary` | `#4CC9D4` | Cyan |
| Tertiary | `tertiary` | `#B7C8DE` | Seafoam |
| Surface | `surface` | `#0D1E33` | Very Dark Navy |

### Typography

Both themes use a dual-font setup via `google_fonts`:
- **Display / Headline:** `Newsreader` (serif) — used for app title, day names, section headings, narrative text
- **Body / Labels:** `Inter` (sans-serif) — used for data, metadata, captions, uppercase labels

Uppercase label style: `Inter`, 10-11px, `FontWeight.w700`, `letterSpacing: 1.5`.

### AppBar Theme

The theme-level `appBarTheme` specifies a Navy background, but all screens override this to use `cs.surface` background. The effective style is surface background / primary foreground / Newsreader title.

### Component Themes

- **Cards:** Rounded corners (12px), elevation 0 (light) / 2 (dark)
- **Chips:** Stadium border (pill shape), selected colour = primary
- **FAB:** `primaryContainer` bg, rounded rect (16px)
- **DatePicker:** Custom themed to match the maritime palette
- **Dialog:** Rounded 16px corners, no surface tint

---

## 16. Localisation

The app supports **German** (default) and **English**. Locale is stored in `ThemeProvider._locale` and persisted to Hive.

### ARB Files

Source of truth: `lib/l10n/app_de.arb` and `lib/l10n/app_en.arb`.  
Generated output: `lib/l10n/app_localizations.dart` and subdirectory (never edit directly — wiped by `flutter gen-l10n`).

Access via `context.l10n` (extension in `l10n_extension.dart`).

### Date Formatting

`intl` package with `initializeDateFormatting('de_CH')` and `initializeDateFormatting('en')` called at startup. `ThemeProvider.localeString` returns `'de_CH'` or `'en'` for `DateFormat` calls.

### Known Localisation Gaps

- Emergency feature (all three screens) uses hardcoded English
- Several dialogs in `EmergencyManifestScreen` mix German/English strings not from ARB files
- `MaydayScreen.appBar.title` is hardcoded in English

---

## 17. Build & Deployment

### Versions

- Flutter SDK: `^3.11.0`
- Dart SDK: `^3.11.0`
- App version: `1.0.21+21`

### iOS

- Bundle: auto-managed signing with development team `QY8ZXY5JV5`
- iOS deployment target: iOS 13+ (inferred from Firebase requirements)
- Plugins requiring CocoaPods (not yet Swift Package Manager): `sign_in_with_apple`, `printing`, `flutter_image_compress`
- **Issue:** iOS 27 beta 2 blocks Flutter debug VM service WebSocket. Use `flutter run -d {device_id}` for development; do not use Xcode debug. See §18.

### Android

- `adaptive_icon_background: "#005AA0"`
- `adaptive_icon_foreground: assets/icon/app_icon_foreground.png`
- Package name: `logbook`

### macOS

- App icon: same source as iOS
- Plugins requiring CocoaPods: `sign_in_with_apple`, `printing`, `flutter_image_compress_macos`

### Firebase

- Project: `logbook-auth-dev`
- Deploy rules: `firebase deploy --only firestore:rules --project logbook-auth-dev`
- Deploy storage rules: `firebase deploy --only storage --project logbook-auth-dev`

---

## 18. Known Platform Issues

### iOS 27 Beta 2

Flutter debug builds (JIT) cannot connect their VM service WebSocket on iOS 27 beta 2. The Xcode-driven LLDB hook (`flutter_lldb_helper.py`) is insufficient on the new OS version — the process may appear to launch but Flutter's debug channel fails with "Connection reset by peer" after ~60 seconds.

**Working workaround:** `flutter run -d {device_id}` in debug mode (not from Xcode).  
**Not working:** `flutter run --release` (fails at install on iOS 27 beta).  
**Root cause:** Flutter JIT on iOS 27 beta — no upstream fix as of 2026-06-25.

Memory: see `project_ios26_debug_issue.md` in the memory system.

---

## 19. Existing Documentation Scripts

Two Python documentation scripts exist in `docs/`:

### `generate_doc.py`

Generates a Word/HTML document from source code (likely uses `python-docx`). Scans the Dart source tree and generates structured documentation. Run from `docs/` directory.

### `generate_wiki.py`

Generates a wiki-format Markdown document. Scans the Dart source tree and outputs structured Markdown pages. Run from `docs/` directory.

Both scripts were created as part of earlier documentation efforts. The output format and scope differ from this hand-written document. For architecture decisions and behavioral documentation (offline sync logic, filter algorithm details), this document is authoritative. For API-surface listings and class references, the generation scripts may be more up to date.

---

*End of documentation. Last updated: 2026-06-25.*
