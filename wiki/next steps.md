# Highest-priority issues

## Critical: Firestore membership rules are bypassable

The broad nested rule allows any existing member to write every subcollection, including members, despite the narrower owner-only rules below it. Firestore overlapping matches are additive. A member can therefore alter membership and roles.
[firestore.rules (line 45)](/Users/ursziegler/development/Logbook/firestore.rules:45)

## Critical: Firebase Storage has no membership check

Any authenticated user who knows a logbookId can read or write its GPX files and photos.
[storage.rules (line 9)](/Users/ursziegler/development/Logbook/storage.rules:9)

## High: Offline deletion is not durable

Entries and tracks are removed locally first, while cloud deletes are fire-and-forget. If the app is offline or the delete fails, the next sync can download the deleted data again because there are no tombstones.
[home_repository.dart (line 495)](/Users/ursziegler/development/Logbook/lib/features/home/data/home_repository.dart:495)
[home_repository.dart (line 658)](/Users/ursziegler/development/Logbook/lib/features/home/data/home_repository.dart:658)

## High: Backup restore does not actually replace cloud data

Restore clears Hive and uploads restored records, but never deletes cloud entries/tracks absent from the backup. Those old records can reappear through listeners or storage sync.
[backup_service.dart (line 265)](/Users/ursziegler/development/Logbook/lib/core/services/backup_service.dart:265)
[home_repository.dart (line 555)](/Users/ursziegler/development/Logbook/lib/features/home/data/home_repository.dart:555)

## Release blockers remain

Android release builds are still signed with the debug key.
[build.gradle.kts (line 29)](/Users/ursziegler/development/Logbook/android/app/build.gradle.kts:29)
Production maps currently use public OSM/Esri testing endpoints.
[map_config.dart (line 41)](/Users/ursziegler/development/Logbook/lib/core/constants/map_config.dart:41)
PDF attribution still says MapTiler while those endpoints are disabled.
[pdf_exporter.dart (line 1031)](/Users/ursziegler/development/Logbook/lib/features/home/utils/pdf_exporter.dart:1031)
Privacy policy, crash reporting, and critical widget-flow coverage are still missing.

## Secondary concerns

PDF fonts are fetched at runtime; the test suite showed fallback-to-Helvetica warnings when offline.
[pdf_exporter.dart (line 357)](/Users/ursziegler/development/Logbook/lib/features/home/utils/pdf_exporter.dart:357)
day_detail_screen.dart is 4,513 lines and settings_screen.dart is 3,404 lines; maintainability will become difficult.
The documented Firebase-failure offline fallback is fragile because AuthService still eagerly depends on FirebaseAuth.instance.
[auth_service.dart (line 10)](/Users/ursziegler/development/Logbook/lib/core/services/auth_service.dart:10)
[router.dart (line 42)](/Users/ursziegler/development/Logbook/lib/app/router.dart:42)

## Recommended order

Fix Firestore/Storage rules first, add tombstone-based sync and cloud-aware restore, then complete signing, map licensing, privacy, and production observability
