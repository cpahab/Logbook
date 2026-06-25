// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Logbook';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get add => 'Add';

  @override
  String get remove => 'Remove';

  @override
  String get saveChanges => 'Save changes';

  @override
  String get apply => 'Apply';

  @override
  String get connect => 'Connect';

  @override
  String get close => 'Close';

  @override
  String get reset => 'Reset';

  @override
  String get copy => 'Copy';

  @override
  String get change => 'Change';

  @override
  String get update => 'Update';

  @override
  String get later => 'Later';

  @override
  String get on => 'On';

  @override
  String get off => 'Off';

  @override
  String get statSailingDays => 'Days';

  @override
  String get statDistance => 'Distance';

  @override
  String get statAvgSpeed => 'Avg Speed';

  @override
  String get statAvgSpeedUnderway => 'Avg Speed Underway';

  @override
  String get statMax => 'Max';

  @override
  String get homeNewDay => 'New Day';

  @override
  String get homeAddEntry => 'Add Entry';

  @override
  String get homeRecentEntries => 'Recent Entries';

  @override
  String get homeAllButton => 'All';

  @override
  String get homeEmpty => 'Logbook is empty';

  @override
  String get dayMenuOptions => 'Options';

  @override
  String get dayMenuChangeDate => 'Change date';

  @override
  String get dayMenuImportGpx => 'Import GPX';

  @override
  String get dayMenuExportGpx => 'Export GPX';

  @override
  String get dayMenuExportPdf => 'Export PDF';

  @override
  String get dayMenuDeleteGpx => 'Delete GPX';

  @override
  String get dayMenuDeleteDay => 'Delete day';

  @override
  String get dayNoEntry => 'No entry for this day';

  @override
  String get dayAddNotes => 'Add notes…';

  @override
  String get dayAddDiary => 'Add diary entry…';

  @override
  String get dayAddCrewMember => 'Add crew member';

  @override
  String get dayEditCrew => 'Edit crew';

  @override
  String get dayAddCrew => 'Add crew…';

  @override
  String get dayDeparturePort => 'Departure port';

  @override
  String get dayDestinationPort => 'Destination port';

  @override
  String get dayCaptureRoute => 'Capture leg…';

  @override
  String get daySaveRoute => 'Save leg';

  @override
  String get dayAddGpxTrack => 'Add GPX track…';

  @override
  String get dayAddPhotosTooltip => 'Add photos';

  @override
  String get dayAddPhotosEmpty => 'Add photos…';

  @override
  String get dayImportingPhotos => 'Importing photos…';

  @override
  String get dayFirstLogEntry => 'Add first log entry…';

  @override
  String get dayDeletePhoto => 'Delete photo?';

  @override
  String get dayEditLogEntry => 'Edit log entry';

  @override
  String get dayDeleteLogEntry => 'Delete log entry';

  @override
  String get dayUpdateVesselStatus => 'Update vessel status';

  @override
  String get dayAddLogEntry => 'Add entry';

  @override
  String get sectionNotes => 'Notes';

  @override
  String get sectionDiary => 'Diary';

  @override
  String get sectionCrew => 'Crew';

  @override
  String get sectionRoute => 'Route & Passage';

  @override
  String get sectionPhotos => 'Photos';

  @override
  String get sectionVesselStatus => 'Vessel Status';

  @override
  String get sectionLogEntries => 'Log Entries';

  @override
  String get labelEntry => 'Entry';

  @override
  String get labelDeparture => 'Departure';

  @override
  String get labelArrival => 'Arrival';

  @override
  String get labelProgress => 'Underway';

  @override
  String get labelSkipper => 'Skipper';

  @override
  String get labelCrewRole => 'Crew';

  @override
  String get dataCrewNote => 'Crew';

  @override
  String get dataCourse => 'Course';

  @override
  String get dataSpeed => 'Speed';

  @override
  String get dataWind => 'Wind';

  @override
  String get dataSea => 'Sea';

  @override
  String get dataWeather => 'Weather';

  @override
  String get dataMainSail => 'Main';

  @override
  String get dataJibSail => 'Jib';

  @override
  String get dataMotor => 'Engine';

  @override
  String get entryDialogTitleNew => 'New Entry';

  @override
  String get entryDialogTitleEdit => 'Edit Entry';

  @override
  String get entryDialogSectionTime => 'Chronometry';

  @override
  String get entryDialogSectionNav => 'Navigation';

  @override
  String get entryDialogSectionEnv => 'Environment';

  @override
  String get entryDialogSectionSails => 'Sails & Engine';

  @override
  String get entryDialogSectionRemarks => 'Remarks';

  @override
  String get entryDialogTimeLabel => 'Time';

  @override
  String get entryDialogCourseLabel => 'Course (°)';

  @override
  String get entryDialogSpeedLabel => 'Speed (kn)';

  @override
  String get entryDialogWindLabel => 'Wind Direction & Force';

  @override
  String get entryDialogSeaLabel => 'Sea';

  @override
  String get entryDialogSeaHint => 'e.g. Slight';

  @override
  String get entryDialogWeatherLabel => 'Weather';

  @override
  String get entryDialogWeatherHint => 'e.g. Sunny';

  @override
  String get entryDialogMainSailLabel => 'Main';

  @override
  String get entryDialogJibSailLabel => 'Jib';

  @override
  String get entryDialogMotorLabel => 'Engine';

  @override
  String get entryDialogKeelLabel => 'Keel';

  @override
  String get entryDialogRemarksHint => 'e.g. Observation, experience…';

  @override
  String get entryDialogSubmitNew => 'Log entry';

  @override
  String get crewDialogTitleAdd => 'Add crew member';

  @override
  String get crewDialogTitleEdit => 'Edit crew member';

  @override
  String get crewSectionIdentity => 'Identity';

  @override
  String get crewFieldFullName => 'Full name';

  @override
  String get crewFieldFullNameHint => 'e.g. Thomas Müller';

  @override
  String get crewSectionMedical => 'Medical info';

  @override
  String get crewFieldBloodGroup => 'Blood group';

  @override
  String get crewFieldBloodGroupHint => 'e.g. O+, A-';

  @override
  String get crewFieldAllergies => 'Allergies';

  @override
  String get crewFieldAllergiesHint => 'List known allergies…';

  @override
  String get crewFieldConditions => 'Conditions / Medication';

  @override
  String get crewFieldConditionsHint => 'e.g. Requires inhaler (asthma)…';

  @override
  String get crewSectionRemarks => 'Remarks';

  @override
  String get crewFieldRemarksHint => 'General notes about this person…';

  @override
  String get crewButtonAddToCrew => 'Add to crew';

  @override
  String get crewButtonRemoveFromCrew => 'Remove from crew';

  @override
  String get crewPickerTitle => 'Choose crew';

  @override
  String get crewPickerRemoveTitle => 'Remove from crew list?';

  @override
  String get crewPickerRemoveContent =>
      'will be permanently removed from the list.';

  @override
  String get crewPickerNewPerson => 'New person…';

  @override
  String get crewRosterTitle => 'Crew roster';

  @override
  String get crewRosterEmpty => 'No crew members yet';

  @override
  String get crewRosterEmptyHint => 'Tap + to add a person.';

  @override
  String get crewRosterNewPerson => 'New person';

  @override
  String get crewRosterRemoveTitle => 'Remove person?';

  @override
  String crewRosterRemoveContent(String name) {
    return '$name will be permanently removed from the crew roster.';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSubtitle => 'Configure navigation environment';

  @override
  String get settingsVesselSection => 'Vessel';

  @override
  String get settingsFieldName => 'Name';

  @override
  String get settingsFieldNameHint => 'e.g. S/V Adventure';

  @override
  String get settingsFieldCallSign => 'Call sign';

  @override
  String get settingsFieldCallSignHint => 'e.g. HB-9-XY';

  @override
  String get settingsAppearanceSection => 'Appearance';

  @override
  String get settingsThemeLabel => 'App theme';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsLanguageLabel => 'Language';

  @override
  String get settingsLanguageDe => 'Deutsch';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get settingsTrackFilterSection => 'Track filter';

  @override
  String get settingsFilterModeMooring => 'Mooring & Anchor';

  @override
  String get settingsFilterModeExact => 'Exact position';

  @override
  String get settingsStationaryLabel => 'Stationary detection';

  @override
  String get settingsStationaryDesc =>
      'Determines how moorings, anchor stops, and harbour visits are detected and displayed as anchor points — at the start, end, and during a voyage.';

  @override
  String get settingsMooringDesc =>
      'Mooring and anchor positions are shown as a single point. Even a wide anchor swing is collapsed to one point.';

  @override
  String get settingsExactPositionDesc =>
      'Only tightly clustered positions are considered stationary. Wide anchor circles remain visible — better for anchor watch.';

  @override
  String get settingsMinStopLabel => 'Min. stop duration';

  @override
  String get settingsMinUnit => 'min';

  @override
  String get settingsMinStopDesc =>
      'Minimum duration of a genuine stop (anchor, harbour). Short slow periods (tack, calm) are ignored.';

  @override
  String get settingsMaxAnchorLabel => 'Max. anchor swing';

  @override
  String get settingsMetersUnit => 'm';

  @override
  String get settingsMaxAnchorDesc =>
      'Maximum extent of a stop. Increase for wide overnight anchor swings (default: 30 m).';

  @override
  String get settingsColdStartLabel => 'Cold-start trim';

  @override
  String get settingsColdStartDesc =>
      'Removes inaccurate GPS fixes at the start of a track before the receiver has settled.';

  @override
  String get settingsTrimSharpnessLabel => 'Trim sharpness';

  @override
  String get settingsTrimSharpnessDesc =>
      'Lower value = more aggressive trimming. Default: 3.0.';

  @override
  String get settingsUnderwayLabel => 'Underway threshold';

  @override
  String get settingsUnderwayDesc =>
      'Minimum speed for the underway average. Drifting below this is not counted.';

  @override
  String get settingsPercentileLabel => 'Peak speed percentile';

  @override
  String get settingsPercentileDesc =>
      'p99 ignores the top 1 % of readings and suppresses GPS outliers. p100 = true maximum.';

  @override
  String get settingsShowRawTrackLabel => 'Show unfiltered track';

  @override
  String get settingsShowRawTrackDesc =>
      'Shows the raw GPX track in addition to the filtered track. Useful for diagnosing and tuning filter settings.';

  @override
  String get settingsCrewSection => 'Crew roster';

  @override
  String get settingsNoEntries => 'No entries yet';

  @override
  String get settingsNoLogbooks => 'No logbooks yet';

  @override
  String settingsPersonCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'People',
      one: 'Person',
    );
    return '$_temp0';
  }

  @override
  String get settingsSyncSection => 'Synchronisation';

  @override
  String get settingsLogbookCodeLabel => 'Logbook code';

  @override
  String get settingsLogbookCodeDesc =>
      'Enter this code on another device to share the same logbook.';

  @override
  String get settingsCodeCopied => 'Code copied.';

  @override
  String get settingsLogbookSyncLabel => 'Logbook Sync';

  @override
  String get settingsLogbookSyncDesc =>
      'Connect to another logbook via Firebase.';

  @override
  String get settingsEnterSyncCode => 'Enter sync code';

  @override
  String get settingsSynchronize => 'Synchronise';

  @override
  String get settingsInvalidCode => 'Invalid code.';

  @override
  String get settingsConnectLogbookTitle => 'Connect logbook';

  @override
  String settingsConnectLogbookContent(String code) {
    return 'This device will be connected to logbook \"$code\". All local entries will be deleted and replaced with cloud data.';
  }

  @override
  String get settingsConnectedAndSynced => 'Connected and synchronised.';

  @override
  String get settingsError => 'Error';

  @override
  String get settingsInviteCodeLabel => 'Your invite code';

  @override
  String get settingsInviteCodeDesc =>
      'Share this code with a crew member to give them access to this logbook.';

  @override
  String get settingsEnterInviteCode => 'Enter invite code';

  @override
  String get settingsConnectButton => 'Connect to logbook';

  @override
  String get settingsCodeNotFound => 'Code not found.';

  @override
  String get settingsAlreadyConnected => 'Already connected.';

  @override
  String get settingsConnected => 'Connected.';

  @override
  String get settingsSwitchLogbookTitle => 'Switch logbook?';

  @override
  String get settingsSwitchLogbookContent =>
      'Your local data will be replaced with the data from the connected logbook.';

  @override
  String get settingsScanQr => 'Scan QR Code';

  @override
  String get settingsScanTitle => 'Scan logbook QR code';

  @override
  String get tracksTitle => 'Voyage Tracks';

  @override
  String get tracksOneYear => '1 Year';

  @override
  String get tracksOneMonth => '1 Month';

  @override
  String get tracksOneWeek => '1 Week';

  @override
  String get tracksCustom => 'Custom';

  @override
  String get tracksZoomIn => 'Zoom in';

  @override
  String get tracksZoomOut => 'Zoom out';

  @override
  String get tracksShowAll => 'Show all tracks';

  @override
  String get tracksFullscreen => 'Fullscreen';

  @override
  String get tracksMapView => 'Map view';

  @override
  String get tracksSatelliteView => 'Satellite view';

  @override
  String get tracksNoTracks => 'No tracks available';

  @override
  String get tracksNoTracksInPeriod => 'No tracks in selected period';

  @override
  String get dayChangeDateTitle => 'Wrong date?';

  @override
  String dayChangeDateContent(String from, String to) {
    return 'The GPX track mainly contains data from $from, not $to.\n\nMove anyway?';
  }

  @override
  String get dayChangeDateConfirm => 'Move anyway';

  @override
  String get dayDateExistsError => 'An entry already exists for this date.';

  @override
  String get dayGpxNoWaypoints => 'GPX file contains no timestamped waypoints.';

  @override
  String dayGpxWrongDateContent(String from, String to) {
    return 'The GPX file mainly contains data from $from, not $to.\n\nImport anyway?';
  }

  @override
  String get dayGpxImportConfirm => 'Import anyway';

  @override
  String dayGpxImported(String date) {
    return 'GPX track imported for $date.';
  }

  @override
  String get dayGpxExported => 'GPX exported.';

  @override
  String get dayGpxDeleteTitle => 'Remove GPX track?';

  @override
  String get dayGpxDeleteContent => 'Delete GPX track for this day?';

  @override
  String get dayGpxRemoved => 'GPX track removed.';

  @override
  String get dayDeleteTitle => 'Delete day?';

  @override
  String dayDeleteContent(String date) {
    return 'All data for $date will be permanently deleted, including log entries and GPX track.';
  }

  @override
  String get dayEntryDeleted => 'Log entry deleted.';

  @override
  String get dayEntryUpdated => 'Log entry updated.';

  @override
  String get dayUndo => 'Undo';

  @override
  String get dayFreeTextHint => 'Free notes for this day…';

  @override
  String get dayDiaryHint => 'Diary entry for this day…';

  @override
  String get vesselStatusTitle => 'Vessel status';

  @override
  String get vesselOilLabel => 'Engine oil';

  @override
  String get vesselFuelLabel => 'Fuel';

  @override
  String get vesselFullLabel => 'Full';

  @override
  String get vesselEmptyLabel => 'Empty';

  @override
  String get vesselKeelDown => 'Down';

  @override
  String get vesselKeelUp => 'Up';

  @override
  String get gpsConsentTitle => 'GPS for Emergencies';

  @override
  String get gpsConsentContent =>
      'When activating the radio distress call, the app determines your GPS position and automatically enters it into the Mayday protocol so rescue services receive your exact location immediately. The position is used exclusively at this moment.';

  @override
  String get gpsConsentLater => 'Later';

  @override
  String get gpsConsentAllow => 'Allow access';

  @override
  String get authLoginTitle => 'Welcome back';

  @override
  String get authLoginSubtitle =>
      'Sign in to sync your logbook across devices.';

  @override
  String get authEmailLabel => 'E-mail';

  @override
  String get authEmailHint => 'captain@example.com';

  @override
  String get authPasswordLabel => 'Password';

  @override
  String get authPasswordHint => 'Your password';

  @override
  String get authSignIn => 'Sign in';

  @override
  String get authSignInWithGoogle => 'Continue with Google';

  @override
  String get authSignInWithApple => 'Continue with Apple';

  @override
  String get authOrDivider => 'or';

  @override
  String get authNoAccount => 'No account yet?';

  @override
  String get authRegisterLink => 'Register';

  @override
  String get authForgotPasswordLink => 'Forgot password?';

  @override
  String get authRegisterTitle => 'Create account';

  @override
  String get authRegisterSubtitle =>
      'Your logbook data stays on-device and syncs via your account.';

  @override
  String get authConfirmPasswordLabel => 'Confirm password';

  @override
  String get authConfirmPasswordHint => 'Repeat password';

  @override
  String get authPasswordMismatch => 'Passwords do not match.';

  @override
  String get authPasswordTooShort => 'Password must be at least 6 characters.';

  @override
  String get authCreateAccount => 'Create account';

  @override
  String get authAlreadyHaveAccount => 'Already have an account?';

  @override
  String get authSignInLink => 'Sign in';

  @override
  String get authForgotPasswordTitle => 'Reset password';

  @override
  String get authForgotPasswordDesc =>
      'Enter your e-mail address and we will send you a link to reset your password.';

  @override
  String get authSendResetEmail => 'Send reset link';

  @override
  String get authResetEmailSent => 'Reset link sent — check your inbox.';

  @override
  String get authBackToSignIn => 'Back to sign in';

  @override
  String get authSignOut => 'Sign out';

  @override
  String get authSignOutConfirm => 'Sign out of your account?';

  @override
  String get authSignOutConfirmDesc =>
      'Your logbook data remains on this device.';

  @override
  String get authSignOutOfflineWarning =>
      'You are currently offline. You will not be able to sign back in until a connection is available.';

  @override
  String get authErrorInvalidEmail => 'Invalid e-mail address.';

  @override
  String get authErrorWrongPassword => 'Incorrect password.';

  @override
  String get authErrorUserNotFound => 'No account found for this e-mail.';

  @override
  String get authErrorEmailInUse =>
      'An account with this e-mail already exists.';

  @override
  String get authErrorWeakPassword => 'Password is too weak.';

  @override
  String get authErrorGeneric => 'Something went wrong. Please try again.';

  @override
  String get authErrorNetworkFailed => 'No internet connection.';

  @override
  String get authErrorTooManyRequests =>
      'Too many attempts. Please try again later.';

  @override
  String get authErrorUserDisabled =>
      'This account has been disabled. Please contact support.';

  @override
  String get authErrorRequiresRecentLogin =>
      'Please sign out and sign back in before deleting your account.';

  @override
  String get settingsAccountSection => 'Account';

  @override
  String get settingsAccountSignedInAs => 'Signed in as';

  @override
  String get settingsAccountNotSignedIn => 'Not signed in';

  @override
  String get settingsAccountManage => 'Manage account';

  @override
  String get authDeleteAccount => 'Delete account';

  @override
  String get authDeleteAccountConfirm =>
      'Delete account? This cannot be undone.';

  @override
  String get authDeleteCleanupFailedTitle => 'Data cleanup incomplete';

  @override
  String get authDeleteCleanupFailedBody =>
      'Some of your data could not be removed from the server. Your account has not been deleted.\n\nPlease try again with a stable internet connection. If the problem persists, contact support and we will manually remove your data.';

  @override
  String get settingsLogbooksSection => 'Logbooks';

  @override
  String get settingsMyLogbooks => 'My Logbooks';

  @override
  String get settingsRoleOwner => 'owner';

  @override
  String get settingsRoleGuest => 'contributor';

  @override
  String get settingsNewLogbook => 'New logbook';

  @override
  String get settingsNewLogbookTitle => 'Create new logbook';

  @override
  String get settingsNewLogbookHint => 'Logbook name';

  @override
  String get settingsRename => 'Rename';

  @override
  String get settingsShare => 'Share';

  @override
  String get settingsDeleteLogbook => 'Delete logbook';

  @override
  String get settingsLeaveLogbook => 'Leave logbook';

  @override
  String get settingsShareCurrentLogbook => 'Share Current Logbook';

  @override
  String get settingsShowQrCode => 'Show QR code';

  @override
  String get settingsScanOrEnterCode => 'Scan QR / Enter code';

  @override
  String get settingsManageGuests => 'Manage contributors';

  @override
  String get settingsNoGuests => 'No contributors';

  @override
  String settingsSwitchTo(String name) {
    return 'Switch to \"$name\"?';
  }

  @override
  String settingsDeleteLogbookConfirm(String name) {
    return 'Delete \"$name\"? This cannot be undone.';
  }

  @override
  String settingsLeaveLogbookConfirm(String name) {
    return 'Leave \"$name\"?';
  }

  @override
  String settingsJoinContent(String name) {
    return 'Join \"$name\"? Your current logbook stays accessible — this adds a new one.';
  }

  @override
  String settingsJoinedLogbook(String name) {
    return 'Connected to \"$name\".';
  }

  @override
  String get offlineBanner => 'Offline — changes saved locally';

  @override
  String get done => 'Done';

  @override
  String get save => 'Save';

  @override
  String get emergencyGuideTitle => 'Distress Signal Guide';

  @override
  String get emergencyGuideIntro =>
      'Quick reference guide for International Maritime Distress Signals. Ensure visibility and clear communication during an emergency.';

  @override
  String get emergencyVisualSignals => 'Visual Signals';

  @override
  String get emergencySoundSignals => 'Sound Signals';

  @override
  String get emergencyElectronicSignals => 'Electronic Signals';

  @override
  String get emergencyPyrotechnicTitle => 'Pyrotechnic Signals';

  @override
  String get emergencyPyrotechnicSubtitle =>
      'Red flare (handheld/parachute) or Orange smoke.';

  @override
  String get emergencyHighVisBadge => 'HIGH VIS';

  @override
  String get emergencyHandSignalTitle => 'Hand Signals';

  @override
  String get emergencyHandSignalSubtitle =>
      'Slowly and repeatedly raising and lowering arms outstretched to each side.';

  @override
  String get emergencyFlagSignalTitle => 'Flag Signals';

  @override
  String get emergencyFlagSignalSubtitle =>
      'Square flag having above or below it a ball or anything resembling a ball, or flags November over Charlie.';

  @override
  String get emergencyGunTitle => 'Gun/Explosive';

  @override
  String get emergencyGunSubtitle => 'Fired at intervals of about a minute.';

  @override
  String get emergencyFoghornTitle => 'Foghorn';

  @override
  String get emergencyFoghornSubtitle =>
      'Continuous sounding with any fog-signaling apparatus.';

  @override
  String get emergencyEpirbTitle => 'EPIRB / PLB';

  @override
  String get emergencyEpirbSubtitle =>
      'Emergency Position Indicating Radio Beacon. Signals 406 MHz to COSPAS-SARSAT satellites.';

  @override
  String get emergencySartTitle => 'SART';

  @override
  String get emergencySartSubtitle =>
      'Search and Rescue Transponder. Shows as a line of 12 dots on nearby X-band radars.';

  @override
  String get emergencyRadioProtocolLabel => 'Radio Protocol (MAYDAY)';

  @override
  String get emergencyRadioProtocolTip =>
      'VHF Channel 16. State \"MAYDAY\" three times, followed by Vessel Name and Position.';

  @override
  String get emergencyOpenChecklist => 'OPEN RADIO CHECKLIST';

  @override
  String get emergencyManifestTitle => 'Emergency Manifest';

  @override
  String get maydayScreenTitle => 'Radio Protocol';

  @override
  String get maydayStateThreeTimes => '(say three times)';

  @override
  String get emergencyDistressGuideSubtitle =>
      'Visual, sound & electronic signals';

  @override
  String get emergencyUrgentProcedure => 'URGENT PROCEDURE';

  @override
  String get emergencyFollowScript =>
      'Follow this script exactly. Transmit on VHF Channel 16.';

  @override
  String get emergencyDscAction1 =>
      'Lift the red flap over the distress button';

  @override
  String get emergencyDscAction2 =>
      'Press and hold (3–5 seconds, varies by radio) until the alert is sent';

  @override
  String get emergencyDscWait =>
      'Wait for the radio to switch automatically to Channel 16';

  @override
  String get emergencyIdentifyVessel => 'Identify your vessel clearly:';

  @override
  String get emergencyPositionUnavailable => 'Position unavailable';

  @override
  String get emergencyAcquiringGps => 'Acquiring GPS…';

  @override
  String get emergencyCriticalTips => 'Critical Protocol Tips';

  @override
  String get emergencyTipCalmTitle => 'Stay Calm:';

  @override
  String get emergencyTipCalmBody =>
      'Take a deep breath before speaking. Panic makes your transmission unintelligible.';

  @override
  String get emergencyTipEnunciateTitle => 'Enunciate:';

  @override
  String get emergencyTipEnunciateBody =>
      'Speak slowly and clearly. Pronounce numbers individually (e.g., \"Five-Zero\" for 50).';

  @override
  String get emergencyTipListenTitle => 'Listen:';

  @override
  String get emergencyTipListenBody =>
      'Release the transmit button and wait 15 seconds for an acknowledgement before repeating.';

  @override
  String get emergencyManifestEditDoneTooltip => 'Done';

  @override
  String get emergencyManifestEditPageTooltip => 'Edit page';

  @override
  String get emergencyProtocolBadge => 'PROTOCOL';

  @override
  String get emergencyRadioProtocolShort => 'Radio Protocol\n(MAYDAY)';

  @override
  String get emergencyVisualAidBadge => 'VISUAL AID';

  @override
  String get emergencyGuideShort => 'Distress Signal\nGuide';

  @override
  String get emergencyContactsSection => 'EMERGENCY CONTACTS';

  @override
  String get emergencyVesselSafetySection => 'VESSEL SAFETY INFO';

  @override
  String get emergencyFrequenciesSection => 'COAST GUARD FREQUENCIES';

  @override
  String get emergencyCrewMedicalSection => 'CREW MEDICAL OVERVIEW';

  @override
  String get emergencyCrewAutoNote =>
      'Automatically taken from the most recent log entry.\nCrew data is managed in the logbook.';

  @override
  String get emergencyNoContacts => 'No emergency contacts added.';

  @override
  String get emergencyAddContactTitle => 'Add emergency contact';

  @override
  String get emergencyContactNameLabel => 'Name';

  @override
  String get emergencyContactRoleHint => 'Role (e.g. Spouse, Doctor)';

  @override
  String get emergencyContactPhoneLabel => 'Phone number';

  @override
  String get emergencyEditContactTitle => 'Edit contact';

  @override
  String get emergencyNoSafetyData => 'No safety data recorded.';

  @override
  String get emergencyBloodBadge => 'BLOOD';

  @override
  String get emergencyNoFrequencies => 'No frequencies configured.';

  @override
  String get emergencyAddFrequencyTitle => 'Add Frequency';

  @override
  String get emergencyEditFrequencyTitle => 'Edit Frequency';

  @override
  String get emergencyFrequencyChannelLabel => 'Channel';

  @override
  String get emergencyFrequencyDescLabel => 'Description';

  @override
  String get emergencyNoCrewHint => 'No crew members added for today.';

  @override
  String get emergencyOpenDayEntry => 'Open day entry';

  @override
  String get emergencyLifeRaft => 'Life Raft';

  @override
  String get emergencyEpirbLocation => 'EPIRB Location';

  @override
  String get emergencyFireSuppression => 'Fire Suppression';

  @override
  String get navJournal => 'Journal';

  @override
  String get navSafety => 'Safety';

  @override
  String get offlineLabel => 'Offline';

  @override
  String get crewBloodGroupPrefix => 'BG';

  @override
  String get sailFull => 'Full sail';

  @override
  String get sailReef1 => '1st reef';

  @override
  String get sailReef2 => '2nd reef';

  @override
  String get sailLowered => 'Lowered';

  @override
  String get sailFurled => 'Furled';

  @override
  String get pdfVoyageLog => 'VOYAGE LOG';

  @override
  String get pdfNotes => 'NOTES';

  @override
  String get pdfDate => 'DATE';

  @override
  String get pdfDistance => 'DISTANCE';

  @override
  String get pdfAvgSpeed => 'AVG SPEED';

  @override
  String get pdfMax => 'MAX';

  @override
  String get pdfDuration => 'UNDERWAY';

  @override
  String get pdfStops => 'STOPS';

  @override
  String get pdfStatistics => 'STATISTICS';

  @override
  String get pdfCrew => 'CREW';

  @override
  String get pdfSkipper => 'SKIPPER';

  @override
  String get pdfCrewMember => 'CREW';

  @override
  String get pdfLogEntries => 'LOG ENTRIES';

  @override
  String get pdfTimeCol => 'Time';

  @override
  String get pdfCourseCol => 'Hdg';

  @override
  String get pdfWindCol => 'Wind';

  @override
  String get pdfSeaCol => 'Sea';

  @override
  String get pdfMotorCol => 'Engine';

  @override
  String get pdfSailsCol => 'Sails';

  @override
  String get pdfRemarksCol => 'Remarks';

  @override
  String get pdfMotorOn => 'ON';

  @override
  String get pdfMotorOff => 'OFF';

  @override
  String get pdfTrackMap => 'COURSE & TRACK';

  @override
  String pdfPassageTo(String destination) {
    return 'Passage to $destination';
  }

  @override
  String pdfDepartureFrom(String origin) {
    return 'Departure from $origin';
  }

  @override
  String pdfPageOf(int page, int total) {
    return 'Page $page of $total';
  }

  @override
  String get pdfLocale => 'en_US';
}
