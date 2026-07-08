# Logbook — Design Brief ("Horizon Minimalist")

A design reference for generating UI screens for **Logbook**, a cross-platform sailing logbook app (Flutter; Android, iOS, macOS, Web). Use this document as the source of truth for colors, typography, components, and screen content — the goal is pixel-consistent output with the shipping app, not a new visual direction.

---

## 1. App Overview

Logbook helps a sailing crew keep a daily logbook underway: GPS track recording, per-day journal entries (crew, weather, course, sail state, notes), an emergency manifest (crew medical info, safety equipment, VHF channels), and a step-by-step MAYDAY radio-call guide. Data syncs across devices for the whole crew via an account-linked "logbook."

**Tone:** calm, functional, nautical without being kitschy. Think chart-table clarity and cockpit-instrument legibility, not a "beachy" or playful aesthetic. Safety-critical screens (MAYDAY) are the one place that's allowed to shout — everything else stays quiet.

---

## 2. Design Principles

1. **Flat over elevated.** No drop shadows as a default habit. Cards use a hairline border + a very subtle 4% (light) / 5% white (dark) shadow at most — not Material's default elevation system. App bars have zero elevation always, even when content scrolls underneath.
2. **One accent, used sparingly.** Gold (`secondary`) marks "this is active / this is important metadata" — section headers, the active bottom-nav tab, the most recent day's highlight, badge counts. It is never a base fill color for large areas.
3. **Left-aligned, not centered.** App bar titles, section headers, and body content are left-aligned. The one deliberate exception is the Home screen's branded wordmark (see §7.9), which stays centered.
4. **Type does the hierarchy work, not boxes.** Prefer a bold/tracked eyebrow label + a plain-weight value over boxes, background tints, or rules to separate sections.
5. **Everything sourced from the theme.** Every color and text style used in a screen must map to a named role below — no ad hoc hex values or one-off font sizes in a mockup. If a new situation doesn't fit an existing role, that's a signal to add a role, not to freehand a value.

---

## 3. Color System

Material 3 `ColorScheme` roles. Both themes ship; default to Light unless asked for Dark.

### 3.1 Light theme

| Role | Hex | Usage |
|---|---|---|
| `primary` | `#002B49` (Deep Navy) | App bar text/icons, primary buttons, links, active nav-adjacent icons, borders on emphasis elements |
| `onPrimary` | `#FFFFFF` | Text/icon on primary fills |
| `primaryContainer` | `#1A3A5C` | FAB background, elevated primary surfaces |
| `onPrimaryContainer` | `#87A4CC` | Text/icon on `primaryContainer` |
| `secondary` ("Captain's Gold") | `#A77E01` | Section-header eyebrow labels, active bottom-nav label, icon accents, badge text |
| `onSecondary` | `#241A00` | Text on a `secondary`-filled surface (dark ink — `secondary` is too bright for white text) |
| `secondaryContainer` | `#FFE088` | Pale gold fill — icon chips, count badges, active-tab icon (brighter than `secondary` itself) |
| `onSecondaryContainer` | `#A77E01` | Mirrors `secondary` deliberately — one consistent gold everywhere |
| `tertiary` | `#142435` | Dark navy accent surface (e.g. vessel-status card fill) |
| `onTertiary` | `#FFFFFF` | |
| `tertiaryContainer` | `#2A3A4C` | Bottom-nav bar background |
| `onTertiaryContainer` | `#93A4B9` | Inactive bottom-nav icon/label |
| `error` | `#BA1A1A` | Destructive actions, critical/urgent emergency accents |
| `onError` | `#FFFFFF` | |
| `errorContainer` | `#FFDAD6` | |
| `onErrorContainer` | `#93000A` | |
| `surface` | `#F7F9FB` | Screen background |
| `onSurface` | `#1B1C1D` | Primary body text |
| `onSurfaceVariant` | `#43474E` | Secondary/caption body text |
| `outline` | `#C3C6CF` | Input borders, dividers |
| `outlineVariant` | `#C3C6CF` | Card borders |
| `surfaceContainerLowest` | `#FFFFFF` | Card fill (the default "card on background" surface) |
| `surfaceContainerLow` | `#F5F3F4` | Secondary card fill, input fill |
| `surfaceContainer` | `#F2F4F6` | |
| `surfaceContainerHigh` | `#E9E8E9` | |

