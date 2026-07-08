# Logbook App — Wiki

**Logbook** is an offline-first, cross-platform sailing logbook built with Flutter. It runs on
iOS, macOS, and Android, and lets a boat's crew keep a shared daily journal, GPS track record,
crew roster, and emergency manifest — with a full MAYDAY radio-protocol guide built in — all
synced across every crew member's device.

---

## What it does

- **Daily journal.** One entry per day: crew aboard, weather, course, sail/motor state,
  free-text notes, and a "diary" reflection line. Each day's timeline can hold multiple
  logged entries (departure, arrival, in-transit updates), each auto-correlated against the
  GPS track for that day.
- **GPS tracking.** Import/export GPX files, view the route on a map (normal + satellite),
  and see computed stats — distance, duration, average speed — per day and aggregated across
  a filterable date range (1 year / 1 month / 1 week / custom).
- **Timeline amendments.** Editing a *past* day's log entry doesn't silently overwrite it —
  it snapshots the prior state as a `TimelineAmendment` with an optional reason, viewable as
  an audit trail on that entry.
- **Emergency manifest.** Crew medical info (blood type, allergies, conditions, personal
  EPIRB), vessel safety equipment (life raft, EPIRB, fire extinguisher), and VHF channel
  presets — editable inline, no separate settings detour.
- **MAYDAY / Radio Protocol.** A live, step-by-step SOLAS/IMO-standard distress-call guide:
  DSC alert, MAYDAY signal, vessel identification, live GPS position, nature of distress,
  crew count, sign-off. Deliberately the one screen in the app allowed to be visually "loud"
  (solid red app bar, error-container icon chips) — see [design.md](design.md) §7.11.
- **Multi-device sync.** Firebase Auth (email/password, Google, Apple) gates access; each
  logbook is shared via an 8-character code or QR code between crew devices, backed by
  Firestore + Cloud Storage.

For a screen-by-screen behavioral walkthrough, see [Features](Features).

---

## Architecture at a glance

| Layer | Technology | Notes |
|-------|-----------|-------|
| Local storage | Hive (typed adapters) | `DayEntry`, `TimelineEntry`, `TimelineAmendment`, `CrewMember`, `DailyTrack`, `TrackPoint`, `EmergencyContact` |
| Cloud sync | Firebase Firestore + Storage | Auth-gated, keyed by `logbookId`; membership enforced by security rules |
| Auth | `firebase_auth` + `google_sign_in` + `sign_in_with_apple` | All three providers wired up and working |
| State management | `provider` (`ChangeNotifier`) | `HomeRepository`, `ThemeProvider`, `EmergencyRepository`, `AuthService` |
| Navigation | `go_router` | Named routes, single auth-gating `redirect` |
| Maps | `flutter_map` | Currently on free public OSM/Esri tile servers — see the note below |
| Localization | `flutter_localizations` + `intl`, ARB-based | German (default) + English; MAYDAY script deliberately stays English (SOLAS/IMO convention) |
| Theming | Material 3 `ColorScheme`/`TextTheme`, DM Sans | "Horizon Minimalist" design system — see [design.md](design.md) |

Full file-by-file breakdown: [Code Map](Code-Map). Firestore/Hive schema: [Data Model](Data-Model).

**⚠ Map tiles are temporarily on free public OSM/Esri servers, not MapTiler.** An earlier
tile-URL fix (`tiles/openstreetmap` 404, fixed in `f26d787`) burned through the MapTiler
free-tier quota, which resets 2026-07-21. `lib/core/constants/map_config.dart` currently has
the MapTiler config commented out and points at public OSM/Esri demo tiles as a stopgap.
Those demo servers aren't licensed for sustained use by a distributed app — this must be
switched back to MapTiler (uncomment the block, delete the testing block) once the quota
resets, and definitely **before any App Store submission**. See [Roadmap](Roadmap).

---

## Design system

The app follows a documented design system, "Horizon Minimalist": a flat, left-aligned,
DM-Sans-everywhere aesthetic with a single sparingly-used gold accent, and a red accent
reserved entirely for the MAYDAY screen. Every color and text style used anywhere in the app
is expected to map to a named `ColorScheme`/`TextTheme` role — no hardcoded hex values or
one-off font sizes in screen code (a full app-wide sweep enforcing this ran across ~16
files in July 2026).

**[design.md](design.md)** is the living reference: full light/dark color tables with the
reasoning behind each choice (including why the dark theme's navy palette was rebuilt as one
consistent ~216°-hue family instead of mixing saturated navy with near-neutral greys),
custom `TextTheme` roles (`dialogTitle`, `fieldValueCompact`/`fieldValueProse`, `microLabel`,
`chipLabel`, `unitLabel`), component conventions, and a full screen inventory. Update it
whenever a design decision changes — it's meant to stay current, not be a one-time snapshot.

---

## Sync model, and a bug worth knowing about

Each day's Firestore document used to be replaced wholesale (`.set()`) on every save, and the
"is this remote update newer than my local edit?" check compared against a *global*
last-full-sync timestamp rather than that specific document's own `updatedAt`. With two
devices editing the same day around the same time, one device could go blind to the other's
newer changes and then silently clobber them on its next save — even a save touching an
unrelated field. This was root-caused and fixed: saves now merge only the fields that
actually changed, and the staleness check compares against each entry's own `updatedAt`
instead of a global sync timestamp. See [Architectural Decisions](Architectural-Decisions)
for the full before/after and remaining edge cases.

---

## Contents

| Page | Summary |
|------|---------|
| [Current State](Current-State) | Tech stack, maturity notes, known platform issues |
| [Code Map](Code-Map) | What each source file does; the app's data flow/sync model |
| [Data Model](Data-Model) | Firestore schema, security rules, Hive boxes, sentinel encoding |
| [Features](Features) | Behavior-level walkthrough of every screen |
| [Architectural Decisions](Architectural-Decisions) | Key decisions recorded so they aren't re-litigated |
| [Billing & Cost](Billing-and-Cost) | Current no-billing decision, Firebase cost reference, fallback plan |
| [Roadmap](Roadmap) | What's left before App Store submission, and known gaps |
| [design.md](design.md) | Design system reference — colors, typography, component conventions, screen inventory |

For a deep dive on the GPS track-cleaning algorithm specifically, see
`docs/GPS-Track-Filtering-Pipeline.docx` in the repository (not in this wiki — it's a
formal technical reference better suited to a standalone document).

> **A note on the other pages in this wiki:** Current State, Code Map, Data Model, Features,
> Architectural Decisions, and Billing & Cost were last verified against the codebase on
> 2026-07-01, before a body of subsequent work (the Horizon Minimalist design-system
> typography migration, the sync bug fix described above, and the MAYDAY screen's visual
> unification described in design.md). This Home page and the map-tile status note above are
> current as of 2026-07-08; the other pages remain broadly accurate but haven't all been
> individually re-verified against that later work.

---

*Repository: [cpahab/Logbook](https://github.com/cpahab/Logbook) · Current branch: main*
