#!/usr/bin/env python3
"""
Generates GitHub wiki pages from the upgrade plan content.
Run with: python3 generate_wiki.py
Output:  wiki/ directory containing all .md files

DO NOT RUN THIS SCRIPT. As of 2026-07, wiki/ is hand-maintained and reflects
current project reality (most of what this script writes describes work that
has since shipped, or pages that were deliberately merged/removed). Running
it would silently overwrite or resurrect superseded pages. Kept only for
historical reference to what the wiki originally looked like. If you need to
regenerate a page, edit it by hand in wiki/ instead.
"""

import sys

print(
    'generate_wiki.py is disabled: wiki/ is now hand-maintained and this '
    'script would overwrite it with a superseded snapshot. See the docstring '
    'at the top of this file. Aborting without writing anything.',
    file=sys.stderr,
)
sys.exit(1)

import os

WIKI_DIR = os.path.join(os.path.dirname(__file__), '..', 'wiki')
os.makedirs(WIKI_DIR, exist_ok=True)

def write_page(filename, content):
    path = os.path.join(WIKI_DIR, filename)
    with open(path, 'w') as f:
        f.write(content.strip() + '\n')
    print(f'  wrote {filename}')

# ─── Home ────────────────────────────────────────────────────────────────────

write_page('Home.md', """
# Logbook App — Upgrade Planning & Architecture

A Flutter-based sailing logbook for iOS, macOS, and Android.
This wiki documents the architecture, completed changes, and planned upgrades.

---

## Contents

| # | Page | Summary |
|---|------|---------|
| 1 | [Current State](Current-State) | Technology stack and where the app stands today |
| 2 | [v1.0.17 Changes](v1.0.17-Changes) | All 17 items implemented in the v1.0.17 session |
| 3 | [Multilingual Support](Multilingual-Support) | German / English implementation plan |
| 4 | [Authentication](Authentication) | Email, Apple, Google auth design |
| 5 | [Billing & Cost Strategy](Billing-and-Cost-Strategy) | Free model, web subscription option |
| 6 | [Maps Provider Migration](Maps-Provider-Migration) | Required before App Store submission |
| 7 | [Cost Risk Analysis](Cost-Risk-Analysis) | Firebase cost estimates and risk mitigation |
| 8 | [Roadmap](Roadmap) | Sequenced plan to first public release |
| A | [Implementation Prompts](Implementation-Prompts) | Copy-paste prompts for future Claude Code sessions |
| B | [Firebase Cost Reference](Firebase-Cost-Reference) | Spark limits and Blaze pricing tables |
| C | [Architectural Decisions](Architectural-Decisions) | Key decisions recorded so they aren't re-litigated |

---

## Quick reference — what to do next

1. **Before any App Store submission:** [Switch map tiles to MapTiler + Esri](Maps-Provider-Migration) (2 days, no dependencies)
2. **For Android:** Register Android app in Firebase Console (see [prompt A2](Implementation-Prompts#a2--android-firebase-registration))
3. **Parallel tracks:** [i18n](Multilingual-Support) and [Auth Phase 2.1](Authentication) can start simultaneously

---

*Repository: [cpahab/Logbook](https://github.com/cpahab/Logbook) · Current branch: main*
""")

# ─── Section 1: Current State ────────────────────────────────────────────────

write_page('Current-State.md', """
# 1. Current State of the App

The Logbook app is a Flutter-based sailing logbook for iOS, macOS, and Android
(Android partially configured). It is currently used only by the developer.

The app stores data locally using Hive and optionally syncs to Firebase Firestore
using an installation-code model — two devices share a logbook by exchanging an
eight-character code. There is no user authentication.

---

## Technology Stack

| Layer | Technology | Notes |
|-------|-----------|-------|
| Local storage | Hive (typed adapters) | DayEntry, TimelineEntry, CrewMember, DailyTrack, EmergencyContact |
| Cloud sync | Firebase Firestore + Storage | Keyed by installationId — no auth required today |
| State management | provider 6.1.2 (ChangeNotifier) | 3 providers: HomeRepository, ThemeProvider, EmergencyRepository |
| Navigation | go_router 17.2.3 | Declarative routes, GoRouter redirect hooks available |
| Maps | flutter_map 8.0.0 | OSM tiles + Esri satellite — both require tile provider change before App Store |
| Auth package | firebase_auth (in pubspec) | Present but never wired up — zero auth code exists |
| Platform targets | iOS ✓  macOS ✓  Android ⚠ | Android Firebase not yet configured (placeholder appId) |
| Localization | flutter_localizations + intl | Hardcoded to de_CH — no ARB files, no l10n.yaml |
| Billing / IAP | None | Zero billing code exists |

---

## Key structural facts

- **Firestore path today:** `logbooks/{installationId}/entries/…`
- **Auth:** None — anyone who knows the installationId can read the logbook
- **Android:** `firebase_options.dart` contains a placeholder `appId`; `google-services.json` is missing
- **Maps:** OSM demo tile server is policy-prohibited for published apps; Esri satellite used without an API key
- **Sentinel issue:** The string `"Besatzung: "` is used both as display text and as a detection marker in code logic — must be split before any i18n work
""")