### 3.2 Dark theme

All surface/container/outline tiers below share one consistent navy family (hue ~216°, stepped only in lightness) — a prior pass mixed saturated-navy tiers (`surface`, `surfaceContainer`) with near-neutral greys (`surfaceDim`, `surfaceContainerLowest/Low/High`, `outline`) that only coincidentally shared the same hue angle at 9–17% saturation, so they read as plain charcoal next to the properly-tinted tiers. Five near-duplicate "dark ink" text colors (`onPrimaryContainer`, `onTertiary`, `onTertiaryFixed`, `onSecondary`) are now one canonical `#001C37`.

| Role | Hex | Usage |
|---|---|---|
| `primary` | `#7DB3F0` (light blue) | Same roles as light theme's `primary` |
| `onPrimary` | `#0A121E` | |
| `primaryContainer` | `#4C7FD9` | |
| `onPrimaryContainer` | `#001C37` | canonical dark ink |
| `secondary` | `#FFE088` (pale gold) | Same roles as light theme's `secondary` — brighter here because the surface is near-black |
| `onSecondary` | `#001C37` | canonical dark ink |
| `secondaryContainer` | `#B8860B` (goldenrod) | |
| `onSecondaryContainer` | `#3A2E00` | |
| `tertiary` | `#B7C8DE` | |
| `onTertiary` | `#001C37` | canonical dark ink |
| `tertiaryContainer` | `#2A3D5B` | Bottom-nav bar background — was drifted to a cyan-ish 202° hue, now matches the 216° navy family |
| `onTertiaryContainer` | `#C9D5E8` | |
| `error` | `#FFB4AB` | |
| `onError` | `#690005` | |
| `surface` | `#0A121E` ("midnight navy") | Screen background — calmer/less inky than the previous `#031428` |
| `onSurface` | `#F2F0F1` | |
| `onSurfaceVariant` | `#C3C6CF` | |
| `outline` | `#4E5D74` | Muted navy-grey — was pure neutral grey with zero blue tint |
| `outlineVariant` | `#343D4B` | |
| `surfaceDim` | `#080E17` | |
| `surfaceBright` | `#1A2E4D` | |
| `surfaceContainerLowest` | `#060A11` | Card fill |
| `surfaceContainerLow` | `#09101B` | |
| `surfaceContainer` | `#0E192A` | |
| `surfaceContainerHigh` | `#14253D` | |
| `surfaceContainerHighest` | `#1C3254` | |

### 3.3 Semantic tokens (derived, not new colors)

- **`mutedLabel`** = `onSurfaceVariant` at 80% opacity — bold/tracked eyebrow labels and secondary stat text (softer than full-strength `onSurfaceVariant`, which reads too heavy at that weight).
- **`criticalColor`** = `error`; **`criticalBgColor`** = `errorContainer`; **`criticalMutedColor`** = `error` at 20% — the entire emergency/MAYDAY vocabulary maps onto the standard error role, never a separate red.
- **`cardShadowColor`** = black at 4% (light) / white at 5% (dark) — the *only* shadow used on cards.
- **`dividerColor`** = `outlineVariant` at 30%.

---

## 4. Typography

**Font family:** DM Sans, everywhere (one deliberate exception: §7.9). Weights used: Regular (400), Medium (500), SemiBold (600), Bold (700).

### 4.1 Material roles actually in use

