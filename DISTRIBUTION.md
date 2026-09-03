# Logbuch — Build & Distribution

## Android (recommended — no accounts, no expiry)

### Prerequisites (one-time setup)
- Android SDK installed at `~/Library/Android/sdk`
- `~/.zshrc` contains:
  ```
  export ANDROID_HOME=$HOME/Library/Android/sdk
  export PATH=$PATH:$ANDROID_HOME/platform-tools
  ```
- On her phone: **Settings → Apps → Special app access → Install unknown apps → Files → enable**

### Build

Open a fresh terminal (to load `~/.zshrc`), then:

```bash
cd ~/development/Logbook
flutter build apk --release --dart-define-from-file=.dart_defines
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

### Install via USB

Connect her phone via USB. First time: tap **Allow USB debugging** on the phone.

```bash
adb install build/app/outputs/flutter-apk/app-release.apk

# For updates (already installed):
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

### Install via file transfer (no cable)

```bash
open build/app/outputs/flutter-apk/
```

AirDrop or email the `app-release.apk` to her phone. She taps it → **Install**.

### Updates

1. Bump build number in `pubspec.yaml` (e.g. `1.0.0+1` → `1.0.0+2`)
2. Run `flutter build apk --release`
3. Transfer and install as above

---

## iOS — Run directly on a device (debug)

```bash
cd ~/development/Logbook
flutter devices                       # list connected/paired devices and their IDs
flutter run -d <device-id>
```

- Debug builds pick up `.dart_defines` automatically via
  `ios/Flutter/Debug.xcconfig` — no extra flag needed.
- Prefer a wired (USB) connection over wireless when possible — wireless
  debugging is slower and more prone to build-settings glitches.

---

## iOS — TestFlight (requires $99/year Apple Developer account)

### Prerequisites (one-time)
1. Register App ID `com.ziegler.logbook` at [developer.apple.com](https://developer.apple.com) → Identifiers
2. Create the app in [App Store Connect](https://appstoreconnect.apple.com) → My Apps → New App
3. In Xcode: open `ios/Runner.xcworkspace`, set Team in Signing & Capabilities

### Build

If first build after `flutter clean` (Firebase SPM packages are wiped):

```bash
# Re-download Firebase SPM packages first (~500MB, 5–15 min)
xcodebuild -resolvePackageDependencies \
  -workspace ~/development/Logbook/ios/Runner.xcworkspace \
  -scheme Runner \
  -clonedSourcePackagesDirPath ~/development/Logbook/build/ios/SourcePackages
```

Then build:

```bash
cd ~/development/Logbook
flutter build ipa --release --dart-define-from-file=.dart_defines
```

**Do not omit `--dart-define-from-file=.dart_defines`** — without it, `MAPTILER_KEY`
(see `lib/core/constants/map_config.dart`) compiles to an empty string, MapTiler
returns 403 for every tile/style request, and the map screens silently fall back
to their "no map data" placeholder in release builds (the error is only logged
when `kDebugMode` is true, so nothing shows up in a TestFlight tester's console
either).

Output: `build/ios/ipa/`

### Upload

Open Xcode → **Window → Organizer** → drag the `.ipa` in → **Distribute App** → **TestFlight & App Store**

### Invite tester

App Store Connect → your app → **TestFlight** → **Internal Testing** → add her Apple ID.
She installs the TestFlight app, then accepts the invite. Builds expire after **90 days**.

---

## iOS — Ad Hoc (requires $99/year Apple Developer account, no App Store Connect)

### Prerequisites (one-time per device)
1. Get her iPhone UDID: Xcode → Window → Devices and Simulators
2. Register it: [developer.apple.com](https://developer.apple.com) → Devices → +
3. Create Ad Hoc provisioning profile: Profiles → + → Ad Hoc → select `com.ziegler.logbook` → include her device → download

### Build

Create `ios/adhoc_options.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>ad-hoc</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
</dict>
</plist>
```

Then build:
```bash
flutter build ipa --release --export-options-plist=ios/adhoc_options.plist --dart-define-from-file=.dart_defines
```

### Install (Apple Configurator 2)

1. Install [Apple Configurator 2](https://apps.apple.com/app/apple-configurator-2/id1037126344) (free, Mac App Store)
2. Connect her iPhone via USB
3. Drag the `.ipa` onto her device — done

Ad Hoc profiles are valid for **1 year**. Re-register if she gets a new iPhone.

---

## Troubleshooting

### iOS: `Xcode build is missing expected TARGET_BUILD_DIR build setting`

If this appears right after a message like `Upgrading project.pbxproj` during
`flutter run`, just rerun the same command — the first run completes an Xcode
project format migration that the tool can't parse mid-build, and the retry
is fast.

### Android: `cannot find symbol FilePickerPlugin` build error

The auto-generated plugin registrant is stale. Delete it and rebuild:

```bash
rm android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java
flutter clean && flutter pub get
flutter build apk --release
```

---

## Account requirements summary

| Method | Developer account | Expiry |
|---|---|---|
| Android APK | None | Never |
| iOS TestFlight | $99/year | 90 days per build |
| iOS Ad Hoc | $99/year | 1 year |
| iOS free (Xcode sideload) | Free account | 7 days |