# ─── Section 2: v1.0.17 Changes ──────────────────────────────────────────────

write_page('v1.0.17-Changes.md', """
# 2. Completed Changes — v1.0.17

All items below were implemented and committed to main. The previous main is preserved as `main-v1.0.16`.

---

## Crew Roster (Items 1–6)

- Allergies and conditions fields added to `CrewMember` Hive model; persisted locally and synced to Firestore.
- Empty crew list opens directly in add-member mode (no redundant edit step).
- Non-empty crew list uses a pending-buffer pattern: edits are staged and committed only on "Übernehmen" — matching the vessel-status interaction.
- First timeline entry of a voyage auto-captures the current crew list as a timestamped crew snapshot entry.
- Any crew change after the first snapshot auto-creates a new timeline entry recording the delta.
- Crew section uses ÄNDERN/HINZUFÜGEN labels matching the AKTUALISIEREN pattern on vessel status.

---

## Timeline Entry (Items 7–9)

- New log entries start blank — no field pre-fill from the previous entry.
- Course field constrained to 0–359 via a custom `TextInputFormatter`; out-of-range values are rejected on keypress.
- Deleting a log entry no longer clears unrelated snackbars (removed `clearSnackBars()` call).

---

## Tooltips & GPS Consent (Items 10–11)

- Tooltips added to all edit/add icon buttons: crew add/edit, Etappe erfassen, Etappe speichern, Logeintrag bearbeiten/löschen, Fotos hinzufügen, Schiffsstatus aktualisieren, and Emergency Manifest edit buttons.
- `GpsConsentService` created: shows a purpose-explanation dialog at first app frame (`HomeScreen.initState` via `addPostFrameCallback`) before the OS permission prompt. Text is urgency-focused and explains the Mayday use case.

---

## Emergency Manifest (Items 12–14)

- Vessel safety info (MMSI, Rufzeichen, Rettungsinsel, EPIRB, Feuerlöschanlage) is now editable inline via an `AlertDialog` on the Emergency Manifest page — no longer navigates away to Settings. Settings editing path remains unchanged.
- The redundant "Tap Edit to add safety equipment details" hint text was removed; the EDIT button in the section header is the single edit trigger.
- Crew Medical Overview header now shows an info-icon tooltip explaining that crew data is auto-filled from the most recent logbook day entry.

---

## Dashboard & Map Screen (Items 15–17)

- Stat boxes harmonized: both Dashboard and Map screens now use `Icons.sailing` for Segeltage, identical typography (Newsreader 22pt, Inter 10pt label), border radius 12, subtle box shadow, and uppercase labels.
- Map filter presets changed from JAHR/6 MON/3 MON/EIGENE to **1 JAHR / 1 MONAT / 1 WOCHE / EIGENE**. Default is now 1 Monat.
- Custom date chip uses compact `d.M.yy` format with reduced letter spacing; date range picker wrapped in `MediaQuery.withClampedTextScaling` to prevent font-scale clipping in picker input fields.

---

## Files changed

| File | Change |
|------|--------|
| `lib/core/services/gps_consent_service.dart` | New — GPS consent dialog |
| `lib/features/emergency/presentation/emergency_manifest_screen.dart` | Inline vessel safety edit, crew tooltip, empty state |
| `lib/features/home/presentation/day_detail_screen.dart` | Crew pending-buffer, timeline fixes, all tooltips |
| `lib/features/home/presentation/home_screen.dart` | GPS consent call, sailing icon |
| `lib/features/home/widgets/add_timeline_entry_dialog.dart` | Blank start, course formatter |
| `lib/features/home/data/home_repository.dart` | Crew snapshot auto-entry |
| `lib/features/tracks/presentation/tracks_screen.dart` | Filter presets, date format, stat box harmonization |
| `lib/core/services/firestore_service.dart` | Allergies/conditions fields |
""")

# ─── Section 3: i18n ─────────────────────────────────────────────────────────

