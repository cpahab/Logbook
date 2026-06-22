// GENERATED CODE – DO NOT EDIT BY HAND
// Regenerate with: flutter gen-l10n  (runs automatically on flutter pub get)
// ignore_for_file: type=lint

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale);

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
  ];

  // ── Common ────────────────────────────────────────────────────────
  String get cancel;
  String get delete;
  String get edit;
  String get add;
  String get remove;
  String get saveChanges;
  String get apply;
  String get connect;
  String get close;
  String get reset;
  String get copy;
  String get change;
  String get update;
  String get later;
  String get on;
  String get off;

  // ── Stats ─────────────────────────────────────────────────────────
  String get statSailingDays;
  String get statDays;
  String get statDistance;
  String get statAvgSpeed;
  String get statAvgSpeedUnderway;
  String get statMax;

  // ── Home ──────────────────────────────────────────────────────────
  String get homeNewDay;
  String get homeAddEntry;
  String get homeRecentEntries;
  String get homeAllButton;
  String get homeEmpty;

  // ── Day Detail ───────────────────────────────────────────────────
  String get dayMenuOptions;
  String get dayMenuChangeDate;
  String get dayMenuImportGpx;
  String get dayMenuExportGpx;
  String get dayMenuExportPdf;
  String get dayMenuDeleteGpx;
  String get dayMenuDeleteDay;
  String get dayNoEntry;
  String get dayAddNotes;
  String get dayAddDiary;
  String get dayAddCrewMember;
  String get dayEditCrew;
  String get dayAddCrew;
  String get dayDeparturePort;
  String get dayDestinationPort;
  String get dayCaptureRoute;
  String get daySaveRoute;
  String get dayAddGpxTrack;
  String get dayAddPhotosTooltip;
  String get dayAddPhotosEmpty;
  String get dayImportingPhotos;
  String get dayFirstLogEntry;
  String get dayDeletePhoto;
  String get dayEditLogEntry;
  String get dayDeleteLogEntry;
  String get dayUpdateVesselStatus;
  String get dayAddLogEntry;

  // ── Sections ──────────────────────────────────────────────────────
  String get sectionNotes;
  String get sectionDiary;
  String get sectionCrew;
  String get sectionRoute;
  String get sectionPhotos;
  String get sectionVesselStatus;
  String get sectionLogEntries;

  // ── Labels ────────────────────────────────────────────────────────
  String get labelEntry;
  String get labelDeparture;
  String get labelArrival;
  String get labelProgress;
  String get labelSkipper;
  String get labelCrewRole;

  // ── Data labels ───────────────────────────────────────────────────
  String get dataCrewNote;
  String get dataCourse;
  String get dataSpeed;
  String get dataWind;
  String get dataSea;
  String get dataWeather;
  String get dataMainSail;
  String get dataJibSail;
  String get dataMotor;

  // ── Entry Dialog ──────────────────────────────────────────────────
  String get entryDialogTitleNew;
  String get entryDialogTitleEdit;
  String get entryDialogSectionTime;
  String get entryDialogSectionNav;
  String get entryDialogSectionEnv;
  String get entryDialogSectionSails;
  String get entryDialogSectionRemarks;
  String get entryDialogTimeLabel;
  String get entryDialogCourseLabel;
  String get entryDialogSpeedLabel;
  String get entryDialogWindLabel;
  String get entryDialogSeaLabel;
  String get entryDialogSeaHint;
  String get entryDialogWeatherLabel;
  String get entryDialogWeatherHint;
  String get entryDialogMainSailLabel;
  String get entryDialogJibSailLabel;
  String get entryDialogMotorLabel;
  String get entryDialogKeelLabel;
  String get entryDialogRemarksHint;
  String get entryDialogSubmitNew;

  // ── Crew Dialog ───────────────────────────────────────────────────
  String get crewDialogTitleAdd;
  String get crewDialogTitleEdit;
  String get crewSectionIdentity;
  String get crewFieldFullName;
  String get crewFieldFullNameHint;
  String get crewSectionMedical;
  String get crewFieldBloodGroup;
  String get crewFieldBloodGroupHint;
  String get crewFieldAllergies;
  String get crewFieldAllergiesHint;
  String get crewFieldConditions;
  String get crewFieldConditionsHint;
  String get crewSectionRemarks;
  String get crewFieldRemarksHint;
  String get crewButtonAddToCrew;
  String get crewButtonRemoveFromCrew;

  // ── Crew Picker ───────────────────────────────────────────────────
  String get crewPickerTitle;
  String get crewPickerRemoveTitle;
  String get crewPickerRemoveContent;
  String get crewPickerNewPerson;

  // ── Crew Roster ───────────────────────────────────────────────────
  String get crewRosterTitle;
  String get crewRosterEmpty;
  String get crewRosterEmptyHint;
  String get crewRosterNewPerson;
  String get crewRosterRemoveTitle;
  String crewRosterRemoveContent(String name);

  // ── Settings ──────────────────────────────────────────────────────
  String get settingsTitle;
  String get settingsSubtitle;
  String get settingsVesselSection;
  String get settingsFieldName;
  String get settingsFieldNameHint;
  String get settingsFieldCallSign;
  String get settingsFieldCallSignHint;
  String get settingsAppearanceSection;
  String get settingsThemeLabel;
  String get settingsThemeSystem;
  String get settingsThemeLight;
  String get settingsThemeDark;
  String get settingsLanguageLabel;
  String get settingsLanguageDe;
  String get settingsLanguageEn;
  String get settingsTrackFilterSection;
  String get settingsFilterModeMooring;
  String get settingsFilterModeExact;
  String get settingsStationaryLabel;
  String get settingsStationaryDesc;
  String get settingsMooringDesc;
  String get settingsExactPositionDesc;
  String get settingsMinStopLabel;
  String get settingsMinUnit;
  String get settingsMinStopDesc;
  String get settingsMaxAnchorLabel;
  String get settingsMetersUnit;
  String get settingsMaxAnchorDesc;
  String get settingsColdStartLabel;
  String get settingsColdStartDesc;
  String get settingsTrimSharpnessLabel;
  String get settingsTrimSharpnessDesc;
  String get settingsUnderwayLabel;
  String get settingsUnderwayDesc;
  String get settingsPercentileLabel;
  String get settingsPercentileDesc;
  String get settingsShowRawTrackLabel;
  String get settingsShowRawTrackDesc;
  String get settingsCrewSection;
  String get settingsNoEntries;
  String settingsPersonCount(int count);
  String get settingsSyncSection;
  String get settingsLogbookCodeLabel;
  String get settingsLogbookCodeDesc;
  String get settingsCodeCopied;
  String get settingsLogbookSyncLabel;
  String get settingsLogbookSyncDesc;
  String get settingsEnterSyncCode;
  String get settingsSynchronize;
  String get settingsInvalidCode;
  String get settingsConnectLogbookTitle;
  String settingsConnectLogbookContent(String code);
  String get settingsConnectedAndSynced;
  String get settingsError;

  // ── Tracks ────────────────────────────────────────────────────────
  String get tracksTitle;
  String get tracksOneYear;
  String get tracksOneMonth;
  String get tracksOneWeek;
  String get tracksCustom;
  String get tracksZoomIn;
  String get tracksZoomOut;
  String get tracksShowAll;
  String get tracksFullscreen;
  String get tracksMapView;
  String get tracksSatelliteView;
  String get tracksNoTracks;
  String get tracksNoTracksInPeriod;

  // ── Day Detail operations ─────────────────────────────────────────
  String get dayChangeDateTitle;
  String dayChangeDateContent(String from, String to);
  String get dayChangeDateConfirm;
  String get dayDateExistsError;
  String get dayGpxNoWaypoints;
  String dayGpxWrongDateContent(String from, String to);
  String get dayGpxImportConfirm;
  String dayGpxImported(String date);
  String get dayGpxExported;
  String get dayGpxDeleteTitle;
  String get dayGpxDeleteContent;
  String get dayGpxRemoved;
  String get dayDeleteTitle;
  String dayDeleteContent(String date);
  String get dayEntryDeleted;
  String get dayEntryUpdated;
  String get dayUndo;
  String get dayFreeTextHint;
  String get dayDiaryHint;
  // ── Vessel Status ─────────────────────────────────────────────────
  String get vesselStatusTitle;
  String get vesselOilLabel;
  String get vesselFuelLabel;
  String get vesselFullLabel;
  String get vesselEmptyLabel;

  // ── GPS Consent ───────────────────────────────────────────────────
  String get gpsConsentTitle;
  String get gpsConsentContent;
  String get gpsConsentLater;
  String get gpsConsentAllow;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(
        lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }
  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale".',
  );
}
