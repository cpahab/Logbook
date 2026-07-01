# Data Model — Firestore, Storage & Hive

## Firestore

```
users/{uid}
  ├── activeLogbookId: String
  └── logbooks: String[]          # logbook IDs this user belongs to

logbooks/{logbookId}
  ├── name: String
  ├── ownerUid: String
  ├── shareCode: String           # 8-char alphanumeric (excludes I/O/0/1 — read/typed by hand)
  ├── createdAt: Timestamp
  │
  ├── members/{uid}
  │   ├── role: 'owner' | 'guest'
  │   └── joinedAt: Timestamp
  │
  ├── entries/{yyyy-MM-dd}        # one document per calendar day
  │   ├── date, fromHarbor, toHarbor, notes, freeText
  │   ├── oilLevel, fuelLevel: int?   # 0–100%
  │   ├── keelDown: bool?
  │   ├── photos: String[]        # Storage download URLs
  │   ├── crew: CrewMember[]      # name, bloodType, allergies, conditions, remarks
  │   ├── timeline: TimelineEntry[]
  │   │   ├── time, course, speed, wind, sea, weather, remarks
  │   │   ├── grossState, fockState  # sail state sentinels, e.g. "sail:reef1"
  │   │   ├── motorOn, keelDown
  │   │   ├── vesselStatusNote    # sentinel, e.g. "vs:oil=75,fuel=60" or "crew:role=0:Alice · Bob"
  │   │   └── amendments: TimelineAmendment[]  # edit history — see below
  │   └── updatedAt: Timestamp    # FieldValue.serverTimestamp() — drives incremental sync
  │
  └── meta/
      ├── settings   # vessel name/MMSI/call sign, life raft/EPIRB/fire suppression, VHF 1–4,
      │              # GPX track-filter tuning (shared across the logbook — see filter_settings.dart)
      ├── contacts   # emergency contacts list
      ├── ui         # month-expansion state map (dashboard UI state)
      └── crew_roster  # shared crew roster: name, blood type, allergies, conditions, remarks, id

shareCodes/{8-char-code}
  └── logbookId: String          # lookup table for the QR/manual join flow
```

GPS tracks (`DailyTrack`) are **not** stored in Firestore — they live in Hive locally and
in Firebase Storage as raw GPX files, since a day's track can be arbitrarily large.

### Sentinel encoding

Several fields store a locale-neutral "sentinel" string instead of display text, so the
same data renders correctly regardless of the viewer's language and old entries don't
freeze into whatever language they were written in:

| Prefix | Example | Parsed by |
|---|---|---|
| `crew:` | `crew:role=0:Alice · Bob` | `HomeRepository.buildCrewNote` / display logic in `day_detail_screen.dart` |
| `vs:` | `vs:oil=75,fuel=60`, `vs:keel=down` | `sail_state_utils.dart: parseVesselStatus` |
| `sail:` | `sail:full`, `sail:reef1`, `sail:reef2`, `sail:lowered`, `sail:furled` | `sail_state_utils.dart: normalizeSailState` / `sailStateAbbr` |

Legacy entries written before a sentinel existed (plain German text) are detected and
handled by fallback branches in the same parsing functions — never migrated in bulk.

### Security rules (as of this writing — `firestore.rules` / `storage.rules` are authoritative)

- **Firestore:** membership-gated. A user can read/write a logbook's data only if a
  `members/{uid}` document exists for it. Only the owner can update/delete the logbook
  document itself or manage other members; a user can add themselves as a `guest`.
  `shareCodes/{code}` is readable by any signed-in user (not listable) — an accepted,
  documented trade-off given the ~1 trillion-combination code space.
- **Storage:** currently **authentication-only** (any signed-in user can read/write any
  `logbooks/{logbookId}/**` path), not membership-gated. This is deliberate: logbook IDs
  are non-guessable Firestore auto-IDs, so auth alone is considered sufficient for now.
  The stronger cross-service `isMember()` check can be restored once App Check is
  configured for release builds (see the comment in `storage.rules`).

---

## Hive (local storage)

| Box | Key | Value | Purpose |
|-----|-----|-------|---------|
| `daily_entries` | ISO date string | `DayEntry` | Journal entries |
| `daily_tracks` | ISO date string | `DailyTrack` | GPX tracks |
| `crew_roster` | member ID | `CrewMember` | Shared crew roster |
| `entry_sync_state` | string | `int` (epoch ms) | Local edit timestamps + last-sync-at, per entry |
| `settings` | string | `String` | `ThemeProvider`'s key-value store (theme, locale, vessel info, filter tuning, ...) |
| `emergency_contacts` / `emergency_contacts_meta` | numeric / string | `EmergencyContact` / `int` | Contacts + local-modified timestamp |

Hive schema safety follows one rule, documented directly in `day_entry.dart` and
`timeline_amendment.dart`: **never reuse or repurpose a `@HiveField` index.** Retired
fields stay as tombstone comments; new fields get the next unused index and must be
nullable (or carry a default) so old persisted objects still deserialize.