| Role | Size / weight | Used for |
|---|---|---|
| `headlineMedium` | 28 / 500 (600 on auth screens) | Auth screen titles ("Sign In", "Create Account") |
| `titleLarge` | 22 / 400 | Base for dialog titles (see `dialogTitle` below) |
| `bodyLarge` | 16 / 400 | Base for most "field value" text (see §4.2) |
| `bodyMedium` | 14 / 400 | Row labels, standard body copy, settings-row values |
| `bodySmall` | 12 / 400 | Captions, secondary stat text, italic descriptive notes |
| `labelSmall` | 11 / **700**, letter-spacing **1.5** (overridden from Material default) | Uppercase eyebrow section headers app-wide, e.g. "EMERGENCY CONTACTS", "VESSEL SAFETY" |

### 4.2 Custom roles (derived from the roles above, never freehanded)

| Role | Definition | Used for |
|---|---|---|
| `dialogTitle` | `titleLarge` + italic + weight 500 | Fullscreen dialog headers (add/edit timeline entry, add/edit crew member) |
| `fieldValueCompact` | 15 / 600 | Dense multi-column form values (timeline entry's time/course/speed, dialog buttons) |
| `fieldHintCompact` | 15 / regular | Hint text paired with `fieldValueCompact` |
| `fieldValueProse` | 18 / 600 | Single-column form values with more room (crew dialog fields, AlertDialog titles) |
| `microLabel` | 9 / 700, letter-spacing 1.0 | Field-level eyebrow labels smaller than a section header (e.g. "COURSE", "BLOOD GROUP") |
| `chipLabel` | 13 / 600 | Selectable chip text (sail-state toggles, distress-type chips) |
| `unitLabel` | 12 / 600 | Small unit suffix next to a number ("kn", "deg") |

Headline "big number" values (oil %, fuel %, keel status, a timeline entry's time-of-day, the home screen's "Recent Entries" subheading) consistently use **18px / weight 600** — this is the app's one "glanceable, important, short" tier, paired with a small eyebrow label above or beside it.

---

## 5. Iconography

Material Symbols, **outlined** style by default (e.g. `directions_boat_outlined`, `settings_outlined`), filled only for a genuinely "on/active" state (e.g. active bottom-nav icons render solid-color, not outline-swapped). Standard sizes: 16px inline-with-text, 18–20px in list rows/section headers, 22px in the bottom nav, 24px+ for empty-state illustrations.

---

## 6. Layout, Spacing & Shape

- **Corner radius:** 12px for cards/containers/chips-as-rectangles, 16px for dialogs and the app's Card/FAB shape, full stadium (999px) for pill-shaped chips and the FAB.
- **Elevation:** 0 everywhere by default (flat). Dialogs and the FAB are the only elements allowed a shadow, and even then it's minimal.
- **App bar:** flat, `elevation: 0`, `scrolledUnderElevation: 0` (no shadow appears on scroll), left-aligned title, bold, 18px, no bottom border/rule.
- **Cards:** `surfaceContainerLowest` fill, 1px `outlineVariant` border, 12–16px radius, the `cardShadowColor` shadow only (4px blur, 2px y-offset). A 4–6px solid color spine on the left edge is the standard way to indicate "this item is active/highlighted" (e.g. the most recent day in the journal list) — not a background-color change.
- **Spacing scale:** 4, 6, 8, 12, 16, 20, 24 — no arbitrary in-between values. Section-to-section vertical gaps are 20px; within-card gaps are 8–12px.
- **Bottom navigation:** a single floating bar (not a bare Material `BottomNavigationBar`) — rounded top corners, `tertiaryContainer` fill, a raised circular FAB breaking through the top edge for the primary "add entry" action. Active tab: solid gold icon + gold label, **no pill/background behind it** — the gold color alone carries the "active" state. Inactive tab: `onTertiaryContainer` icon + label.

---

## 7. Core Components & Screen-Specific Notes

### 7.1 Section header
Icon (18–20px, `secondary`) + uppercase label (`labelSmall`, `secondary`) in a `Row`, optionally with a trailing edit/add icon button. This is the single most repeated pattern in the app — every card group on every screen starts with one.

### 7.2 Data row (label + value)
A `SizedBox`-width label column (`bodyMedium` 600, `onSurface`) on the left, value right-aligned or trailing (`chipLabel` or `fieldValueCompact`, `primary` color) on the right — used throughout Settings and the vessel-info section. Keep the label column wide enough that translated labels (this app ships English + German) don't wrap.

### 7.3 Buttons
`FilledButton` (primary action, `primary` fill / `onPrimary` text, 12px radius) → `OutlinedButton` (secondary action, `primary` text + 25%-alpha `primary` border) → `TextButton`/destructive `OutlinedButton` in `error` color for delete/remove actions. Button text uses `fieldValueCompact` (15/600).

### 7.4 Chips
Two flavors: **filter chips** (stadium shape, `primary` fill when selected / `surfaceContainer` when not, `labelSmall`-derived text) and **selectable state chips** (sail state, motor on/off, keel up/down — stadium, `primary` fill when selected / `surfaceContainerLow` otherwise, `chipLabel` text).

### 7.5 Dialogs & forms
Fullscreen `Dialog.fullscreen` for anything with more than 2–3 fields (add/edit crew member, add/edit timeline entry) — app bar with `dialogTitle` style, body organized into bordered "cards" per logical group (Identity, Medical Info, Safety Equipment, ...), each with a `_SectionHeader` per §7.1. Short confirmations use a standard centered `AlertDialog` (16px radius, `fieldValueProse` title, `bodyMedium` content).

### 7.6 Journal / day list (Home screen)
Vertical list grouped by month (collapsible headers with a gold pale-fill count badge when collapsed). Each day is a card: date + weather/wind icons top row, route or day-of-week as the title, distance/duration stats inline at the bottom. The most recent (or otherwise "active") day gets the gold left-spine treatment from §6 and full opacity; other days sit at ~85% opacity.

### 7.7 Day detail screen
Single scroll of cards in this order: crew list → daily reflection (diary quote, italic) → photo strip → route map (with departure/arrival time pill labels) → log/timeline entries (each a bordered card: eyebrow label like "DEPARTURE"/"ARRIVAL"/"ENTRY", a large 18/600 time value, then course/speed/wind/sea/weather/sail data as a comma-joined caption line) → vessel status (oil/fuel % bars + keel state, on a `tertiary`-colored card) → free-text notes (last).

### 7.8 Tracks / map screen
Filter strip (1 Year / 1 Month / 1 Week / Custom date-range chips) above a map that takes ~48% of the remaining vertical space, with the day list below taking the other ~52% (map intentionally does *not* dominate — the list needs room). Map pins/badges use tiny (7–10px) bold labels in a solid-color rounded chip.

### 7.9 Home screen hero (the one branding exception)
The Home screen's app bar is taller (72px) and centered, showing the app wordmark in **Newsreader** (a serif, NOT DM Sans) at 28px bold, plus the vessel's name beneath it at 20px italic medium. This is a deliberate one-off brand treatment — do not extend the serif font anywhere else.

### 7.10 Emergency Manifest & Emergency Handbook
Same section-header + card pattern as everywhere else. Crew medical overview: blood-type gets its own red badge (`errorContainer` fill / `onErrorContainer` text) since it's the one field worth visually separating; every other field (allergies, conditions, EPIRB, remarks) uses a gold icon + standard `onSurface` text — blood is the only thing allowed to be red here.

### 7.11 MAYDAY / Radio Protocol screen — the one "loud" screen
App bar fills solid `error` red (not the flat/transparent app bar used elsewhere). Steps are numbered cards (STEP 1–7) with a pulsing red left border/glow while a distress alert is "live," red 11px tracked eyebrow labels, and oversized values (18–22px bold) for the parts a sailor needs to read at a glance while stressed (the "MAYDAY, MAYDAY, MAYDAY" line is 22px). This is the one screen explicitly allowed to break the "quiet, minimal" rule from §2 — that's the point.

Every large icon on the left of every step (including the identification/position/crew-status/closing steps, which otherwise share the plain `_StepCard` layout with the rest of the app) uses `errorContainer`/`onErrorContainer` as an icon-chip background/foreground pair — never the solid-red-fill/white-icon treatment used elsewhere for a plain "urgent" marker. Each theme uses its own natural pairing directly (light: pale-red bg + dark-red icon; dark: whatever `errorContainer`/`onErrorContainer` naturally resolve to in that theme) — no custom brightness-swapping logic, just the theme's own roles as-is.

Step 7 ("CLOSING / OVER") uses the exact same `_StepCard` shell as steps 3/4/6 (surface-colored card, red left border, red eyebrow label) rather than its old bespoke solid-navy treatment — every step now reads as one family, with only steps 1/2/5 (the true "live distress" cards) getting the pulsing red border/glow treatment on top.

The `_StepCard`-based steps' left border (3/4/6/7) is `error`, not the gold `secondary` used for section-header accents on every other screen — on this one screen, red is the only accent color, reserved entirely for "this is a MAYDAY-protocol step." Any content box that isn't a plain surface fill (the selected distress-type pill) uses the same `errorContainer`/`onErrorContainer` pale-bg/dark-text pairing as the icon chips, rather than a semantic color (e.g. blue for "GPS lock acquired") — visual consistency with the rest of the page wins over color-coding by data state on this screen specifically. Every `errorContainer` usage on this screen is full-strength — no per-element opacity tweaks — so it reads as one consistent red rather than several near-miss shades.

**Spoken-script typography.** The radio script mixes two kinds of text: fixed phrases that are always the same ("MAYDAY, MAYDAY, MAYDAY," "THIS IS YACHT," "CALLSIGN," "MMSI," "POSITION:") and fill-in values unique to this boat/situation (vessel name, callsign, MMSI, position fix, crew count, the selected nature of distress). Fixed phrases stay plain `onSurface`, bold, no underline. Every fill-in value uses one shared style regardless of which step it's in — `error` color + underline (`_spokenValueSpan` helper) — so a sailor reading under stress sees one consistent visual cue for "this is the part that's specific to right now," never a per-step color. Position is inline on the same line as its "POSITION:" label, same as every other step's label+value pair — no separate bordered box.

Step 5 (Nature of Distress) doesn't repeat its own heading as body text — the card's own "STEP 5: NATURE OF DISTRESS" eyebrow label already says it, and the phrase itself is never spoken on the radio anyway. Only the selected option (e.g. "FIRE") gets the spoken-value red-underline treatment; the other two options render as small `(bracketed)` tappable text below it rather than equal-weight selector pills, so it's visually obvious only one of the three is ever "the thing to say."

---

## 8. Screens Inventory

| Screen | Route | Notes |
|---|---|---|
| Sign In | `/auth/login` | |
| Register | `/auth/register` | |
| Forgot Password | `/auth/forgot-password` | |
| Verify Email | `/auth/verify-email` | |
| Home (Journal) | `/` | §7.6 |
| GPX Import | `/gpx-import` | Fullscreen import flow |
| Day Detail | `/day/:year/:month/:day` | §7.7 |
| Settings | `/settings` | Vessel info, VHF channels, preferences — §7.2 |
| Crew Roster | `/settings/crew-roster` | List + add/edit crew dialog, §7.5 |
| Tracks / Map | `/tracks` | §7.8 |
| Tracks Fullscreen | `/tracks/fullscreen` | Map only, no list |
| Emergency Manifest | `/emergency` | §7.10 |
| MAYDAY / Radio Protocol | `/emergency/mayday` | §7.11 |
| Emergency Handbook | `/emergency/distress` | Visual/sound/electronic distress-signal reference |

---

## 9. Accessibility Notes

- Body text must stay at or above 4.5:1 contrast against its surface.
- The gold `secondary` accent is a deliberate, documented exception: ~3.5:1 against the surface (light theme), which clears the 3:1 floor for large text/icon/UI-component use but *not* the 4.5:1 body-text bar — this is why gold is only ever used for short labels/icons, never paragraph text.
- Never rely on color alone to communicate state where avoidable (e.g. active nav tab uses both a color change and — where space allows — an icon/weight change).
