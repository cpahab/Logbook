# To dos

## Release blockers remain

Android release builds are still signed with the debug key.
[build.gradle.kts (line 29)](/Users/ursziegler/development/Logbook/android/app/build.gradle.kts:29)
Production maps currently use public OSM/Esri testing endpoints.
[map_config.dart (line 41)](/Users/ursziegler/development/Logbook/lib/core/constants/map_config.dart:41)
PDF attribution still says MapTiler while those endpoints are disabled.
[pdf_exporter.dart (line 1031)](/Users/ursziegler/development/Logbook/lib/features/home/utils/pdf_exporter.dart:1031)
Privacy policy, crash reporting, and critical widget-flow coverage are still missing.