write_page('Multilingual-Support.md', """
# 3. Future Upgrade: Multilingual (de / en)

**Estimated effort:** ~11 working days
**Dependencies:** None — can start immediately
**Ready-to-paste prompt:** [Appendix A3](Implementation-Prompts#a3--multilingual-german--english)

---

## Scope decision

German and English only. The Emergency Manifest screen stays in English permanently — it is already
written in English and this is the correct call for a maritime safety document that may be used in
international waters or by non-German-speaking crew.

---

## Current state

- `flutter_localizations` and `intl` packages are already in `pubspec.yaml`.
- The app locale is hardcoded to `de_CH` in `app.dart`.
- Approximately 80–90 German strings are scattered across presentation files. No ARB files or `l10n.yaml` exist.
- **Structural issue:** the string `"Besatzung: "` serves dual purpose — it is displayed text AND a logic sentinel used in `startsWith()` detection. Localising it naively breaks crew-change detection.

---

## The sentinel fix (must be done first)

Before any string extraction, the `"Besatzung: "` prefix must be split into two things:

1. A **non-localised ASCII key** used in code logic: `"crew:"`
2. A **separate display string** in the ARB file: `"Besatzung: "` / `"Crew: "`

The Firestore-stored `vesselStatusNote` values also use this prefix, so existing stored entries
will need a one-time migration or the detection logic must handle both the old and new prefix.

Files to update: `home_repository.dart` and `day_detail_screen.dart`.

---

## Work phases

| Phase | Work | Est. days |
|-------|------|-----------|
| 1.1 Infrastructure | Add `l10n.yaml`, configure gen-l10n, wire `AppLocalizations` delegate in `app.dart`, language toggle in Settings persisted to Hive | 2 |
| 1.2 String extraction | Extract ~80–90 strings into `app_de.arb`, fix Besatzung sentinel, handle ICU interpolations (counts, distances) | 4 |
| 1.3 English ARB | Create `app_en.arb` — many terms (nm, kn, MMSI, VHF, GPX) are already English; main work is UI copy | 2 |
| 1.4 Date formatting | Verify DateFormat calls respect active locale; German: TT.MM.JJJJ, English: DD/MM/YYYY (maritime convention) | 1 |
| 1.5 QA | All screens in both languages, PDF export, edge cases and empty states | 2 |

---

## Important constraints

- **Skip all files in `lib/features/emergency/`** — Emergency Manifest stays English permanently.
- The i18n work is fully independent of auth — both can proceed in parallel.
- Once ARB infrastructure is in place, each additional language is 2–3 days of translation.
""")

# ─── Section 4: Auth ─────────────────────────────────────────────────────────

write_page('Authentication.md', """
# 4. Future Upgrade: Authentication

**Estimated effort:** ~20 working days
**Dependencies:** Android Firebase registration ([A2](Implementation-Prompts#a2--android-firebase-registration))
**Ready-to-paste prompt:** [Appendix A4](Implementation-Prompts#a4--authentication-email-apple-google)

---

## Decisions already made

- **Providers:** Email/Password, Apple Sign-In, Google Sign-In
- **No grace period** for existing users (developer is the only current user — clean cutover)
- **Platforms:** iOS, Android, macOS

---

## Data model change

The current Firestore structure is keyed by an `installationId` with no access control.
Authentication enables proper access control.

| | Today | After auth |
|--|-------|-----------|
| Firestore path | `logbooks/{installationId}/entries/…` | `boats/{boatId}/entries/…` |
| Access control | None — anyone with the code can read | Firestore rules: only members of the boat |
| User identity | None | `users/{uid}/profile → {boatId, email, createdAt}` |
| Multi-device share | Exchange 8-char installationId | Same boatId, second uid added to members array |
| Migration needed? | N/A (developer only) | Clean start — no migration scripts required |

---

## Android and macOS prerequisites

Before any auth work can be tested on Android or macOS:

- **Android:** Run `flutterfire configure --platforms=android`, add `google-services.json` to `android/app/`, set `applicationId` in `build.gradle`.
- **macOS:** Register a separate Firebase macOS app (currently shares the iOS appId — needs its own for correct Auth OAuth callbacks).
- **Sign in with Apple:** Add the capability to both iOS and macOS Xcode targets; add entitlement files.
- **Google Sign-In:** Add SHA-1 fingerprint to Firebase Console for Android; add reversed-client-id URL scheme to `Info.plist` for iOS.

---

## Work phases

| Phase | Work | Est. days |
|-------|------|-----------|
| 2.1 Platform setup | Firebase Android registration, macOS app separation, enable Auth providers, add `sign_in_with_apple` + `google_sign_in` packages, entitlements and URL schemes | 5 |
| 2.2 Auth UI | Login screen (email + Apple + Google), registration, forgot-password, auth state listener driving GoRouter redirect, account screen in Settings (sign out, delete account) | 5 |
| 2.3 Data model | New Firestore structure, Firestore Security Rules, FirestoreService refactor to use `boatId` from user profile | 5 |
| 2.4 Share model | "Connect another device" flow: enter boatId on second device → uid added to `boats/{boatId}/members`; disconnect / leave boat actions | 3 |
| 2.5 Auth QA | All three providers on all three platforms, account linking edge case, offline auth state persistence | 2 |

---

## Account linking edge case (required)

If a user signs in with Google using the same email address as an existing email/password account,
Firebase throws a `credential-already-in-use` error. The app must catch this and offer a "Link accounts" flow.

This is a required UX path — it is surprisingly common and App Store reviewers test it.

---

## Apple Sign-In requirement

Apple Sign-In is **mandatory** when any social login is offered on iOS (App Store rule 4.8).
Offering Google but not Apple is a rejection reason.
""")

