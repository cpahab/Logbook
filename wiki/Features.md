# Feature Walkthroughs

A behavior-level tour of each screen. For file locations see [Code Map](Code-Map); for
the underlying schema see [Data Model](Data-Model). The GPS track-cleaning algorithm
itself has its own detailed writeup: `docs/GPS-Track-Filtering-Pipeline.docx`.

---

## Journal (Home Screen)

A single scrollable journal: year filter pills (newest year auto-selected, "All" pill to
show everything), a stats bento (days logged + total distance), then a month-grouped,
newest-first timeline of day entries. Each entry card shows the date, route (from → to),
a narrative excerpt, GPX stats if a track exists, and weather/wind icons. Month headers
are collapsible; the expansion state syncs across devices via `meta/ui`.

The "days logged" stat counts every day entry with a positive distance (either from a
GPX track or a manually entered `distanceNm`), not just days that happen to have an
imported GPS track — a day logged without GPS still counts.

The FAB opens a two-option menu: **New Day** (date picker, disables already-used dates)
or **Add Entry** (jumps to the most recent day and opens the timeline dialog directly).

## Day Detail

The largest screen — a full vertical view of one day: crew list, diary/notes, photo
strip, an interactive route map, the chronological timeline log, and vessel status
(oil/fuel/keel).

**Auto-snapshot on first timeline entry:** the first real timeline entry of a day
auto-prepends a crew snapshot (if crew is set) and a vessel-status snapshot (oil/fuel/keel,
whichever are set) at the same timestamp — a "log it once" convenience. Subsequent entries
don't re-log unless the crew or status actually changes.

**Day carry-forward:** creating a new day carries forward the crew list and the nearest
past day's oil/fuel/keel values (each independently — they don't have to come from the
same day).

**Menu actions:** change date (moves the GPX track too), import/export/delete GPX, export
PDF, delete day.

## Crew Management

Two levels: **day-entry crew** (`DayEntry.crew`, carried forward day to day, the working
set for that voyage) and the **shared roster** (`HomeRepository.roster`, a permanent
address book of frequent crew, synced via `meta/crew_roster`). The roster is the picker
source when adding someone to a day. The first person in a day's crew list is the
Skipper; reordering is supported and appends a new crew-change timeline entry.

The Emergency Manifest reads crew (with medical info) from today's entry, falling back to
the last day that had crew.

## GPS Tracks Screen

Shows every imported GPX track on one map, colour-coded per day (golden-angle hue
palette for maximum visual separation between adjacent days), with a date-range filter
(1 year / 1 month / 1 week / custom) and a scrollable list of tracks below. Selecting a
track in the list highlights and focuses it on the map. The date-range filter and
satellite-view toggle persist for the app session (surviving navigation to other tabs)
but reset on a full app restart — see the comment on the `static` fields in
`tracks_screen.dart`.

Each track is rendered through `buildDisplayModel` (see the filtering pipeline doc):
moving segments at full opacity, stop entry/exit connectors faded, and a gap where the
filter detected a GPS teleport. Stops are drawn as two concentric rings (50th/95th
percentile GPS spread).

## Emergency Module

Three screens under the Safety tab:

- **Emergency Manifest** — quick links to the two screens below, editable emergency
  contacts (tap-to-call), vessel safety info (MMSI, call sign, life raft, EPIRB, fire
  suppression — synced via `meta/settings`), VHF channel reference, and a read-only crew
  medical overview.
- **MAYDAY** — a step-by-step radio protocol checklist. Vessel ID pre-fills from settings;
  position uses live GPS in Degrees-Decimal-Minutes format; nature-of-distress and crew
  count are interactive. The radio-script text itself (`"MAYDAY, MAYDAY, MAYDAY"`, step
  labels, etc.) is intentionally always English, per SOLAS/IMO convention for
  international distress calls — informational content elsewhere in the manifest is
  localized normally.
- **Distress Signal Guide** — reference for visual/sound/electronic distress signals.

## Settings

Vessel information, logbook management (list/create/join-by-code-or-QR/rename/delete),
crew roster entry point, app settings (language, theme, title, weather URL), track-filter
tuning (see [Data Model](Data-Model) — cloud-synced per logbook), a manual "Force Sync"
button, and account actions (sign out, delete account — both guarded against being
attempted while offline).

Switching the active logbook wipes local Hive state and re-attaches everything
(`HomeRepository.reattachAndSync`, `ThemeProvider.clearVesselSettings` +
`attachFirestore`, `EmergencyRepository.clearLocalData` + `attachFirestore`) — the switch
downloads the new logbook's data *before* touching local state, so a failed download
leaves the previous logbook's data intact.

## PDF Export

Generates an A4 voyage report (`pdf_exporter.dart`): vessel name, route title, narrative,
photos, notes, a rendered track-map thumbnail, a stats block, the full timeline, and a
crew list. All section labels and the date format go through a `PdfStrings` bundle built
from `l10n` at the call site, so the PDF matches the app's active language rather than
being hardcoded to one locale.
