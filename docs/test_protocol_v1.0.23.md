# Device Test Protocol — v1.0.23

**Branch:** `claude/version-tag-status-94c3n6`  
**Tag:** `v1.0.23`  
**Date:** 2026-06-25

---

## About the code changes in this version

### What was refactored for testability — and why no revert is needed

The last commit (`51871fc`) extracted three functions from widget classes into a
shared utility file (`lib/features/home/utils/sail_state_utils.dart`):

| Function | Was in | Now in |
|---|---|---|
| `normalizeSailState` | private method `_AddTimelineEntryDialogState` | `sail_state_utils.dart` (top-level) |
| `sailStateAbbr` | local closure inside `_buildTimeline` in `pdf_exporter.dart` | `sail_state_utils.dart` (top-level) |
| `parseVesselStatus` | inline logic inside `_DayDetailScreenState._vesselStatusDisplay` | `sail_state_utils.dart` (top-level) |

**The logic is identical — only the location changed.** The app behaviour is
unchanged. There is nothing to revert. The test file
(`test/sail_state_utils_test.dart`) is never compiled into the production app;
it only runs when you execute `flutter test`.

The refactoring is a permanent improvement: the shared utility file is the
single source of truth for sentinel parsing, so future changes only need to
happen in one place.

---

## Test areas and what to verify

### 1. Launch and data integrity

**Goal:** Confirm existing local data loads without crash after the Hive adapter
change (field 13 / `participantsList` removed from the adapter).

Steps:
- Cold-launch the app on a device that already has journal entries stored locally
- Confirm the journal list appears and all entries are visible
- Open several existing day entries and scroll through them
- Open an entry that has timeline rows saved before this session

Pass criteria:
- No crash on launch
- All existing entries display correctly
- No missing or garbled data in timeline rows

---

### 2. Navigation bar

**Goal:** Confirm all four tab labels are localised and the FAB is accessible.

Steps:
- Observe the bottom nav bar labels: should read **Journal / Tracks / Settings /
  Safety** in English, or **Journal / Tracks / Einstellungen / Sicherheit** in
  German
- Confirm the **Offline** indicator appears when you enable airplane mode (small
  text below the nav bar)
- Long-press the centre `+` FAB
- If using iOS VoiceOver or Android TalkBack, activate the FAB and confirm the
  accessibility label announces "Add"

Pass criteria:
- All four labels shown in the correct locale (no hardcoded German in English
  locale or vice versa)
- Offline indicator appears in airplane mode and disappears when connectivity
  is restored
- Tooltip "Add" appears on long-press of the FAB

---

### 3. Timeline entry dialog — sail state chips

**Goal:** Confirm sail state options display in the correct locale and save as
locale-neutral sentinels.

Steps:
- Open the Add / Edit timeline entry dialog
- Scroll to the **Sails** section
- Confirm the mainsail chips show: **Full sail / 1st reef / 2nd reef /
  Lowered** (English) or **Voll gesetzt / 1. Reff / 2. Reff / Niedergeholt**
  (German)
- Confirm the foresail chips show: **Full sail / 1st reef / 2nd reef / Furled**
  (English) or **Voll gesetzt / 1. Reff / 2. Reff / Eingerollt** (German)
- Select "2nd reef" on mainsail and save the entry
- Reopen the entry in the dialog and confirm "2nd reef" is still selected

Pass criteria:
- Chips display in the correct locale
- Selection persists correctly (sentinel `sail:reef2` is stored, not German text)

---

### 4. Timeline entry dialog — units

**Goal:** Confirm speed and wind units are correct.

Steps:
- Open the Add / Edit timeline entry dialog
- Confirm the **Speed** field shows the unit **kn** (not `kts`)
- Confirm the **Wind strength** field shows the unit **kn** (not `KN`)

Pass criteria:
- Both unit labels read `kn`

---

### 5. Keel state chips

**Goal:** Confirm keel chips use localised labels.

Steps:
- Open the Add / Edit timeline entry dialog
- Scroll to the keel section
- Confirm chips show **Down / Up** (English) or **Unten / Oben** (German)
- Select one, save, reopen — confirm selection persists

Pass criteria:
- Labels are in the correct locale
- Selection persists correctly

---

### 6. Day detail — vessel status display

**Goal:** Confirm the vessel status sentinel is parsed and displayed correctly,
not shown as raw text.

Steps:
- Open a day entry that has a vessel status note (oil/fuel levels or keel
  stored via the gauge edit)
- Locate the vessel status row in the timeline
- Confirm it reads e.g. **Oil: 75% · Fuel: 60%** or **Keel: Down** — not the
  raw sentinel string `vs:oil=75,fuel=60` or `vs:keel=down`