# ─── Section 5: Billing ──────────────────────────────────────────────────────

write_page('Billing-and-Cost-Strategy.md', """
# 5. Future Upgrade: Billing & Cost Strategy

**Current recommendation:** No billing — absorb Firebase costs
**If costs grow:** Web subscription + token model (see below)
**Ready-to-paste prompt (if needed):** [Appendix A5](Implementation-Prompts#a5--web-subscription--token-billing-optional-implement-later)

---

## The core principle

The developer does not want to subsidise cloud storage costs. However, the actual Firebase
cost per user is very small — roughly €0.003–0.006 per active user per month. The question
is therefore not "how much does it cost" but "what model avoids paywall complexity in the app
while still recovering costs if the app grows."

---

## Option comparison

| Model | Dev cost | User cost | Paywall in app | Android | Effort |
|-------|----------|-----------|----------------|---------|--------|
| Absorb Firebase costs | $0–20/mo | None | None | Yes | Zero |
| CloudKit (Apple platforms only) | $0 | None (iCloud quota) | None | No | 3 weeks |
| Web subscription + token | $0 | ~€10/yr via Stripe | None — token entry only | Yes | 2 weeks |
| Local network sync (Bonjour) | $0 | None | None | Yes | 3 weeks |
| Full IAP paywall | Firebase costs | ~€2/yr via App Store | Yes — full Apple review | Yes | 6–8 weeks |

---

## Recommended approach

**Deploy without any billing now. Add web subscription later only if Firebase costs become real.**

1. Set a Firebase budget alert at €20/month (email notification).
2. Set a hard spending cap at €50/month (Firebase automatically disables billing — note: this also disables Firestore writes above the Spark limit, so users would see sync failures rather than unexpected charges).
3. At ~500 active users, evaluate whether the Firebase bill is meaningful. It will likely be €2–4/month.
4. If cost recovery is needed, implement the web subscription + token model.

> **Why not IAP now?** App Store IAP adds 30% Apple cut, a dedicated review process for subscriptions, RevenueCat integration complexity, paywall UI, Cloud Function webhook infrastructure, and ongoing subscription management. The break-even point is at several hundred paying users — not where the app is today.

---

## Web subscription + token model (detail)

This model avoids App Store IAP entirely and is explicitly permitted by Apple guidelines
when the service is delivered outside the app.

1. User visits `logbuch.app/sync` in a browser and pays via Stripe (e.g. €9.90/year).
2. Stripe webhook calls a Firebase Cloud Function that generates a UUID sync token and emails it to the user.
3. User enters the token in app Settings under "Sync-Code aktivieren."
4. The app sends the token to a Cloud Function that validates it and marks the user's Firestore subscription as active.
5. Firestore Security Rules gate write access on `subscription.status == "active"`.

**Result:** No in-app purchase UI, no Apple review for billing, no 30% platform fee.
""")

# ─── Section 6: Maps ─────────────────────────────────────────────────────────

