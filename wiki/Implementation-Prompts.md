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