Pass criteria:
- No raw sentinel strings visible anywhere in the UI

---

### 7. Day detail — legacy sail state display

**Goal:** Confirm that old entries with German sail state text still display
correctly (legacy fallback path).

Steps:
- If you have entries saved before this update (with values like "Voll gesetzt",
  "1. Reff"), open one of them
- Confirm the timeline row displays the sail state correctly (it will show the
  German text verbatim — that is correct for legacy entries)
- Confirm no crash and no raw sentinel text visible

Pass criteria:
- Legacy German values display as-is without crash

---

### 8. PDF export

**Goal:** Confirm all section headers and labels appear in the correct locale.

Steps:
- Open a day entry with timeline entries, crew, and at least one harbour name
- Tap the export / share button and generate a PDF
- Verify the following labels appear in the correct locale:

English expected:
- Voyage header: `VOYAGE LOG` / `NOTES`
- Stats block: `DATE`, `DISTANCE`, `AVG SPEED`, `MAX`, `UNDERWAY`, `STOPS`,
  `STATISTICS`
- Crew block: `CREW`, `SKIPPER`
- Timeline header: `LOG ENTRIES`, columns `Time`, `Hdg`, `Wind`, `Sea`,
  `Engine`, `Sails`, `Remarks`
- Motor column: `ON` / `OFF`
- Track map: `COURSE & TRACK`
- Footer: `Page 1 of N`
- Route title: `Passage to [harbour]`

German expected values (de locale):
- `TAGEBUCH` / `NOTIZEN`, `DATUM`, `DISTANZ`, `Ø FAHRT`, `FAHRZEIT`,
  `STATISTIK`, `CREW`, `SKIPPER`, `BESATZUNG`, `LOGBUCH-EINTRÄGE`,
  `Zeit`, `Kurs`, `Wind`, `See`, `Motor`, `Segel`, `Bemerkungen`,
  `AN` / `AUS`, `KURS & TRACK`, `Seite 1 von N`, `Passage nach [Hafen]`

Pass criteria:
- All labels in the correct locale
- No hardcoded German visible in the English locale PDF

---

### 9. Account deletion — connectivity check (optional, needs test account)

**Goal:** Confirm the offline guard works and Firestore failure does not delete
the Auth account.

Steps (offline test):
- Enable airplane mode
- Go to Settings → Account → Delete account
- Confirm the deletion is blocked with a network error message
- Restore connectivity

Steps (happy path):
- Sign in with a disposable test account
- Go to Settings → Account → Delete account
- Confirm the confirmation dialog appears, then the deletion proceeds
- Confirm you are redirected to the login screen

Pass criteria:
- Offline deletion attempt is blocked with an informative message
- Online deletion completes and logs the user out

---

### 10. Run unit tests (on Mac, not device)

Execute before or after device testing to confirm the sentinel logic.

**Run all tests in the project:**

```
flutter test
```

**Run only the sentinel/PDF tests:**

```
flutter test test/sail_state_utils_test.dart
```

**Run with full per-test output:**

```
flutter test --reporter expanded
```

Expected output: **21 tests passed** (1 placeholder + 20 sentinel/PDF tests)

#### What `flutter test` does vs `flutter build` / `flutter run`

- `flutter test` — compiles only the Dart code and runs it on your Mac in a
  headless Dart VM. No simulator, no device, no Firebase, no network needed.
  Takes about 2–5 seconds for this suite.
- `flutter build` — compiles the full app for a target platform (Android/iOS).
  Takes minutes.
- `flutter run` — builds and deploys to a connected device or simulator.

The tests never touch Firebase, Hive, or the network. They are pure Dart
function calls with known inputs checked against expected outputs.

#### When to run them

Run `flutter test` before every commit that touches sentinel or PDF parsing
logic. If you later add a new sail state or a new vessel-status key, add a test
case alongside the code change — `flutter test` tells you immediately whether
the logic is correct, before touching a device.

---

## Summary checklist

| # | Area | Pass |
|---|---|---|
| 1 | Launch — no crash, existing data visible | ☐ |
| 2 | NavBar labels localised, FAB tooltip works | ☐ |
| 3 | Sail chips show correct locale, persist as sentinels | ☐ |
| 4 | Speed unit `kn`, wind unit `kn` | ☐ |
| 5 | Keel chips localised and persist | ☐ |
| 6 | Vessel status shows parsed text, not raw sentinel | ☐ |
| 7 | Legacy German sail state entries display without crash | ☐ |
| 8 | PDF labels in correct locale | ☐ |
| 9 | Account deletion blocked offline (optional) | ☐ |
| 10 | `flutter test` — 20/20 passing | ☐ |