write_page('Maps-Provider-Migration.md', """
# 6. Maps — Required Change Before Any App Store Submission

> This must be addressed regardless of which other upgrades are pursued.
> Both current tile providers violate their terms of service for published apps.

**Estimated effort:** 2 days
**Dependencies:** None — do this first
**Ready-to-paste prompt:** [Appendix A1](Implementation-Prompts#a1--map-tile-provider-switch-maptiler--esri)

---

## Current situation

The app uses two tile sources, called in **five places** (`tracks_screen.dart` ×2, `day_detail_screen.dart` ×2, `pdf_exporter.dart` ×1):

| Tile source | Problem |
|-------------|---------|
| `tile.openstreetmap.org` | OSM's own servers are explicitly off-limits for distributed apps. Their policy states that heavy use (including app distribution) is forbidden without prior permission from the OSM Operations Working Group. |
| `server.arcgisonline.com` (Esri) | The ArcGIS Living Atlas World Imagery basemap requires an Esri Developer account and an API key for production use, even on the free tier. Currently called with no credentials. |

---

## Recommended solution: MapTiler

MapTiler is an OSM-compatible tile CDN that is **drop-in compatible with `flutter_map`**.
It is specifically recommended for this app because it offers a **nautical chart map style**
(depth contours, buoys, traffic separation zones, port markers) — directly relevant to sailors.

| MapTiler tier | Tile requests/month | Cost |
|--------------|---------------------|------|
| Free | 100,000 | €0 |
| Pay-as-you-go | Unlimited | €0.003 per 1,000 above free tier |
| At 500 users (est.) | ~50,000 requests | €0 — within free tier |
| At 2,000 users (est.) | ~200,000 requests | ~€0.30/month |

For the Esri satellite layer, the existing URL continues to work — just add an API key from
the free ArcGIS Developer tier (2 million tile requests/month free).

---

## Code change

The change is a URL swap in five locations plus a new constants file.

```dart
// lib/core/constants/map_config.dart
const kMapTilerApiKey = 'YOUR_MAPTILER_API_KEY';
const kBaseTileUrl =
    'https://api.maptiler.com/maps/nautical/{z}/{x}/{y}.png?key=$kMapTilerApiKey';
const kSatelliteUrl =
    'https://server.arcgisonline.com/.../tile/{z}/{y}/{x}?token=$kEsriKey';
```

Files to update:
- `lib/features/tracks/presentation/tracks_screen.dart` (×2)
- `lib/features/home/presentation/day_detail_screen.dart` (×2)
- `lib/features/home/utils/pdf_exporter.dart` (×1)
- Update `RichAttributionWidget` in both map widgets to credit MapTiler

The `flutter_map` package and `latlong2` do not need to change. No provider migration required.

---

## MapTiler vs Mapbox summary

| | MapTiler | Mapbox |
|--|----------|--------|
| Free tier | 100,000 map loads/month | 50,000 map loads/month |
| flutter_map compatible | Yes — standard XYZ tile URLs, drop-in | No — requires separate `mapbox_maps_flutter` SDK |
| Nautical charts | Yes, built-in NAUTICAL style | No native nautical style |
| OSM base | Yes | Originally OSM, now proprietary |
| Effort to integrate | URL swap | SDK replacement |

**MapTiler wins** for this app: nautical style, drop-in compatibility, 2× more generous free tier.
""")

# ─── Section 7: Cost Risk ────────────────────────────────────────────────────

write_page('Cost-Risk-Analysis.md', """
# 7. Cost Risk Analysis — Running the App for Free

Full reference data is in [Appendix B](Firebase-Cost-Reference).

---

## Firebase free tier capacity (Spark plan)

| Firebase service | Free tier limit | App usage at 500 users | Headroom |
|------------------|----------------|------------------------|----------|
| Firestore reads | 50,000/day | ~5,000/day | 10× margin |
| Firestore writes | 20,000/day | ~2,000/day | 10× margin |
| Firestore storage | 1 GB total | ~365 MB (365 entries × 1 KB × 1,000 users) | Adequate |
| Firebase Storage (GPX) | 5 GB total | ~5 GB (10 MB × 500 users) | At limit |
| Firebase Auth (email) | 10,000/month | Trivial | Fine |
| Auth (Google/Apple) | Unlimited on Identity Platform | — | Free |

---

## Blaze (pay-as-you-go) cost estimates

| Active users | Estimated monthly Firebase cost |
|-------------|--------------------------------|
| 100 | €0 (Spark free tier covers all) |
| 500 | €0–1 |
| 1,000 | €3–6 |
| 5,000 | €18–30 |
| 10,000 | €50–80 |

---

## Risk mitigation

- Set a Firebase billing budget **alert at €20/month** (email notification).
- Set a **hard spending cap at €50/month** (Firebase automatically disables billing — note: this also disables Firestore writes above the Spark limit, so users would see sync failures rather than unexpected charges).
- A runaway read/write bug is the main risk. Firebase's billing console shows per-operation usage in near-real-time — monitor this for the first week after any sync-related code change.

---

## Verdict

Running completely free is financially sound for the foreseeable life of a niche sailing logbook.
Getting to 1,000 active users — where cost reaches €5/month — is itself a significant milestone.
The entire first year of Firebase costs will likely be under €50 total.
""")

# ─── Section 8: Roadmap ──────────────────────────────────────────────────────

write_page('Roadmap.md', """
# 8. Recommended Roadmap & Sequencing

**Total elapsed time to first public release: 8–10 weeks**
(with i18n and auth Phase 2.1 running in parallel from week 1)

---

## Immediate — before App Store submission

1. Switch map tiles to MapTiler + Esri API key. (2 days — no dependencies)
   → See [Maps Provider Migration](Maps-Provider-Migration) and [Prompt A1](Implementation-Prompts#a1--map-tile-provider-switch-maptiler--esri)

2. Register Android app in Firebase Console; add `google-services.json`. (1 day)
   → See [Prompt A2](Implementation-Prompts#a2--android-firebase-registration)

---

## Short term — parallel tracks (can run concurrently)

3. **i18n: de/en** (11 days — independent of auth; Emergency Manifest stays English)
   → See [Multilingual Support](Multilingual-Support) and [Prompt A3](Implementation-Prompts#a3--multilingual-german--english)

4. **Auth Phase 2.1** — Firebase Android registration, macOS app separation, enable Auth providers (5 days — begin concurrently with i18n)
   → See [Authentication](Authentication) and [Prompt A4](Implementation-Prompts#a4--authentication-email-apple-google)

---

## Medium term — after auth

5. App Store Connect and Google Play setup, submissions.
6. Set Firebase budget alerts. Deploy without billing.

---

## Later — if/when needed

7. Web subscription + token billing model — only if Firebase cost becomes real or cost recovery is desired.
   → See [Billing & Cost Strategy](Billing-and-Cost-Strategy) and [Prompt A5](Implementation-Prompts#a5--web-subscription--token-billing-optional-implement-later)

8. Additional languages — once ARB infrastructure is in place, each new language is 2–3 days of translation.

9. Nautical chart enhancements — MapTiler nautical style + OpenSeaMap overlay for chart markers.

---

## Full calendar view

| Weeks | Work | Dependency |
|-------|------|-----------|
| 1 | Maps tile switch + Android Firebase registration | None — start here |
| 1–3 | i18n (parallel) | None |
| 2–3 | Auth Phase 2.1 — platform setup | After Android registration |
| 4–5 | Auth Phase 2.2–2.3 — auth UI + data model | After 2.1 |
| 6 | Auth Phase 2.4–2.5 — share model + QA | After 2.3 |
| 7–8 | App Store Connect + Google Play setup, submissions | After auth + i18n complete |
| 8+ | Apple review clock (1–2 weeks) | After submission |
| Later | Web billing (if needed) | Auth must be complete |
""")

# ─── Appendix A: Prompts ─────────────────────────────────────────────────────

write_page('Implementation-Prompts.md', """
# Appendix A — Implementation Prompts for Future Sessions

Each prompt below is designed to be pasted directly into a new Claude Code session.
They are self-contained — each includes the necessary context so the agent can begin
work without reading back through previous sessions.
The branch and file paths match the current repository state on main.

---

## A1 — Map Tile Provider Switch (MapTiler + Esri)

**Effort:** 2 days | **Dependency:** None | **Do this first before any App Store submission**

```
We are working on the Flutter sailing logbook app at /home/user/Logbook (Flutter,
Hive, Firebase, flutter_map). The app currently uses OSM demo tiles
(tile.openstreetmap.org) and Esri satellite tiles (server.arcgisonline.com)
with no API keys. Both violate their terms for published apps.

Task: Switch to MapTiler (nautical chart style) + Esri (with API key).

1. Create lib/core/constants/map_config.dart with:
   - kMapTilerApiKey (placeholder string)
   - kBaseTileUrl using MapTiler nautical style:
     https://api.maptiler.com/maps/nautical/{z}/{x}/{y}.png?key={key}
   - kSatelliteUrl using Esri World Imagery with API key param

2. Replace the hardcoded URL strings in all 5 places:
   - lib/features/tracks/presentation/tracks_screen.dart (×2)
   - lib/features/home/presentation/day_detail_screen.dart (×2)
   - lib/features/home/utils/pdf_exporter.dart (×1 static URL)

3. Update RichAttributionWidget in both map widgets to credit MapTiler.

Do not change any other code. Commit and push to main.
```

---

## A2 — Android Firebase Registration

**Effort:** 1 day | **Dependency:** None | **Required before any Android testing**

```
We are working on the Flutter sailing logbook app at /home/user/Logbook.
Firebase is configured for iOS and macOS but Android has a placeholder
appId in lib/firebase_options.dart: "REPLACE_WITH_ANDROID_APP_ID".

Task: Help me complete Android Firebase registration.

1. Show me the exact flutterfire CLI command to run locally to register
   the Android app (bundle ID: com.ziegler.logbook or confirm from
   android/app/build.gradle).
2. Once I have run flutterfire and have google-services.json:
   - Confirm where to place google-services.json
   - Update firebase_options.dart with the real Android appId
   - Verify android/app/build.gradle has the correct applicationId and
     the google-services plugin applied
3. Verify the android/ directory has the necessary plugin classpath in
   android/build.gradle or settings.gradle.kts

Commit and push changes to main once verified.
```

---

## A3 — Multilingual (German / English)

**Effort:** 11 days | **Dependency:** None | **Emergency Manifest stays English**

```
We are working on the Flutter sailing logbook app at /home/user/Logbook.
The app is currently hardcoded to German (de_CH). We want to support
German and English, with the Emergency Manifest screen permanently
in English (do not extract strings from emergency_manifest_screen.dart).

flutter_localizations and intl are already in pubspec.yaml.

CRITICAL — fix the Besatzung sentinel first:
The string "Besatzung: " in home_repository.dart is used both as display
text and as a detection sentinel (startsWith). Before extracting strings,
change the stored prefix to a non-localised ASCII key "crew:" and create
a separate display string for the ARB file. Update the detection logic in
day_detail_screen.dart and home_repository.dart accordingly.

Then:
1. Add l10n.yaml (arb-dir: lib/l10n, template-arb-file: app_de.arb)
2. Create lib/l10n/app_de.arb with all extracted German strings
3. Create lib/l10n/app_en.arb with English translations
4. Wire AppLocalizations.delegate in lib/app.dart
5. Add language selector in Settings screen, persist choice in ThemeProvider
6. Verify DateFormat calls use the active locale

Skip all files in lib/features/emergency/.
Commit and push to main after each phase.
```

---

## A4 — Authentication (Email, Apple, Google)

**Effort:** 20 days | **Dependency:** Android Firebase registered (A2) | **New Firestore structure**

```
We are working on the Flutter sailing logbook app at /home/user/Logbook.
firebase_auth is in pubspec.yaml but never wired up. We want to add:
  - Email/Password login
  - Apple Sign-In (iOS + macOS)
  - Google Sign-In (iOS + Android)

Current Firestore path: logbooks/{installationId}/...
Target Firestore path:  boats/{boatId}/...  +  users/{uid}/profile

There are NO existing users to migrate. Clean cutover.

Phase 1 — Platform setup (tell me what to do in Firebase Console and Xcode):
  - Enable Email/Password, Apple, Google in Firebase Auth Console
  - sign_in_with_apple capability for iOS and macOS targets
  - Google reversed-client-id URL scheme in Info.plist
  - SHA-1 fingerprint for Android in Firebase Console
  - Add packages: sign_in_with_apple, google_sign_in to pubspec.yaml

Phase 2 — Auth UI:
  - Login screen: email+password fields, Apple button, Google button
  - Register screen, forgot-password screen
  - Auth guard in GoRouter (router.dart) — redirect unauthenticated to /login
  - Account section in settings_screen.dart: email, sign out, delete account

Phase 3 — Data model:
  - Update lib/core/services/firestore_service.dart to use boatId
    (from users/{uid}/profile.boatId) instead of installationId
  - On first authenticated launch: create users/{uid} and boats/{boatId}
  - Write Firestore Security Rules: only members of boats/{boatId} can r/w

Phase 4 — Multi-device share:
  - "Connect to existing logbook" flow: user enters boatId
  - Cloud Function or client-side: add uid to boats/{boatId}/members

Commit and push each phase to main separately.
```

---

## A5 — Web Subscription + Token Billing (optional, implement later)

**Effort:** 2 weeks | **Dependency:** Auth (A4) must be complete | **Only implement if Firebase costs become meaningful**

```
We are working on the Flutter sailing logbook app at /home/user/Logbook.
Auth is complete (Firebase Auth, users/{uid} in Firestore).
We want to add optional paid cloud sync using a web-based subscription
model to avoid App Store IAP (no 30% platform cut, no IAP review).

Model:
  1. User pays on website (Stripe) → webhook → Cloud Function generates UUID
     token → emails it to user
  2. User enters token in app Settings ("Sync-Code aktivieren")
  3. App sends token to validation Cloud Function → sets
     users/{uid}/subscription: {status: "active", expiresAt}
  4. Firestore Security Rules gate write access on subscription.status

Tasks:
  - Write Firebase Cloud Functions: generateToken (Stripe webhook),
    validateToken (called from app)
  - Add token entry field + "Activate" button to settings_screen.dart
  - Add subscription status display in settings_screen.dart
  - Add sync gate in home_repository.dart: check subscription before
    any Firestore write; fall back to local-only if not subscribed
  - Add persistent banner in home_screen.dart when sync is inactive
  - Update Firestore Security Rules to check subscription.status

Commit and push each component to main separately.
```
""")

# ─── Appendix B: Firebase Cost Reference ─────────────────────────────────────

write_page('Firebase-Cost-Reference.md', """
# Appendix B — Firebase Cost Reference

---

## Spark plan (free) limits

| Service | Free limit | What exceeds it |
|---------|-----------|-----------------|
| Firestore reads | 50,000 / day | Active users doing many reads on app open |
| Firestore writes | 20,000 / day | Heavy logging days with many timeline entries |
| Firestore storage | 1 GiB total | Approximately 1,300 users with a full year of entries |
| Firebase Storage | 5 GiB total | Approximately 500 users with 10 MB of GPX tracks each |
| Firebase Auth (email) | 10,000 MAU / month | Not a concern at early scale |
| Auth (Google / Apple) | Unlimited on Identity Platform | Always free |
| Cloud Functions invocations | 125,000 / month | Only relevant if billing webhooks are added |

---

## Blaze pricing (after free tier)

| Service | Price |
|---------|-------|
| Firestore reads | $0.06 per 100,000 |
| Firestore writes | $0.18 per 100,000 |
| Firestore storage | $0.18 per GiB/month |
| Firebase Storage | $0.026 per GiB/month |
| Cloud Functions | $0.40 per million invocations + compute time |

---

## Budget protection setup

In Firebase Console → Project Settings → Usage and billing:

1. Set a **budget alert at €20/month** (email notification to you)
2. Set a **spending limit at €50/month**

> **Important:** The spending limit prevents runaway costs but will cause Firestore
> writes to fail once hit — users will see sync errors rather than unexpected charges.
> This is the correct trade-off for a small independent app.

---

## GPX storage note

Firebase Storage is the most constrained free resource for this app.
GPX track files can be 1–10 MB each. At 500 users with 10 MB average:
that's 5 GB — right at the Spark plan limit.

Options if this becomes a constraint:
- Compress GPX files before upload (gzip reduces them 60–70%)
- Store only the most recent N tracks in Storage; older tracks local-only
- Move to Blaze plan (~€0.026/GB/month — 5 GB is €0.13/month, negligible)
""")

# ─── Appendix C: Decisions Log ───────────────────────────────────────────────

write_page('Architectural-Decisions.md', """
# Appendix C — Key Architectural Decisions Log

Decisions made during planning — recorded so they don't need to be re-litigated in future sessions.

---

| Decision | Choice made | Reasoning |
|----------|------------|-----------|
| Emergency Manifest language | Always English | Already written in English; maritime safety document used internationally; do not localise |
| Auth providers | Email/Password + Apple + Google | Apple Sign-In mandatory when offering any social login on iOS (App Store rule). Google Sign-In covers Android. Email/Password as universal fallback. |
| Billing model (current) | No billing — absorb Firebase costs | Firebase cost is < €5/month at 1,000 users. Billing complexity is not justified at current scale. Revisit if cost exceeds €20/month. |
| Billing model (if needed) | Web subscription + token (not App Store IAP) | Avoids 30% platform cut, no App Store billing review, acceptable under App Store guidelines when sync is framed as an external service. |
| Map tile provider | MapTiler (nautical style) + Esri (satellite) | OSM demo tile server is policy-prohibited for published apps. MapTiler free tier covers early scale; nautical chart style is relevant for sailors. |
| State management | Keep provider package — no migration | Existing ChangeNotifier providers are correct for the app's complexity level. Auth and subscription each add one new provider to MultiProvider. |
| Data model | `logbooks/{id}` → `boats/{boatId}` + `users/{uid}` | Enables Firestore Security Rules based on auth. No migration needed (no existing users). |
| Multi-device share | Keep code-based sharing via boatId | Preserves the elegant "share a boat" UX. Second device enters boatId after login; uid is added to `boats/{boatId}/members`. |
| Android state | Firebase not yet configured (placeholder) | Must run `flutterfire configure --platforms=android` and add `google-services.json` before Android testing. This is Phase 2.1 of the auth track. |
| Grace period for old users | None | Developer is the only current user. Clean cutover to new data model. |
| i18n sentinel fix | `"crew:"` prefix in logic, localised display string in ARB | `"Besatzung: "` is used as both display text and detection marker. Splitting these prevents localisation from breaking crew-change detection. |
""")

print('\\nAll wiki pages generated in:', os.path.abspath(WIKI_DIR))
print('\\nTo push to GitHub wiki, run locally:')
print('  git clone https://github.com/cpahab/Logbook.wiki.git /tmp/logbook-wiki')
print('  cp wiki/*.md /tmp/logbook-wiki/')
print('  cd /tmp/logbook-wiki && git add . && git commit -m "Add upgrade planning wiki" && git push')
