import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In de, this message translates to:
  /// **'Logbuch'**
  String get appTitle;

  /// No description provided for @cancel.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get cancel;

  /// No description provided for @mapLoadRetry.
  ///
  /// In de, this message translates to:
  /// **'Erneut versuchen'**
  String get mapLoadRetry;

  /// No description provided for @delete.
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In de, this message translates to:
  /// **'Bearbeiten'**
  String get edit;

  /// No description provided for @add.
  ///
  /// In de, this message translates to:
  /// **'Hinzufügen'**
  String get add;

  /// No description provided for @remove.
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get remove;

  /// No description provided for @undo.
  ///
  /// In de, this message translates to:
  /// **'Rückgängig'**
  String get undo;

  /// No description provided for @saveChanges.
  ///
  /// In de, this message translates to:
  /// **'Änderungen speichern'**
  String get saveChanges;

  /// No description provided for @apply.
  ///
  /// In de, this message translates to:
  /// **'Übernehmen'**
  String get apply;

  /// No description provided for @connect.
  ///
  /// In de, this message translates to:
  /// **'Verbinden'**
  String get connect;

  /// No description provided for @close.
  ///
  /// In de, this message translates to:
  /// **'Schließen'**
  String get close;

  /// No description provided for @reset.
  ///
  /// In de, this message translates to:
  /// **'Zurücksetzen'**
  String get reset;

  /// No description provided for @change.
  ///
  /// In de, this message translates to:
  /// **'Ändern'**
  String get change;

  /// No description provided for @update.
  ///
  /// In de, this message translates to:
  /// **'Aktualisieren'**
  String get update;

  /// No description provided for @later.
  ///
  /// In de, this message translates to:
  /// **'Später'**
  String get later;

  /// No description provided for @statSailingDays.
  ///
  /// In de, this message translates to:
  /// **'Tage'**
  String get statSailingDays;

  /// No description provided for @statDistance.
  ///
  /// In de, this message translates to:
  /// **'Distanz'**
  String get statDistance;

  /// No description provided for @statAvgSpeedUnderway.
  ///
  /// In de, this message translates to:
  /// **'Ø Geschwindigkeit in Fahrt'**
  String get statAvgSpeedUnderway;

  /// No description provided for @statMax.
  ///
  /// In de, this message translates to:
  /// **'Max'**
  String get statMax;

  /// No description provided for @statDuration.
  ///
  /// In de, this message translates to:
  /// **'Fahrzeit'**
  String get statDuration;

  /// No description provided for @homeNewDay.
  ///
  /// In de, this message translates to:
  /// **'Neuer Tag'**
  String get homeNewDay;

  /// No description provided for @homeAddEntry.
  ///
  /// In de, this message translates to:
  /// **'Eintrag hinzufügen'**
  String get homeAddEntry;

  /// No description provided for @homeRecentEntries.
  ///
  /// In de, this message translates to:
  /// **'Letzte Einträge'**
  String get homeRecentEntries;

  /// No description provided for @homeAllButton.
  ///
  /// In de, this message translates to:
  /// **'Alle'**
  String get homeAllButton;

  /// No description provided for @homeEmpty.
  ///
  /// In de, this message translates to:
  /// **'Logbuch ist leer'**
  String get homeEmpty;

  /// No description provided for @dayMenuOptions.
  ///
  /// In de, this message translates to:
  /// **'Optionen'**
  String get dayMenuOptions;

  /// No description provided for @dayMenuChangeDate.
  ///
  /// In de, this message translates to:
  /// **'Datum ändern'**
  String get dayMenuChangeDate;

  /// No description provided for @dayMenuImportGpx.
  ///
  /// In de, this message translates to:
  /// **'GPX importieren'**
  String get dayMenuImportGpx;

  /// No description provided for @dayMenuExportGpx.
  ///
  /// In de, this message translates to:
  /// **'GPX exportieren'**
  String get dayMenuExportGpx;

  /// No description provided for @dayMenuExportPdf.
  ///
  /// In de, this message translates to:
  /// **'PDF exportieren'**
  String get dayMenuExportPdf;

  /// No description provided for @dayMenuDeleteGpx.
  ///
  /// In de, this message translates to:
  /// **'GPX löschen'**
  String get dayMenuDeleteGpx;

  /// No description provided for @dayMenuDeleteDay.
  ///
  /// In de, this message translates to:
  /// **'Tag löschen'**
  String get dayMenuDeleteDay;

  /// No description provided for @dayNoEntry.
  ///
  /// In de, this message translates to:
  /// **'Kein Eintrag für diesen Tag'**
  String get dayNoEntry;

  /// No description provided for @dayAddNotes.
  ///
  /// In de, this message translates to:
  /// **'Notizen hinzufügen…'**
  String get dayAddNotes;

  /// No description provided for @dayAddDiary.
  ///
  /// In de, this message translates to:
  /// **'Tagebucheintrag hinzufügen…'**
  String get dayAddDiary;

  /// No description provided for @dayAddCrewMember.
  ///
  /// In de, this message translates to:
  /// **'Besatzungsmitglied hinzufügen'**
  String get dayAddCrewMember;

  /// No description provided for @dayEditCrew.
  ///
  /// In de, this message translates to:
  /// **'Besatzung bearbeiten'**
  String get dayEditCrew;

  /// No description provided for @dayAddCrew.
  ///
  /// In de, this message translates to:
  /// **'Besatzung hinzufügen…'**
  String get dayAddCrew;

  /// No description provided for @dayDeparturePort.
  ///
  /// In de, this message translates to:
  /// **'Starthafen'**
  String get dayDeparturePort;

  /// No description provided for @dayDestinationPort.
  ///
  /// In de, this message translates to:
  /// **'Zielhafen'**
  String get dayDestinationPort;

  /// No description provided for @dayCaptureRoute.
  ///
  /// In de, this message translates to:
  /// **'Etappe erfassen…'**
  String get dayCaptureRoute;

  /// No description provided for @daySaveRoute.
  ///
  /// In de, this message translates to:
  /// **'Etappe speichern'**
  String get daySaveRoute;

  /// No description provided for @dayAddGpxTrack.
  ///
  /// In de, this message translates to:
  /// **'GPX Track hinzufügen…'**
  String get dayAddGpxTrack;

  /// No description provided for @dayAddPhotosTooltip.
  ///
  /// In de, this message translates to:
  /// **'Fotos hinzufügen'**
  String get dayAddPhotosTooltip;

  /// No description provided for @dayAddPhotosEmpty.
  ///
  /// In de, this message translates to:
  /// **'Fotos hinzufügen…'**
  String get dayAddPhotosEmpty;

  /// No description provided for @dayImportingPhotos.
  ///
  /// In de, this message translates to:
  /// **'Fotos werden importiert…'**
  String get dayImportingPhotos;

  /// No description provided for @dayFirstLogEntry.
  ///
  /// In de, this message translates to:
  /// **'Ersten Logeintrag hinzufügen…'**
  String get dayFirstLogEntry;

  /// No description provided for @dayDeletePhoto.
  ///
  /// In de, this message translates to:
  /// **'Foto löschen?'**
  String get dayDeletePhoto;

  /// No description provided for @dayEditLogEntry.
  ///
  /// In de, this message translates to:
  /// **'Logeintrag bearbeiten'**
  String get dayEditLogEntry;

  /// No description provided for @dayDeleteLogEntry.
  ///
  /// In de, this message translates to:
  /// **'Logeintrag löschen'**
  String get dayDeleteLogEntry;

  /// No description provided for @dayUpdateVesselStatus.
  ///
  /// In de, this message translates to:
  /// **'Schiffsstatus aktualisieren'**
  String get dayUpdateVesselStatus;

  /// No description provided for @dayAddLogEntry.
  ///
  /// In de, this message translates to:
  /// **'Eintrag hinzufügen'**
  String get dayAddLogEntry;

  /// No description provided for @sectionNotes.
  ///
  /// In de, this message translates to:
  /// **'Notizen'**
  String get sectionNotes;

  /// No description provided for @sectionDiary.
  ///
  /// In de, this message translates to:
  /// **'Tagebuch'**
  String get sectionDiary;

  /// No description provided for @sectionCrew.
  ///
  /// In de, this message translates to:
  /// **'Besatzung'**
  String get sectionCrew;

  /// No description provided for @sectionRoute.
  ///
  /// In de, this message translates to:
  /// **'Route & Passage'**
  String get sectionRoute;

  /// No description provided for @sectionPhotos.
  ///
  /// In de, this message translates to:
  /// **'Fotos'**
  String get sectionPhotos;

  /// No description provided for @sectionVesselStatus.
  ///
  /// In de, this message translates to:
  /// **'Schiffsstatus'**
  String get sectionVesselStatus;

  /// No description provided for @sectionLogEntries.
  ///
  /// In de, this message translates to:
  /// **'Chronologische Einträge'**
  String get sectionLogEntries;

  /// No description provided for @labelEntry.
  ///
  /// In de, this message translates to:
  /// **'Eintrag'**
  String get labelEntry;

  /// No description provided for @labelDeparture.
  ///
  /// In de, this message translates to:
  /// **'Abfahrt'**
  String get labelDeparture;

  /// No description provided for @labelArrival.
  ///
  /// In de, this message translates to:
  /// **'Ankunft'**
  String get labelArrival;

  /// No description provided for @labelProgress.
  ///
  /// In de, this message translates to:
  /// **'Verlauf'**
  String get labelProgress;

  /// No description provided for @labelSkipper.
  ///
  /// In de, this message translates to:
  /// **'Skipper'**
  String get labelSkipper;

  /// No description provided for @labelCrewRole.
  ///
  /// In de, this message translates to:
  /// **'Besatzung'**
  String get labelCrewRole;

  /// No description provided for @dataCrewNote.
  ///
  /// In de, this message translates to:
  /// **'Besatzung'**
  String get dataCrewNote;

  /// No description provided for @dataCourse.
  ///
  /// In de, this message translates to:
  /// **'Kurs'**
  String get dataCourse;

  /// No description provided for @dataSpeed.
  ///
  /// In de, this message translates to:
  /// **'Fahrt'**
  String get dataSpeed;

  /// No description provided for @dataWind.
  ///
  /// In de, this message translates to:
  /// **'Wind'**
  String get dataWind;

  /// No description provided for @dataSea.
  ///
  /// In de, this message translates to:
  /// **'See'**
  String get dataSea;

  /// No description provided for @dataWeather.
  ///
  /// In de, this message translates to:
  /// **'Wetter'**
  String get dataWeather;

  /// No description provided for @dataTemperature.
  ///
  /// In de, this message translates to:
  /// **'Temp.'**
  String get dataTemperature;

  /// No description provided for @dataPressure.
  ///
  /// In de, this message translates to:
  /// **'Luftdruck'**
  String get dataPressure;

  /// No description provided for @dataPosition.
  ///
  /// In de, this message translates to:
  /// **'Position'**
  String get dataPosition;

  /// No description provided for @entryDialogTitleNew.
  ///
  /// In de, this message translates to:
  /// **'Neuer Eintrag'**
  String get entryDialogTitleNew;

  /// No description provided for @entryDialogTitleEdit.
  ///
  /// In de, this message translates to:
  /// **'Eintrag bearbeiten'**
  String get entryDialogTitleEdit;

  /// No description provided for @entryDialogSectionTime.
  ///
  /// In de, this message translates to:
  /// **'Chronometrie'**
  String get entryDialogSectionTime;

  /// No description provided for @entryDialogSectionNav.
  ///
  /// In de, this message translates to:
  /// **'Navigation'**
  String get entryDialogSectionNav;

  /// No description provided for @entryDialogSectionEnv.
  ///
  /// In de, this message translates to:
  /// **'Umgebung'**
  String get entryDialogSectionEnv;

  /// No description provided for @entryDialogSectionVessel.
  ///
  /// In de, this message translates to:
  /// **'Schiff'**
  String get entryDialogSectionVessel;

  /// No description provided for @entryDialogSectionRemarks.
  ///
  /// In de, this message translates to:
  /// **'Bemerkungen'**
  String get entryDialogSectionRemarks;

  /// No description provided for @entryDialogTimeLabel.
  ///
  /// In de, this message translates to:
  /// **'Uhrzeit'**
  String get entryDialogTimeLabel;

  /// No description provided for @entryDialogCourseLabel.
  ///
  /// In de, this message translates to:
  /// **'Kurs (°)'**
  String get entryDialogCourseLabel;

  /// No description provided for @entryDialogSpeedLabel.
  ///
  /// In de, this message translates to:
  /// **'Fahrt (kn)'**
  String get entryDialogSpeedLabel;

  /// No description provided for @entryDialogWindLabel.
  ///
  /// In de, this message translates to:
  /// **'Wind Richtung & Stärke'**
  String get entryDialogWindLabel;

  /// No description provided for @entryDialogSeaLabel.
  ///
  /// In de, this message translates to:
  /// **'See'**
  String get entryDialogSeaLabel;

  /// No description provided for @entryDialogSeaHint.
  ///
  /// In de, this message translates to:
  /// **'z.B. Leicht'**
  String get entryDialogSeaHint;

  /// No description provided for @entryDialogWeatherLabel.
  ///
  /// In de, this message translates to:
  /// **'Wetter'**
  String get entryDialogWeatherLabel;

  /// No description provided for @entryDialogWeatherHint.
  ///
  /// In de, this message translates to:
  /// **'z.B. Sonnig'**
  String get entryDialogWeatherHint;

  /// No description provided for @entryDialogTemperatureLabel.
  ///
  /// In de, this message translates to:
  /// **'Temperatur'**
  String get entryDialogTemperatureLabel;

  /// No description provided for @entryDialogPressureLabel.
  ///
  /// In de, this message translates to:
  /// **'Luftdruck'**
  String get entryDialogPressureLabel;

  /// No description provided for @entryDialogAddTempPressure.
  ///
  /// In de, this message translates to:
  /// **'Temperatur & Luftdruck hinzufügen'**
  String get entryDialogAddTempPressure;

  /// No description provided for @entryDialogMotorLabel.
  ///
  /// In de, this message translates to:
  /// **'Motor'**
  String get entryDialogMotorLabel;

  /// No description provided for @entryDialogKeelLabel.
  ///
  /// In de, this message translates to:
  /// **'Kiel'**
  String get entryDialogKeelLabel;

  /// No description provided for @entryDialogRemarksHint.
  ///
  /// In de, this message translates to:
  /// **'z.B. Beobachtung, Erlebnis…'**
  String get entryDialogRemarksHint;

  /// No description provided for @entryDialogSubmitNew.
  ///
  /// In de, this message translates to:
  /// **'In Log eintragen'**
  String get entryDialogSubmitNew;

  /// No description provided for @crewDialogTitleAdd.
  ///
  /// In de, this message translates to:
  /// **'Besatzung hinzufügen'**
  String get crewDialogTitleAdd;

  /// No description provided for @crewDialogTitleEdit.
  ///
  /// In de, this message translates to:
  /// **'Besatzung bearbeiten'**
  String get crewDialogTitleEdit;

  /// No description provided for @crewSectionIdentity.
  ///
  /// In de, this message translates to:
  /// **'Identität'**
  String get crewSectionIdentity;

  /// No description provided for @crewFieldFullName.
  ///
  /// In de, this message translates to:
  /// **'Vollständiger Name'**
  String get crewFieldFullName;

  /// No description provided for @crewFieldFullNameHint.
  ///
  /// In de, this message translates to:
  /// **'z.B. Thomas Müller'**
  String get crewFieldFullNameHint;

  /// No description provided for @crewSectionMedical.
  ///
  /// In de, this message translates to:
  /// **'Medizinische Info'**
  String get crewSectionMedical;

  /// No description provided for @crewFieldBloodGroup.
  ///
  /// In de, this message translates to:
  /// **'Blutgruppe'**
  String get crewFieldBloodGroup;

  /// No description provided for @crewFieldBloodGroupHint.
  ///
  /// In de, this message translates to:
  /// **'z.B. 0+, A-'**
  String get crewFieldBloodGroupHint;

  /// No description provided for @crewFieldAllergies.
  ///
  /// In de, this message translates to:
  /// **'Allergien'**
  String get crewFieldAllergies;

  /// No description provided for @crewFieldAllergiesHint.
  ///
  /// In de, this message translates to:
  /// **'Bekannte Allergien auflisten…'**
  String get crewFieldAllergiesHint;

  /// No description provided for @crewFieldConditions.
  ///
  /// In de, this message translates to:
  /// **'Erkrankungen / Medikamente'**
  String get crewFieldConditions;

  /// No description provided for @crewFieldConditionsHint.
  ///
  /// In de, this message translates to:
  /// **'z.B. Benötigt Inhalator (Asthma)…'**
  String get crewFieldConditionsHint;

  /// No description provided for @crewSectionSafety.
  ///
  /// In de, this message translates to:
  /// **'Sicherheitsausrüstung'**
  String get crewSectionSafety;

  /// No description provided for @crewFieldPersonalEpirb.
  ///
  /// In de, this message translates to:
  /// **'Persönlicher EPIRB / PLB'**
  String get crewFieldPersonalEpirb;

  /// No description provided for @crewFieldPersonalEpirbHint.
  ///
  /// In de, this message translates to:
  /// **'z.B. Ja, McMurdo FastFind 220'**
  String get crewFieldPersonalEpirbHint;

  /// No description provided for @crewSectionRemarks.
  ///
  /// In de, this message translates to:
  /// **'Bemerkungen'**
  String get crewSectionRemarks;

  /// No description provided for @crewFieldRemarksHint.
  ///
  /// In de, this message translates to:
  /// **'Allgemeine Notizen zu dieser Person…'**
  String get crewFieldRemarksHint;

  /// No description provided for @crewButtonAddToCrew.
  ///
  /// In de, this message translates to:
  /// **'Zur Besatzung hinzufügen'**
  String get crewButtonAddToCrew;

  /// No description provided for @crewDetailNoInfo.
  ///
  /// In de, this message translates to:
  /// **'Für diese Person sind keine weiteren Angaben erfasst.'**
  String get crewDetailNoInfo;

  /// No description provided for @crewButtonRemoveFromCrew.
  ///
  /// In de, this message translates to:
  /// **'Besatzung entfernen'**
  String get crewButtonRemoveFromCrew;

  /// No description provided for @crewButtonRemoveFromDay.
  ///
  /// In de, this message translates to:
  /// **'Von diesem Tag entfernen'**
  String get crewButtonRemoveFromDay;

  /// No description provided for @crewPickerTitle.
  ///
  /// In de, this message translates to:
  /// **'Besatzung wählen'**
  String get crewPickerTitle;

  /// No description provided for @crewPickerNewPerson.
  ///
  /// In de, this message translates to:
  /// **'Neue Person…'**
  String get crewPickerNewPerson;

  /// No description provided for @crewRosterTitle.
  ///
  /// In de, this message translates to:
  /// **'Besatzungsliste'**
  String get crewRosterTitle;

  /// No description provided for @crewRosterEmpty.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Besatzungsmitglieder'**
  String get crewRosterEmpty;

  /// No description provided for @crewRosterEmptyHint.
  ///
  /// In de, this message translates to:
  /// **'Tippe auf + um eine Person hinzuzufügen.'**
  String get crewRosterEmptyHint;

  /// No description provided for @crewRosterNewPerson.
  ///
  /// In de, this message translates to:
  /// **'Neue Person'**
  String get crewRosterNewPerson;

  /// No description provided for @crewRosterReorderTooltip.
  ///
  /// In de, this message translates to:
  /// **'Sortieren'**
  String get crewRosterReorderTooltip;

  /// No description provided for @crewRosterReorderDoneTooltip.
  ///
  /// In de, this message translates to:
  /// **'Fertig'**
  String get crewRosterReorderDoneTooltip;

  /// No description provided for @crewRosterMemberDeleted.
  ///
  /// In de, this message translates to:
  /// **'{name} entfernt.'**
  String crewRosterMemberDeleted(String name);

  /// No description provided for @settingsTitle.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen'**
  String get settingsTitle;

  /// No description provided for @settingsSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Navigationsumgebung konfigurieren'**
  String get settingsSubtitle;

  /// No description provided for @settingsVesselSection.
  ///
  /// In de, this message translates to:
  /// **'Schiff'**
  String get settingsVesselSection;

  /// No description provided for @settingsVesselInfo.
  ///
  /// In de, this message translates to:
  /// **'Schiffsdaten wie Name, MMSI und Rufzeichen sowie Notfallausrüstung erfassen.'**
  String get settingsVesselInfo;

  /// No description provided for @settingsFieldName.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get settingsFieldName;

  /// No description provided for @settingsFieldNameHint.
  ///
  /// In de, this message translates to:
  /// **'z.B. S.V. Adventure'**
  String get settingsFieldNameHint;

  /// No description provided for @settingsFieldCallSign.
  ///
  /// In de, this message translates to:
  /// **'Rufzeichen'**
  String get settingsFieldCallSign;

  /// No description provided for @settingsFieldCallSignHint.
  ///
  /// In de, this message translates to:
  /// **'z.B. HB-9-XY'**
  String get settingsFieldCallSignHint;

  /// No description provided for @settingsFieldLifeRaftHint.
  ///
  /// In de, this message translates to:
  /// **'z.B. Cockpitfach, 6 Personen'**
  String get settingsFieldLifeRaftHint;

  /// No description provided for @settingsFieldEpirbHint.
  ///
  /// In de, this message translates to:
  /// **'z.B. Navigationstisch'**
  String get settingsFieldEpirbHint;

  /// No description provided for @settingsFieldFireSuppHint.
  ///
  /// In de, this message translates to:
  /// **'z.B. Kombüse, Motorraum'**
  String get settingsFieldFireSuppHint;

  /// No description provided for @settingsEquipmentSection.
  ///
  /// In de, this message translates to:
  /// **'Schiffskonfiguration'**
  String get settingsEquipmentSection;

  /// No description provided for @settingsEquipmentInfo.
  ///
  /// In de, this message translates to:
  /// **'Lege fest, welche Segel-, Motor- und Kielzustände für Logbucheinträge verwendet werden können.'**
  String get settingsEquipmentInfo;

  /// No description provided for @settingsEquipmentSlotLabel.
  ///
  /// In de, this message translates to:
  /// **'Bezeichnung'**
  String get settingsEquipmentSlotLabel;

  /// No description provided for @settingsEquipmentStateLabel.
  ///
  /// In de, this message translates to:
  /// **'Zustand'**
  String get settingsEquipmentStateLabel;

  /// No description provided for @settingsEquipmentAddState.
  ///
  /// In de, this message translates to:
  /// **'Hinzufügen'**
  String get settingsEquipmentAddState;

  /// No description provided for @settingsEquipmentStateDeleted.
  ///
  /// In de, this message translates to:
  /// **'{state} entfernt.'**
  String settingsEquipmentStateDeleted(String state);

  /// No description provided for @settingsEquipmentTypeSail.
  ///
  /// In de, this message translates to:
  /// **'Segel'**
  String get settingsEquipmentTypeSail;

  /// No description provided for @settingsEquipmentAddType.
  ///
  /// In de, this message translates to:
  /// **'{type} hinzufügen'**
  String settingsEquipmentAddType(String type);

  /// No description provided for @settingsEquipmentDeleteType.
  ///
  /// In de, this message translates to:
  /// **'{type} löschen'**
  String settingsEquipmentDeleteType(String type);

  /// No description provided for @settingsEquipmentTypeDeleted.
  ///
  /// In de, this message translates to:
  /// **'{type} entfernt.'**
  String settingsEquipmentTypeDeleted(String type);

  /// No description provided for @settingsAppearanceSection.
  ///
  /// In de, this message translates to:
  /// **'Darstellung & Standort'**
  String get settingsAppearanceSection;

  /// No description provided for @settingsAppearanceInfo.
  ///
  /// In de, this message translates to:
  /// **'Design und Sprache der App anpassen, sowie ob neue Einträge deine GPS-Position erfassen.'**
  String get settingsAppearanceInfo;

  /// No description provided for @settingsThemeLabel.
  ///
  /// In de, this message translates to:
  /// **'App-Design'**
  String get settingsThemeLabel;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In de, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeLight.
  ///
  /// In de, this message translates to:
  /// **'Hell'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In de, this message translates to:
  /// **'Dunkel'**
  String get settingsThemeDark;

  /// No description provided for @settingsLanguageLabel.
  ///
  /// In de, this message translates to:
  /// **'Sprache'**
  String get settingsLanguageLabel;

  /// No description provided for @settingsLanguageDe.
  ///
  /// In de, this message translates to:
  /// **'Deutsch'**
  String get settingsLanguageDe;

  /// No description provided for @settingsLanguageEn.
  ///
  /// In de, this message translates to:
  /// **'English'**
  String get settingsLanguageEn;

  /// No description provided for @settingsAutoLogPositionLabel.
  ///
  /// In de, this message translates to:
  /// **'Position bei neuen Einträgen erfassen'**
  String get settingsAutoLogPositionLabel;

  /// No description provided for @settingsAutoLogPositionDesc.
  ///
  /// In de, this message translates to:
  /// **'Solange dies aktiviert ist, wird die GPS-Position dieses Geräts automatisch für jeden neuen Zeitleisten-Eintrag erfasst. Die Position jedes Eintrags wird einmalig bei dessen Erstellung erfasst und danach nie erneut erfasst oder geändert. Nicht im PDF-Export enthalten.'**
  String get settingsAutoLogPositionDesc;

  /// No description provided for @settingsTrackFilterSection.
  ///
  /// In de, this message translates to:
  /// **'Trackfilter'**
  String get settingsTrackFilterSection;

  /// No description provided for @settingsFilterModeMooring.
  ///
  /// In de, this message translates to:
  /// **'Liegeplatz & Anker'**
  String get settingsFilterModeMooring;

  /// No description provided for @settingsFilterModeExact.
  ///
  /// In de, this message translates to:
  /// **'Genaue Position'**
  String get settingsFilterModeExact;

  /// No description provided for @settingsStationaryLabel.
  ///
  /// In de, this message translates to:
  /// **'Stationäre Erkennung'**
  String get settingsStationaryLabel;

  /// No description provided for @settingsStationaryDesc.
  ///
  /// In de, this message translates to:
  /// **'Bestimmt, wie Liegeplätze, Ankerstopps und Hafenbesuche erkannt und als Ankerpunkt dargestellt werden – am Anfang, Ende und unterwegs.'**
  String get settingsStationaryDesc;

  /// No description provided for @settingsMooringDesc.
  ///
  /// In de, this message translates to:
  /// **'Liegeplatz und Ankerpositionen werden als einzelner Punkt dargestellt. Auch ein weitausholender Ankerkreis wird zu einem Punkt zusammengefasst.'**
  String get settingsMooringDesc;

  /// No description provided for @settingsExactPositionDesc.
  ///
  /// In de, this message translates to:
  /// **'Nur eng geclusterte Positionen gelten als stationär. Breite Ankerkreise bleiben sichtbar – besser für Ankerwache.'**
  String get settingsExactPositionDesc;

  /// No description provided for @settingsMinStopLabel.
  ///
  /// In de, this message translates to:
  /// **'Min. Stopp-Dauer'**
  String get settingsMinStopLabel;

  /// No description provided for @settingsMinUnit.
  ///
  /// In de, this message translates to:
  /// **'min'**
  String get settingsMinUnit;

  /// No description provided for @settingsMinStopDesc.
  ///
  /// In de, this message translates to:
  /// **'Mindestdauer eines echten Stopps (Anker, Hafen). Kurze Langsamfahrten (Wende, Flaute) werden ignoriert.'**
  String get settingsMinStopDesc;

  /// No description provided for @settingsMaxAnchorLabel.
  ///
  /// In de, this message translates to:
  /// **'Max. Ankerschwung'**
  String get settingsMaxAnchorLabel;

  /// No description provided for @settingsMetersUnit.
  ///
  /// In de, this message translates to:
  /// **'m'**
  String get settingsMetersUnit;

  /// No description provided for @settingsMaxAnchorDesc.
  ///
  /// In de, this message translates to:
  /// **'Maximale Ausdehnung eines Stopps. Erhöhen bei weitem Ankerschwung über Nacht (Standard: 30 m).'**
  String get settingsMaxAnchorDesc;

  /// No description provided for @settingsColdStartLabel.
  ///
  /// In de, this message translates to:
  /// **'Kaltstart-Trimmen'**
  String get settingsColdStartLabel;

  /// No description provided for @settingsColdStartDesc.
  ///
  /// In de, this message translates to:
  /// **'Entfernt ungenaue GPS-Fixes am Spuranfang, bevor der Empfänger eingeschwungen ist.'**
  String get settingsColdStartDesc;

  /// No description provided for @settingsTrimSharpnessLabel.
  ///
  /// In de, this message translates to:
  /// **'Trim-Schärfe'**
  String get settingsTrimSharpnessLabel;

  /// No description provided for @settingsTrimSharpnessDesc.
  ///
  /// In de, this message translates to:
  /// **'Niedrigerer Wert = aggressiver trimmen. Standard: 3.0.'**
  String get settingsTrimSharpnessDesc;

  /// No description provided for @settingsUnderwayLabel.
  ///
  /// In de, this message translates to:
  /// **'Unterwegs-Schwelle'**
  String get settingsUnderwayLabel;

  /// No description provided for @settingsUnderwayDesc.
  ///
  /// In de, this message translates to:
  /// **'Mindestgeschwindigkeit für den Fahrt-Durchschnitt. Driften unterhalb wird nicht mitgezählt.'**
  String get settingsUnderwayDesc;

  /// No description provided for @settingsPercentileLabel.
  ///
  /// In de, this message translates to:
  /// **'Spitzenwert-Perzentil'**
  String get settingsPercentileLabel;

  /// No description provided for @settingsPercentileDesc.
  ///
  /// In de, this message translates to:
  /// **'p99 ignoriert das oberste 1 % der Messwerte und unterdrückt GPS-Ausreißer. p100 = echter Maximalwert.'**
  String get settingsPercentileDesc;

  /// No description provided for @settingsMaxSpeedLabel.
  ///
  /// In de, this message translates to:
  /// **'Geschwindigkeits-Obergrenze'**
  String get settingsMaxSpeedLabel;

  /// No description provided for @settingsMaxSpeedDesc.
  ///
  /// In de, this message translates to:
  /// **'Fixe Punkte über dieser Geschwindigkeit gelten immer als GPS-Ausreißer. Bei schnellen Booten (Regatta, Foiler, Motorboot) erhöhen, sonst werden echte schnelle Fahrten herausgefiltert.'**
  String get settingsMaxSpeedDesc;

  /// No description provided for @settingsShowRawTrackLabel.
  ///
  /// In de, this message translates to:
  /// **'Ungefilterte Spur anzeigen'**
  String get settingsShowRawTrackLabel;

  /// No description provided for @settingsShowRawTrackDesc.
  ///
  /// In de, this message translates to:
  /// **'Zeigt den Roh-GPX-Track zusätzlich zur gefilterten Spur an. Dient zur Fehleranalyse und zum Optimieren der Filtereinstellungen.'**
  String get settingsShowRawTrackDesc;

  /// No description provided for @settingsCrewSection.
  ///
  /// In de, this message translates to:
  /// **'Besatzungsliste'**
  String get settingsCrewSection;

  /// No description provided for @settingsBackupSection.
  ///
  /// In de, this message translates to:
  /// **'Backup & Wiederherstellung'**
  String get settingsBackupSection;

  /// No description provided for @settingsBackupSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Daten dieses Logbuchs exportieren oder wiederherstellen'**
  String get settingsBackupSubtitle;

  /// No description provided for @settingsSetUpCloudSync.
  ///
  /// In de, this message translates to:
  /// **'Cloud-Synchronisierung einrichten'**
  String get settingsSetUpCloudSync;

  /// No description provided for @settingsSetUpCloudSyncSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Anmelden, um geräteübergreifend zu synchronisieren und dein Logbuch in der Cloud zu sichern'**
  String get settingsSetUpCloudSyncSubtitle;

  /// No description provided for @settingsNoEntries.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Einträge'**
  String get settingsNoEntries;

  /// No description provided for @settingsNoLogbooks.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Logbücher'**
  String get settingsNoLogbooks;

  /// No description provided for @settingsPersonCount.
  ///
  /// In de, this message translates to:
  /// **'{count, plural, one{Person} other{Personen}}'**
  String settingsPersonCount(int count);

  /// No description provided for @settingsSyncSection.
  ///
  /// In de, this message translates to:
  /// **'Synchronisierung'**
  String get settingsSyncSection;

  /// No description provided for @settingsLogbookCodeLabel.
  ///
  /// In de, this message translates to:
  /// **'Logbuch-Code'**
  String get settingsLogbookCodeLabel;

  /// No description provided for @settingsLogbookCodeDesc.
  ///
  /// In de, this message translates to:
  /// **'Gib diesen Code auf einem anderen Gerät ein, um dasselbe Logbuch zu teilen.'**
  String get settingsLogbookCodeDesc;

  /// No description provided for @settingsLogbookSyncLabel.
  ///
  /// In de, this message translates to:
  /// **'Logbook Sync'**
  String get settingsLogbookSyncLabel;

  /// No description provided for @settingsLogbookSyncDesc.
  ///
  /// In de, this message translates to:
  /// **'Mit einem anderen Logbuch via Firebase verbinden.'**
  String get settingsLogbookSyncDesc;

  /// No description provided for @settingsEnterSyncCode.
  ///
  /// In de, this message translates to:
  /// **'Sync-Code eingeben'**
  String get settingsEnterSyncCode;

  /// No description provided for @settingsSynchronize.
  ///
  /// In de, this message translates to:
  /// **'Synchronisieren'**
  String get settingsSynchronize;

  /// No description provided for @settingsInvalidCode.
  ///
  /// In de, this message translates to:
  /// **'Ungültiger Code.'**
  String get settingsInvalidCode;

  /// No description provided for @settingsConnectLogbookTitle.
  ///
  /// In de, this message translates to:
  /// **'Logbuch verbinden'**
  String get settingsConnectLogbookTitle;

  /// No description provided for @settingsConnectLogbookContent.
  ///
  /// In de, this message translates to:
  /// **'Dieses Gerät wird mit dem Logbuch \"{code}\" verbunden. Alle lokalen Einträge werden gelöscht und durch die Cloud-Daten ersetzt.'**
  String settingsConnectLogbookContent(String code);

  /// No description provided for @settingsConnectedAndSynced.
  ///
  /// In de, this message translates to:
  /// **'Verbunden und synchronisiert.'**
  String get settingsConnectedAndSynced;

  /// No description provided for @settingsError.
  ///
  /// In de, this message translates to:
  /// **'Fehler'**
  String get settingsError;

  /// No description provided for @settingsInviteCodeLabel.
  ///
  /// In de, this message translates to:
  /// **'Dein Einladungscode'**
  String get settingsInviteCodeLabel;

  /// No description provided for @settingsInviteCodeDesc.
  ///
  /// In de, this message translates to:
  /// **'Teile diesen Code mit einem Crewmitglied, um Zugang zu diesem Logbuch zu gewähren.'**
  String get settingsInviteCodeDesc;

  /// No description provided for @settingsConnectButton.
  ///
  /// In de, this message translates to:
  /// **'Mit Logbuch verbinden'**
  String get settingsConnectButton;

  /// No description provided for @settingsCodeNotFound.
  ///
  /// In de, this message translates to:
  /// **'Code nicht gefunden.'**
  String get settingsCodeNotFound;

  /// No description provided for @settingsAlreadyConnected.
  ///
  /// In de, this message translates to:
  /// **'Bereits verbunden.'**
  String get settingsAlreadyConnected;

  /// No description provided for @settingsConnected.
  ///
  /// In de, this message translates to:
  /// **'Verbunden.'**
  String get settingsConnected;

  /// No description provided for @settingsSwitchLogbookTitle.
  ///
  /// In de, this message translates to:
  /// **'Logbuch wechseln?'**
  String get settingsSwitchLogbookTitle;

  /// No description provided for @settingsSwitchLogbookContent.
  ///
  /// In de, this message translates to:
  /// **'Die lokalen Daten werden durch die Daten des verbundenen Logbuchs ersetzt.'**
  String get settingsSwitchLogbookContent;

  /// No description provided for @settingsSwitchLogbookOffline.
  ///
  /// In de, this message translates to:
  /// **'Für den Logbuchwechsel ist eine Internetverbindung erforderlich.'**
  String get settingsSwitchLogbookOffline;

  /// No description provided for @settingsSwitchLogbookError.
  ///
  /// In de, this message translates to:
  /// **'Logbuch konnte nicht gewechselt werden. Bitte versuche es erneut.'**
  String get settingsSwitchLogbookError;

  /// No description provided for @settingsSwitchLogbookInProgress.
  ///
  /// In de, this message translates to:
  /// **'Logbuch wird gewechselt…'**
  String get settingsSwitchLogbookInProgress;

  /// No description provided for @settingsSwitchLogbookComplete.
  ///
  /// In de, this message translates to:
  /// **'Logbuch gewechselt.'**
  String get settingsSwitchLogbookComplete;

  /// No description provided for @settingsScanQr.
  ///
  /// In de, this message translates to:
  /// **'QR scannen'**
  String get settingsScanQr;

  /// No description provided for @settingsScanTitle.
  ///
  /// In de, this message translates to:
  /// **'Logbuch-QR-Code scannen'**
  String get settingsScanTitle;

  /// No description provided for @tracksTitle.
  ///
  /// In de, this message translates to:
  /// **'Fahrtstrecken'**
  String get tracksTitle;

  /// No description provided for @tracksOneYear.
  ///
  /// In de, this message translates to:
  /// **'Letztes Jahr'**
  String get tracksOneYear;

  /// No description provided for @tracksOneMonth.
  ///
  /// In de, this message translates to:
  /// **'Letzter Monat'**
  String get tracksOneMonth;

  /// No description provided for @tracksOneWeek.
  ///
  /// In de, this message translates to:
  /// **'Letzte Woche'**
  String get tracksOneWeek;

  /// No description provided for @tracksCustom.
  ///
  /// In de, this message translates to:
  /// **'Eigene'**
  String get tracksCustom;

  /// No description provided for @tracksZoomIn.
  ///
  /// In de, this message translates to:
  /// **'Vergrössern'**
  String get tracksZoomIn;

  /// No description provided for @tracksZoomOut.
  ///
  /// In de, this message translates to:
  /// **'Verkleinern'**
  String get tracksZoomOut;

  /// No description provided for @tracksShowAll.
  ///
  /// In de, this message translates to:
  /// **'Alle Tracks anzeigen'**
  String get tracksShowAll;

  /// No description provided for @tracksFullscreen.
  ///
  /// In de, this message translates to:
  /// **'Vollbild'**
  String get tracksFullscreen;

  /// No description provided for @tracksMapView.
  ///
  /// In de, this message translates to:
  /// **'Kartenansicht'**
  String get tracksMapView;

  /// No description provided for @tracksSatelliteView.
  ///
  /// In de, this message translates to:
  /// **'Satellitenansicht'**
  String get tracksSatelliteView;

  /// No description provided for @tracksNoTracks.
  ///
  /// In de, this message translates to:
  /// **'Keine Tracks vorhanden'**
  String get tracksNoTracks;

  /// No description provided for @tracksNoTracksInPeriod.
  ///
  /// In de, this message translates to:
  /// **'Keine Tracks im gewählten Zeitraum'**
  String get tracksNoTracksInPeriod;

  /// No description provided for @arrivalTimeUncertainTooltip.
  ///
  /// In de, this message translates to:
  /// **'Ankunftszeit anhand der letzten Bewegung geschätzt. Die GPS-Positionsqualität reichte nicht aus, um den genauen Liegeplatz zu bestimmen.'**
  String get arrivalTimeUncertainTooltip;

  /// No description provided for @departureTimeEstimatedTooltip.
  ///
  /// In de, this message translates to:
  /// **'Abfahrtszeit anhand der ersten Bewegung geschätzt. Die GPS-Positionsqualität reichte nicht aus, um den genauen Liegeplatz zu bestimmen.'**
  String get departureTimeEstimatedTooltip;

  /// No description provided for @departureTimeUnknownTooltip.
  ///
  /// In de, this message translates to:
  /// **'Diese Aufzeichnung beginnt, während das Boot bereits unterwegs war — die tatsächliche Abfahrtszeit wurde nicht erfasst.'**
  String get departureTimeUnknownTooltip;

  /// No description provided for @dayChangeDateTitle.
  ///
  /// In de, this message translates to:
  /// **'Falsches Datum?'**
  String get dayChangeDateTitle;

  /// No description provided for @dayChangeDateContent.
  ///
  /// In de, this message translates to:
  /// **'Der GPX-Track enthält hauptsächlich Daten vom {from}, nicht vom {to}.\n\nTrotzdem verschieben?'**
  String dayChangeDateContent(String from, String to);

  /// No description provided for @dayChangeDateConfirm.
  ///
  /// In de, this message translates to:
  /// **'Trotzdem verschieben'**
  String get dayChangeDateConfirm;

  /// No description provided for @dayDateExistsError.
  ///
  /// In de, this message translates to:
  /// **'Für dieses Datum existiert bereits ein Eintrag.'**
  String get dayDateExistsError;

  /// No description provided for @dayGpxNoWaypoints.
  ///
  /// In de, this message translates to:
  /// **'GPX-File enthält keine Wegpunkte mit Zeitstempel.'**
  String get dayGpxNoWaypoints;

  /// No description provided for @dayGpxWrongDateContent.
  ///
  /// In de, this message translates to:
  /// **'Das GPX-File enthält hauptsächlich Daten vom {from}, nicht vom {to}.\n\nTrotzdem importieren?'**
  String dayGpxWrongDateContent(String from, String to);

  /// No description provided for @dayGpxImportConfirm.
  ///
  /// In de, this message translates to:
  /// **'Trotzdem importieren'**
  String get dayGpxImportConfirm;

  /// No description provided for @dayGpxImported.
  ///
  /// In de, this message translates to:
  /// **'GPX-Track importiert für {date}.'**
  String dayGpxImported(String date);

  /// No description provided for @dayGpxExported.
  ///
  /// In de, this message translates to:
  /// **'GPX exportiert.'**
  String get dayGpxExported;

  /// No description provided for @dayGpxDeleteTitle.
  ///
  /// In de, this message translates to:
  /// **'GPX-Track entfernen?'**
  String get dayGpxDeleteTitle;

  /// No description provided for @dayGpxDeleteContent.
  ///
  /// In de, this message translates to:
  /// **'GPX-Track für diesen Tag löschen?'**
  String get dayGpxDeleteContent;

  /// No description provided for @dayGpxRemoved.
  ///
  /// In de, this message translates to:
  /// **'GPX-Track entfernt.'**
  String get dayGpxRemoved;

  /// No description provided for @dayDeleteTitle.
  ///
  /// In de, this message translates to:
  /// **'Tag löschen?'**
  String get dayDeleteTitle;

  /// No description provided for @dayDeleteContent.
  ///
  /// In de, this message translates to:
  /// **'Alle Daten für den {date} werden unwiderruflich gelöscht, inklusive Logeinträge und GPX-Track.'**
  String dayDeleteContent(String date);

  /// No description provided for @dayEntryDeleted.
  ///
  /// In de, this message translates to:
  /// **'Logeintrag gelöscht.'**
  String get dayEntryDeleted;

  /// No description provided for @dayEntryUpdated.
  ///
  /// In de, this message translates to:
  /// **'Logeintrag aktualisiert.'**
  String get dayEntryUpdated;

  /// No description provided for @dayFreeTextHint.
  ///
  /// In de, this message translates to:
  /// **'Freie Notizen für diesen Tag…'**
  String get dayFreeTextHint;

  /// No description provided for @dayDiaryHint.
  ///
  /// In de, this message translates to:
  /// **'Tagebucheintrag für diesen Tag…'**
  String get dayDiaryHint;

  /// No description provided for @vesselStatusTitle.
  ///
  /// In de, this message translates to:
  /// **'Schiffsstatus'**
  String get vesselStatusTitle;

  /// No description provided for @vesselOilLabel.
  ///
  /// In de, this message translates to:
  /// **'Motoröl'**
  String get vesselOilLabel;

  /// No description provided for @vesselFuelLabel.
  ///
  /// In de, this message translates to:
  /// **'Kraftstoff'**
  String get vesselFuelLabel;

  /// No description provided for @vesselFullLabel.
  ///
  /// In de, this message translates to:
  /// **'Voll'**
  String get vesselFullLabel;

  /// No description provided for @vesselEmptyLabel.
  ///
  /// In de, this message translates to:
  /// **'Leer'**
  String get vesselEmptyLabel;

  /// No description provided for @vesselKeelDown.
  ///
  /// In de, this message translates to:
  /// **'Unten'**
  String get vesselKeelDown;

  /// No description provided for @vesselKeelUp.
  ///
  /// In de, this message translates to:
  /// **'Oben'**
  String get vesselKeelUp;

  /// No description provided for @gpsConsentTitle.
  ///
  /// In de, this message translates to:
  /// **'GPS für den Notfall'**
  String get gpsConsentTitle;

  /// No description provided for @gpsConsentContent.
  ///
  /// In de, this message translates to:
  /// **'Beim Aktivieren des Funk-Notrufs ermittelt die App Ihren GPS-Standort und trägt ihn automatisch ins Mayday-Protokoll ein, damit Rettungskräfte Ihre genaue Position sofort erhalten. Der Standort wird ausschliesslich in diesem Moment genutzt.'**
  String get gpsConsentContent;

  /// No description provided for @gpsConsentLater.
  ///
  /// In de, this message translates to:
  /// **'Später'**
  String get gpsConsentLater;

  /// No description provided for @gpsConsentAllow.
  ///
  /// In de, this message translates to:
  /// **'Zugriff erlauben'**
  String get gpsConsentAllow;

  /// No description provided for @authLoginTitle.
  ///
  /// In de, this message translates to:
  /// **'Willkommen zurück'**
  String get authLoginTitle;

  /// No description provided for @authLoginSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Melde dich an, um dein Logbuch geräteübergreifend zu synchronisieren.'**
  String get authLoginSubtitle;

  /// No description provided for @authEmailLabel.
  ///
  /// In de, this message translates to:
  /// **'E-Mail'**
  String get authEmailLabel;

  /// No description provided for @authEmailHint.
  ///
  /// In de, this message translates to:
  /// **'kapitaen@beispiel.com'**
  String get authEmailHint;

  /// No description provided for @authPasswordLabel.
  ///
  /// In de, this message translates to:
  /// **'Passwort'**
  String get authPasswordLabel;

  /// No description provided for @authPasswordHint.
  ///
  /// In de, this message translates to:
  /// **'Dein Passwort'**
  String get authPasswordHint;

  /// No description provided for @authSignIn.
  ///
  /// In de, this message translates to:
  /// **'Anmelden'**
  String get authSignIn;

  /// No description provided for @authSignInWithGoogle.
  ///
  /// In de, this message translates to:
  /// **'Mit Google fortfahren'**
  String get authSignInWithGoogle;

  /// No description provided for @authSignInWithApple.
  ///
  /// In de, this message translates to:
  /// **'Mit Apple fortfahren'**
  String get authSignInWithApple;

  /// No description provided for @authOrDivider.
  ///
  /// In de, this message translates to:
  /// **'oder'**
  String get authOrDivider;

  /// No description provided for @authNoAccount.
  ///
  /// In de, this message translates to:
  /// **'Noch kein Konto?'**
  String get authNoAccount;

  /// No description provided for @authRegisterLink.
  ///
  /// In de, this message translates to:
  /// **'Registrieren'**
  String get authRegisterLink;

  /// No description provided for @authContinueOffline.
  ///
  /// In de, this message translates to:
  /// **'Ohne Konto fortfahren'**
  String get authContinueOffline;

  /// No description provided for @authForgotPasswordLink.
  ///
  /// In de, this message translates to:
  /// **'Passwort vergessen?'**
  String get authForgotPasswordLink;

  /// No description provided for @authRegisterTitle.
  ///
  /// In de, this message translates to:
  /// **'Konto erstellen'**
  String get authRegisterTitle;

  /// No description provided for @authRegisterSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Deine Logbuchdaten bleiben auf dem Gerät und werden über dein Konto synchronisiert.'**
  String get authRegisterSubtitle;

  /// No description provided for @authConfirmPasswordLabel.
  ///
  /// In de, this message translates to:
  /// **'Passwort bestätigen'**
  String get authConfirmPasswordLabel;

  /// No description provided for @authConfirmPasswordHint.
  ///
  /// In de, this message translates to:
  /// **'Passwort wiederholen'**
  String get authConfirmPasswordHint;

  /// No description provided for @authPasswordMismatch.
  ///
  /// In de, this message translates to:
  /// **'Die Passwörter stimmen nicht überein.'**
  String get authPasswordMismatch;

  /// No description provided for @authPasswordTooShort.
  ///
  /// In de, this message translates to:
  /// **'Das Passwort muss mindestens 6 Zeichen lang sein.'**
  String get authPasswordTooShort;

  /// No description provided for @authCreateAccount.
  ///
  /// In de, this message translates to:
  /// **'Konto erstellen'**
  String get authCreateAccount;

  /// No description provided for @authAlreadyHaveAccount.
  ///
  /// In de, this message translates to:
  /// **'Bereits ein Konto?'**
  String get authAlreadyHaveAccount;

  /// No description provided for @authSignInLink.
  ///
  /// In de, this message translates to:
  /// **'Anmelden'**
  String get authSignInLink;

  /// No description provided for @authForgotPasswordTitle.
  ///
  /// In de, this message translates to:
  /// **'Passwort zurücksetzen'**
  String get authForgotPasswordTitle;

  /// No description provided for @authForgotPasswordDesc.
  ///
  /// In de, this message translates to:
  /// **'Gib deine E-Mail-Adresse ein und wir senden dir einen Link zum Zurücksetzen deines Passworts.'**
  String get authForgotPasswordDesc;

  /// No description provided for @authSendResetEmail.
  ///
  /// In de, this message translates to:
  /// **'Link senden'**
  String get authSendResetEmail;

  /// No description provided for @authResetEmailSent.
  ///
  /// In de, this message translates to:
  /// **'Link gesendet — bitte prüfe deinen Posteingang.'**
  String get authResetEmailSent;

  /// No description provided for @authBackToSignIn.
  ///
  /// In de, this message translates to:
  /// **'Zurück zur Anmeldung'**
  String get authBackToSignIn;

  /// No description provided for @authSignOut.
  ///
  /// In de, this message translates to:
  /// **'Abmelden'**
  String get authSignOut;

  /// No description provided for @authSignOutConfirm.
  ///
  /// In de, this message translates to:
  /// **'Von deinem Konto abmelden?'**
  String get authSignOutConfirm;

  /// No description provided for @authSignOutConfirmDesc.
  ///
  /// In de, this message translates to:
  /// **'Deine Logbuchdaten bleiben auf diesem Gerät.'**
  String get authSignOutConfirmDesc;

  /// No description provided for @authSignOutOfflineWarning.
  ///
  /// In de, this message translates to:
  /// **'Du bist offline. Ohne Verbindung kannst du dich danach nicht wieder anmelden.'**
  String get authSignOutOfflineWarning;

  /// No description provided for @authErrorInvalidEmail.
  ///
  /// In de, this message translates to:
  /// **'Ungültige E-Mail-Adresse.'**
  String get authErrorInvalidEmail;

  /// No description provided for @authErrorWrongPassword.
  ///
  /// In de, this message translates to:
  /// **'Falsches Passwort.'**
  String get authErrorWrongPassword;

  /// No description provided for @authErrorUserNotFound.
  ///
  /// In de, this message translates to:
  /// **'Kein Konto für diese E-Mail gefunden.'**
  String get authErrorUserNotFound;

  /// No description provided for @authErrorEmailInUse.
  ///
  /// In de, this message translates to:
  /// **'Ein Konto mit dieser E-Mail existiert bereits.'**
  String get authErrorEmailInUse;

  /// No description provided for @authErrorWeakPassword.
  ///
  /// In de, this message translates to:
  /// **'Das Passwort ist zu schwach.'**
  String get authErrorWeakPassword;

  /// No description provided for @authErrorGeneric.
  ///
  /// In de, this message translates to:
  /// **'Etwas ist schiefgelaufen. Bitte versuche es erneut.'**
  String get authErrorGeneric;

  /// No description provided for @authErrorNetworkFailed.
  ///
  /// In de, this message translates to:
  /// **'Keine Internetverbindung.'**
  String get authErrorNetworkFailed;

  /// No description provided for @authErrorTooManyRequests.
  ///
  /// In de, this message translates to:
  /// **'Zu viele Versuche. Bitte versuche es später erneut.'**
  String get authErrorTooManyRequests;

  /// No description provided for @authErrorUserDisabled.
  ///
  /// In de, this message translates to:
  /// **'Dieses Konto wurde deaktiviert. Bitte kontaktiere den Support.'**
  String get authErrorUserDisabled;

  /// No description provided for @authErrorRequiresRecentLogin.
  ///
  /// In de, this message translates to:
  /// **'Bitte melde dich ab und wieder an, bevor du dein Konto löschst.'**
  String get authErrorRequiresRecentLogin;

  /// No description provided for @authVerifyEmailTitle.
  ///
  /// In de, this message translates to:
  /// **'E-Mail bestätigen'**
  String get authVerifyEmailTitle;

  /// No description provided for @authVerifyEmailBody.
  ///
  /// In de, this message translates to:
  /// **'Wir haben einen Bestätigungslink an {email} gesendet.\nTippe auf den Link und dann auf die Schaltfläche unten.'**
  String authVerifyEmailBody(String email);

  /// No description provided for @authVerifyEmailCheck.
  ///
  /// In de, this message translates to:
  /// **'E-Mail bestätigt'**
  String get authVerifyEmailCheck;

  /// No description provided for @authVerifyEmailResend.
  ///
  /// In de, this message translates to:
  /// **'Bestätigungs-E-Mail erneut senden'**
  String get authVerifyEmailResend;

  /// No description provided for @authVerifyEmailSent.
  ///
  /// In de, this message translates to:
  /// **'Bestätigungs-E-Mail gesendet'**
  String get authVerifyEmailSent;

  /// No description provided for @settingsAccountSection.
  ///
  /// In de, this message translates to:
  /// **'Konto'**
  String get settingsAccountSection;

  /// No description provided for @settingsAccountInfo.
  ///
  /// In de, this message translates to:
  /// **'Anmeldung und Konto verwalten.'**
  String get settingsAccountInfo;

  /// No description provided for @settingsAccountSignedInAs.
  ///
  /// In de, this message translates to:
  /// **'Angemeldet als'**
  String get settingsAccountSignedInAs;

  /// No description provided for @settingsAccountNotSignedIn.
  ///
  /// In de, this message translates to:
  /// **'Nicht angemeldet'**
  String get settingsAccountNotSignedIn;

  /// No description provided for @settingsAccountManage.
  ///
  /// In de, this message translates to:
  /// **'Konto verwalten'**
  String get settingsAccountManage;

  /// No description provided for @authDeleteAccount.
  ///
  /// In de, this message translates to:
  /// **'Konto löschen'**
  String get authDeleteAccount;

  /// No description provided for @authDeleteAccountConfirm.
  ///
  /// In de, this message translates to:
  /// **'Konto löschen? Diese Aktion kann nicht rückgängig gemacht werden.'**
  String get authDeleteAccountConfirm;

  /// No description provided for @authDeleteCleanupFailedTitle.
  ///
  /// In de, this message translates to:
  /// **'Datenlöschung unvollständig'**
  String get authDeleteCleanupFailedTitle;

  /// No description provided for @authDeleteCleanupFailedBody.
  ///
  /// In de, this message translates to:
  /// **'Einige deiner Daten konnten nicht vom Server gelöscht werden. Dein Konto wurde nicht gelöscht.\n\nBitte versuche es erneut mit einer stabilen Internetverbindung. Falls das Problem weiterhin besteht, kontaktiere den Support – wir löschen deine Daten dann manuell.'**
  String get authDeleteCleanupFailedBody;

  /// No description provided for @settingsLogbooksSection.
  ///
  /// In de, this message translates to:
  /// **'Logbücher'**
  String get settingsLogbooksSection;

  /// No description provided for @settingsActiveLogbookHeader.
  ///
  /// In de, this message translates to:
  /// **'Aktives Logbuch: {name}'**
  String settingsActiveLogbookHeader(String name);

  /// No description provided for @settingsLogbooksInfo.
  ///
  /// In de, this message translates to:
  /// **'Logbücher verwalten, wechseln oder mit anderen teilen.'**
  String get settingsLogbooksInfo;

  /// No description provided for @settingsLocalLogbooksInfo.
  ///
  /// In de, this message translates to:
  /// **'Logbücher auf diesem Gerät verwalten oder wechseln. Kein Cloud-Backup — zum Sichern die Exportfunktion nutzen.'**
  String get settingsLocalLogbooksInfo;

  /// No description provided for @settingsDeleteLocalLogbookConfirm.
  ///
  /// In de, this message translates to:
  /// **'\"{name}\" löschen? Es gibt kein Cloud-Backup — dies kann nicht rückgängig gemacht werden, ausser du hast es bereits exportiert.'**
  String settingsDeleteLocalLogbookConfirm(String name);

  /// No description provided for @settingsMyLogbooks.
  ///
  /// In de, this message translates to:
  /// **'Meine Logbücher'**
  String get settingsMyLogbooks;

  /// No description provided for @settingsRoleOwner.
  ///
  /// In de, this message translates to:
  /// **'Eigentümer'**
  String get settingsRoleOwner;

  /// No description provided for @settingsRoleGuest.
  ///
  /// In de, this message translates to:
  /// **'Beitragender'**
  String get settingsRoleGuest;

  /// No description provided for @settingsNewLogbook.
  ///
  /// In de, this message translates to:
  /// **'Neues Logbuch'**
  String get settingsNewLogbook;

  /// No description provided for @settingsNewLogbookTitle.
  ///
  /// In de, this message translates to:
  /// **'Neues Logbuch erstellen'**
  String get settingsNewLogbookTitle;

  /// No description provided for @settingsNewLogbookHint.
  ///
  /// In de, this message translates to:
  /// **'Logbuchname'**
  String get settingsNewLogbookHint;

  /// No description provided for @settingsRename.
  ///
  /// In de, this message translates to:
  /// **'Umbenennen'**
  String get settingsRename;

  /// No description provided for @settingsShare.
  ///
  /// In de, this message translates to:
  /// **'Teilen'**
  String get settingsShare;

  /// No description provided for @settingsDeleteLogbook.
  ///
  /// In de, this message translates to:
  /// **'Logbuch löschen'**
  String get settingsDeleteLogbook;

  /// No description provided for @settingsLeaveLogbook.
  ///
  /// In de, this message translates to:
  /// **'Logbuch verlassen'**
  String get settingsLeaveLogbook;

  /// No description provided for @settingsShareCurrentLogbook.
  ///
  /// In de, this message translates to:
  /// **'Aktuelles Logbuch teilen'**
  String get settingsShareCurrentLogbook;

  /// No description provided for @settingsShowQrCode.
  ///
  /// In de, this message translates to:
  /// **'QR-Code anzeigen'**
  String get settingsShowQrCode;

  /// No description provided for @settingsManageGuests.
  ///
  /// In de, this message translates to:
  /// **'Beitragende verwalten'**
  String get settingsManageGuests;

  /// No description provided for @settingsNoGuests.
  ///
  /// In de, this message translates to:
  /// **'Keine Beitragenden'**
  String get settingsNoGuests;

  /// No description provided for @settingsRemoveGuestTitle.
  ///
  /// In de, this message translates to:
  /// **'Beitragende:n entfernen?'**
  String get settingsRemoveGuestTitle;

  /// No description provided for @settingsRemoveGuestConfirm.
  ///
  /// In de, this message translates to:
  /// **'\"{name}\" hat danach keinen Zugriff mehr auf dieses Logbuch.'**
  String settingsRemoveGuestConfirm(String name);

  /// No description provided for @settingsGuestRemoved.
  ///
  /// In de, this message translates to:
  /// **'Entfernt.'**
  String get settingsGuestRemoved;

  /// No description provided for @settingsSwitchTo.
  ///
  /// In de, this message translates to:
  /// **'Zu \"{name}\" wechseln?'**
  String settingsSwitchTo(String name);

  /// No description provided for @settingsDeleteLogbookConfirm.
  ///
  /// In de, this message translates to:
  /// **'\"{name}\" löschen? Diese Aktion kann nicht rückgängig gemacht werden.'**
  String settingsDeleteLogbookConfirm(String name);

  /// No description provided for @settingsLeaveLogbookConfirm.
  ///
  /// In de, this message translates to:
  /// **'\"{name}\" verlassen?'**
  String settingsLeaveLogbookConfirm(String name);

  /// No description provided for @settingsJoinContent.
  ///
  /// In de, this message translates to:
  /// **'Zu \"{name}\" beitreten? Dein aktuelles Logbuch bleibt erhalten – es wird ein neues hinzugefügt.'**
  String settingsJoinContent(String name);

  /// No description provided for @settingsJoinedLogbook.
  ///
  /// In de, this message translates to:
  /// **'Mit \"{name}\" verbunden.'**
  String settingsJoinedLogbook(String name);

  /// No description provided for @offlineBanner.
  ///
  /// In de, this message translates to:
  /// **'Offline — Änderungen lokal gespeichert'**
  String get offlineBanner;

  /// No description provided for @done.
  ///
  /// In de, this message translates to:
  /// **'Fertig'**
  String get done;

  /// No description provided for @save.
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get save;

  /// No description provided for @emergencyGuideTitle.
  ///
  /// In de, this message translates to:
  /// **'Notsignal-Handbuch'**
  String get emergencyGuideTitle;

  /// No description provided for @emergencyGuideIntro.
  ///
  /// In de, this message translates to:
  /// **'Kurzreferenz für internationale Seenotzeichen. Gewährleiste Sichtbarkeit und klare Kommunikation im Notfall.'**
  String get emergencyGuideIntro;

  /// No description provided for @emergencyVisualSignals.
  ///
  /// In de, this message translates to:
  /// **'Sichtsignale'**
  String get emergencyVisualSignals;

  /// No description provided for @emergencySoundSignals.
  ///
  /// In de, this message translates to:
  /// **'Schallsignale'**
  String get emergencySoundSignals;

  /// No description provided for @emergencyElectronicSignals.
  ///
  /// In de, this message translates to:
  /// **'Elektronische Signale'**
  String get emergencyElectronicSignals;

  /// No description provided for @emergencyPyrotechnicTitle.
  ///
  /// In de, this message translates to:
  /// **'Pyrotechnische Signale'**
  String get emergencyPyrotechnicTitle;

  /// No description provided for @emergencyPyrotechnicSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Rote Leuchtrakete (Handfeuer/Fallschirm) oder orangefarbener Rauch.'**
  String get emergencyPyrotechnicSubtitle;

  /// No description provided for @emergencyHighVisBadge.
  ///
  /// In de, this message translates to:
  /// **'SICHTBAR'**
  String get emergencyHighVisBadge;

  /// No description provided for @emergencyHandSignalTitle.
  ///
  /// In de, this message translates to:
  /// **'Handsignale'**
  String get emergencyHandSignalTitle;

  /// No description provided for @emergencyHandSignalSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Langsam und wiederholt die seitwärts ausgestreckten Arme heben und senken.'**
  String get emergencyHandSignalSubtitle;

  /// No description provided for @emergencyFlagSignalTitle.
  ///
  /// In de, this message translates to:
  /// **'Flaggensignale'**
  String get emergencyFlagSignalTitle;

  /// No description provided for @emergencyFlagSignalSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Quadratische Flagge mit einer Kugel darüber oder darunter oder Flaggen November über Charlie.'**
  String get emergencyFlagSignalSubtitle;

  /// No description provided for @emergencyGunTitle.
  ///
  /// In de, this message translates to:
  /// **'Schuss/Sprengmittel'**
  String get emergencyGunTitle;

  /// No description provided for @emergencyGunSubtitle.
  ///
  /// In de, this message translates to:
  /// **'In Abständen von etwa einer Minute abgefeuert.'**
  String get emergencyGunSubtitle;

  /// No description provided for @emergencyFoghornTitle.
  ///
  /// In de, this message translates to:
  /// **'Nebelhorn'**
  String get emergencyFoghornTitle;

  /// No description provided for @emergencyFoghornSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Anhaltender Ton mit einem beliebigen Nebelsignalgerät.'**
  String get emergencyFoghornSubtitle;

  /// No description provided for @emergencyEpirbTitle.
  ///
  /// In de, this message translates to:
  /// **'EPIRB / PLB'**
  String get emergencyEpirbTitle;

  /// No description provided for @emergencyEpirbSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Notpositionsanzeige-Funkbake. Sendet 406 MHz an COSPAS-SARSAT-Satelliten.'**
  String get emergencyEpirbSubtitle;

  /// No description provided for @emergencySartTitle.
  ///
  /// In de, this message translates to:
  /// **'SART'**
  String get emergencySartTitle;

  /// No description provided for @emergencySartSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Such- und Rettungstransponder. Erscheint als Linie aus 12 Punkten auf X-Band-Radargeräten.'**
  String get emergencySartSubtitle;

  /// No description provided for @emergencyRadioProtocolLabel.
  ///
  /// In de, this message translates to:
  /// **'Funkprotokoll (MAYDAY)'**
  String get emergencyRadioProtocolLabel;

  /// No description provided for @emergencyRadioProtocolTip.
  ///
  /// In de, this message translates to:
  /// **'UKW-Kanal 16. \"MAYDAY\" dreimal nennen, dann Schiffsname und Position.'**
  String get emergencyRadioProtocolTip;

  /// No description provided for @emergencyOpenChecklist.
  ///
  /// In de, this message translates to:
  /// **'FUNK-CHECKLISTE ÖFFNEN'**
  String get emergencyOpenChecklist;

  /// No description provided for @emergencyManifestTitle.
  ///
  /// In de, this message translates to:
  /// **'Notfall Manifest'**
  String get emergencyManifestTitle;

  /// No description provided for @maydayScreenTitle.
  ///
  /// In de, this message translates to:
  /// **'Funkprotokoll'**
  String get maydayScreenTitle;

  /// No description provided for @maydayStateThreeTimes.
  ///
  /// In de, this message translates to:
  /// **'(dreimal sagen)'**
  String get maydayStateThreeTimes;

  /// No description provided for @emergencyDistressGuideSubtitle.
  ///
  /// In de, this message translates to:
  /// **'Visuelle, akustische & elektronische Signale'**
  String get emergencyDistressGuideSubtitle;

  /// No description provided for @emergencyUrgentProcedure.
  ///
  /// In de, this message translates to:
  /// **'NOTFALLVERFAHREN'**
  String get emergencyUrgentProcedure;

  /// No description provided for @emergencyFollowScript.
  ///
  /// In de, this message translates to:
  /// **'Dieses Skript exakt befolgen. Auf UKW-Kanal 16 senden.'**
  String get emergencyFollowScript;

  /// No description provided for @emergencyDscAction1.
  ///
  /// In de, this message translates to:
  /// **'Rote Abdeckung über dem Notrufknopf öffnen'**
  String get emergencyDscAction1;

  /// No description provided for @emergencyDscAction2.
  ///
  /// In de, this message translates to:
  /// **'Drücken und halten (3–5 Sekunden, je nach Funkgerät) bis der Alarm gesendet ist'**
  String get emergencyDscAction2;

  /// No description provided for @emergencyDscWait.
  ///
  /// In de, this message translates to:
  /// **'Warten bis das Funkgerät automatisch auf Kanal 16 wechselt'**
  String get emergencyDscWait;

  /// No description provided for @emergencyIdentifyVessel.
  ///
  /// In de, this message translates to:
  /// **'Fahrzeug eindeutig identifizieren:'**
  String get emergencyIdentifyVessel;

  /// No description provided for @emergencyPositionUnavailable.
  ///
  /// In de, this message translates to:
  /// **'Position nicht verfügbar'**
  String get emergencyPositionUnavailable;

  /// No description provided for @emergencyAcquiringGps.
  ///
  /// In de, this message translates to:
  /// **'GPS wird ermittelt…'**
  String get emergencyAcquiringGps;

  /// No description provided for @emergencyCriticalTips.
  ///
  /// In de, this message translates to:
  /// **'Wichtige Protokollhinweise'**
  String get emergencyCriticalTips;

  /// No description provided for @emergencyTipCalmTitle.
  ///
  /// In de, this message translates to:
  /// **'Ruhe bewahren:'**
  String get emergencyTipCalmTitle;

  /// No description provided for @emergencyTipCalmBody.
  ///
  /// In de, this message translates to:
  /// **'Tief durchatmen vor dem Sprechen. Panik macht die Übertragung unverständlich.'**
  String get emergencyTipCalmBody;

  /// No description provided for @emergencyTipEnunciateTitle.
  ///
  /// In de, this message translates to:
  /// **'Deutlich sprechen:'**
  String get emergencyTipEnunciateTitle;

  /// No description provided for @emergencyTipEnunciateBody.
  ///
  /// In de, this message translates to:
  /// **'Langsam und deutlich sprechen. Zahlen einzeln aussprechen (z.B. \"Fünf-Null\" für 50).'**
  String get emergencyTipEnunciateBody;

  /// No description provided for @emergencyTipListenTitle.
  ///
  /// In de, this message translates to:
  /// **'Zuhören:'**
  String get emergencyTipListenTitle;

  /// No description provided for @emergencyTipListenBody.
  ///
  /// In de, this message translates to:
  /// **'Sendetaste loslassen und 15 Sekunden auf Bestätigung warten, bevor wiederholt wird.'**
  String get emergencyTipListenBody;

  /// No description provided for @emergencyManifestEditDoneTooltip.
  ///
  /// In de, this message translates to:
  /// **'Fertig'**
  String get emergencyManifestEditDoneTooltip;

  /// No description provided for @emergencyManifestEditPageTooltip.
  ///
  /// In de, this message translates to:
  /// **'Seite bearbeiten'**
  String get emergencyManifestEditPageTooltip;

  /// No description provided for @emergencyProtocolBadge.
  ///
  /// In de, this message translates to:
  /// **'PROTOKOLL'**
  String get emergencyProtocolBadge;

  /// No description provided for @emergencyRadioProtocolShort.
  ///
  /// In de, this message translates to:
  /// **'Funkprotokoll\n(MAYDAY)'**
  String get emergencyRadioProtocolShort;

  /// No description provided for @emergencyVisualAidBadge.
  ///
  /// In de, this message translates to:
  /// **'SICHTHILFE'**
  String get emergencyVisualAidBadge;

  /// No description provided for @emergencyGuideShort.
  ///
  /// In de, this message translates to:
  /// **'Notsignal-\nHandbuch'**
  String get emergencyGuideShort;

  /// No description provided for @emergencyContactsSection.
  ///
  /// In de, this message translates to:
  /// **'NOTFALLKONTAKTE'**
  String get emergencyContactsSection;

  /// No description provided for @emergencyVesselSafetySection.
  ///
  /// In de, this message translates to:
  /// **'SICHERHEITSINFO SCHIFF'**
  String get emergencyVesselSafetySection;

  /// No description provided for @emergencyNoSafetyData.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Sicherheitsdaten erfasst.'**
  String get emergencyNoSafetyData;

  /// No description provided for @emergencyFrequenciesSection.
  ///
  /// In de, this message translates to:
  /// **'FUNKFREQUENZEN'**
  String get emergencyFrequenciesSection;

  /// No description provided for @emergencyCrewMedicalSection.
  ///
  /// In de, this message translates to:
  /// **'MEDIZINISCHE BESATZUNGSÜBERSICHT'**
  String get emergencyCrewMedicalSection;

  /// No description provided for @emergencyCrewAutoNote.
  ///
  /// In de, this message translates to:
  /// **'Automatisch aus dem aktuellsten Logeintrag übernommen.\nBesatzungsdaten werden im Logbuch gepflegt.'**
  String get emergencyCrewAutoNote;

  /// No description provided for @emergencyNoContacts.
  ///
  /// In de, this message translates to:
  /// **'Keine Notfallkontakte hinzugefügt.'**
  String get emergencyNoContacts;

  /// No description provided for @emergencyAddContactTitle.
  ///
  /// In de, this message translates to:
  /// **'Notfallkontakt hinzufügen'**
  String get emergencyAddContactTitle;

  /// No description provided for @emergencyContactNameLabel.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get emergencyContactNameLabel;

  /// No description provided for @emergencyContactRoleHint.
  ///
  /// In de, this message translates to:
  /// **'Rolle (z.B. Partner, Arzt)'**
  String get emergencyContactRoleHint;

  /// No description provided for @emergencyContactPhoneLabel.
  ///
  /// In de, this message translates to:
  /// **'Telefonnummer'**
  String get emergencyContactPhoneLabel;

  /// No description provided for @emergencyContactDeleted.
  ///
  /// In de, this message translates to:
  /// **'{name} entfernt.'**
  String emergencyContactDeleted(String name);

  /// No description provided for @emergencyEditContactTitle.
  ///
  /// In de, this message translates to:
  /// **'Kontakt bearbeiten'**
  String get emergencyEditContactTitle;

  /// No description provided for @emergencyBloodBadge.
  ///
  /// In de, this message translates to:
  /// **'BLUT'**
  String get emergencyBloodBadge;

  /// No description provided for @emergencyNoFrequencies.
  ///
  /// In de, this message translates to:
  /// **'Keine Frequenzen konfiguriert.'**
  String get emergencyNoFrequencies;

  /// No description provided for @emergencyAddFrequencyTitle.
  ///
  /// In de, this message translates to:
  /// **'Frequenz hinzufügen'**
  String get emergencyAddFrequencyTitle;

  /// No description provided for @emergencyEditFrequencyTitle.
  ///
  /// In de, this message translates to:
  /// **'Frequenz bearbeiten'**
  String get emergencyEditFrequencyTitle;

  /// No description provided for @emergencyFrequencyChannelLabel.
  ///
  /// In de, this message translates to:
  /// **'Kanal'**
  String get emergencyFrequencyChannelLabel;

  /// No description provided for @emergencyFrequencyDescLabel.
  ///
  /// In de, this message translates to:
  /// **'Beschreibung'**
  String get emergencyFrequencyDescLabel;

  /// No description provided for @emergencyFrequencyDeleted.
  ///
  /// In de, this message translates to:
  /// **'{channel} entfernt.'**
  String emergencyFrequencyDeleted(String channel);

  /// No description provided for @emergencyNoCrewHint.
  ///
  /// In de, this message translates to:
  /// **'Keine Besatzungsmitglieder für heute hinzugefügt.'**
  String get emergencyNoCrewHint;

  /// No description provided for @emergencyOpenDayEntry.
  ///
  /// In de, this message translates to:
  /// **'Tageseintrag öffnen'**
  String get emergencyOpenDayEntry;

  /// No description provided for @emergencyLifeRaft.
  ///
  /// In de, this message translates to:
  /// **'Rettungsinsel'**
  String get emergencyLifeRaft;

  /// No description provided for @emergencyEpirbLocation.
  ///
  /// In de, this message translates to:
  /// **'EPIRB-Standort'**
  String get emergencyEpirbLocation;

  /// No description provided for @emergencyFireSuppression.
  ///
  /// In de, this message translates to:
  /// **'Feuerlöscher'**
  String get emergencyFireSuppression;

  /// No description provided for @navJournal.
  ///
  /// In de, this message translates to:
  /// **'Journal'**
  String get navJournal;

  /// No description provided for @navTracks.
  ///
  /// In de, this message translates to:
  /// **'Tracks'**
  String get navTracks;

  /// No description provided for @navSettings.
  ///
  /// In de, this message translates to:
  /// **'Einst.'**
  String get navSettings;

  /// No description provided for @navSafety.
  ///
  /// In de, this message translates to:
  /// **'Sicherheit'**
  String get navSafety;

  /// No description provided for @offlineLabel.
  ///
  /// In de, this message translates to:
  /// **'Offline'**
  String get offlineLabel;

  /// No description provided for @crewBloodGroupPrefix.
  ///
  /// In de, this message translates to:
  /// **'BG'**
  String get crewBloodGroupPrefix;

  /// No description provided for @pdfVoyageLog.
  ///
  /// In de, this message translates to:
  /// **'TAGEBUCH'**
  String get pdfVoyageLog;

  /// No description provided for @pdfNotes.
  ///
  /// In de, this message translates to:
  /// **'NOTIZEN'**
  String get pdfNotes;

  /// No description provided for @pdfDate.
  ///
  /// In de, this message translates to:
  /// **'DATUM'**
  String get pdfDate;

  /// No description provided for @pdfDistance.
  ///
  /// In de, this message translates to:
  /// **'DISTANZ'**
  String get pdfDistance;

  /// No description provided for @pdfAvgSpeedUnderway.
  ///
  /// In de, this message translates to:
  /// **'Ø IN FAHRT'**
  String get pdfAvgSpeedUnderway;

  /// No description provided for @pdfMax.
  ///
  /// In de, this message translates to:
  /// **'MAX'**
  String get pdfMax;

  /// No description provided for @pdfDuration.
  ///
  /// In de, this message translates to:
  /// **'FAHRZEIT'**
  String get pdfDuration;

  /// No description provided for @pdfStatistics.
  ///
  /// In de, this message translates to:
  /// **'STATISTIK'**
  String get pdfStatistics;

  /// No description provided for @pdfCrew.
  ///
  /// In de, this message translates to:
  /// **'CREW'**
  String get pdfCrew;

  /// No description provided for @pdfSkipper.
  ///
  /// In de, this message translates to:
  /// **'SKIPPER'**
  String get pdfSkipper;

  /// No description provided for @pdfCrewMember.
  ///
  /// In de, this message translates to:
  /// **'BESATZUNG'**
  String get pdfCrewMember;

  /// No description provided for @pdfLogEntries.
  ///
  /// In de, this message translates to:
  /// **'LOGBUCH-EINTRÄGE'**
  String get pdfLogEntries;

  /// No description provided for @pdfTimeCol.
  ///
  /// In de, this message translates to:
  /// **'Zeit'**
  String get pdfTimeCol;

  /// No description provided for @pdfCourseCol.
  ///
  /// In de, this message translates to:
  /// **'Kurs'**
  String get pdfCourseCol;

  /// No description provided for @pdfWindCol.
  ///
  /// In de, this message translates to:
  /// **'Wind'**
  String get pdfWindCol;

  /// No description provided for @pdfSeaCol.
  ///
  /// In de, this message translates to:
  /// **'See'**
  String get pdfSeaCol;

  /// No description provided for @pdfPositionCol.
  ///
  /// In de, this message translates to:
  /// **'Position'**
  String get pdfPositionCol;

  /// No description provided for @pdfRemarksCol.
  ///
  /// In de, this message translates to:
  /// **'Bemerkungen'**
  String get pdfRemarksCol;

  /// No description provided for @pdfTrackMap.
  ///
  /// In de, this message translates to:
  /// **'KURS & TRACK'**
  String get pdfTrackMap;

  /// No description provided for @pdfPassageTo.
  ///
  /// In de, this message translates to:
  /// **'Passage nach {destination}'**
  String pdfPassageTo(String destination);

  /// No description provided for @pdfDepartureFrom.
  ///
  /// In de, this message translates to:
  /// **'Abfahrt von {origin}'**
  String pdfDepartureFrom(String origin);

  /// No description provided for @pdfPageOf.
  ///
  /// In de, this message translates to:
  /// **'Seite {page} von {total}'**
  String pdfPageOf(int page, int total);

  /// No description provided for @pdfDepartureFromAt.
  ///
  /// In de, this message translates to:
  /// **'Abfahrt von {origin} um {time}'**
  String pdfDepartureFromAt(String origin, String time);

  /// No description provided for @pdfArrivalAt.
  ///
  /// In de, this message translates to:
  /// **'Ankunft um {time}'**
  String pdfArrivalAt(String time);

  /// No description provided for @pdfLocale.
  ///
  /// In de, this message translates to:
  /// **'de_CH'**
  String get pdfLocale;

  /// No description provided for @pdfGeneratedOn.
  ///
  /// In de, this message translates to:
  /// **'Erstellt am'**
  String get pdfGeneratedOn;

  /// No description provided for @homeExportRangeTooltip.
  ///
  /// In de, this message translates to:
  /// **'Zeitraum als PDF exportieren'**
  String get homeExportRangeTooltip;

  /// No description provided for @homeExportRangeConfirmTitle.
  ///
  /// In de, this message translates to:
  /// **'Als PDF exportieren?'**
  String get homeExportRangeConfirmTitle;

  /// No description provided for @homeExportRangeConfirmBody.
  ///
  /// In de, this message translates to:
  /// **'Dies exportiert jeden erfassten Tag zwischen {range} als ein einzelnes PDF.'**
  String homeExportRangeConfirmBody(String range);

  /// No description provided for @homeExportRangeConfirmButton.
  ///
  /// In de, this message translates to:
  /// **'Exportieren'**
  String get homeExportRangeConfirmButton;

  /// No description provided for @homeExportRangeInProgress.
  ///
  /// In de, this message translates to:
  /// **'PDF-Export wird vorbereitet…'**
  String get homeExportRangeInProgress;

  /// No description provided for @homeExportRangeEmpty.
  ///
  /// In de, this message translates to:
  /// **'Keine Logbucheinträge im gewählten Zeitraum.'**
  String get homeExportRangeEmpty;

  /// No description provided for @homeExportRangeSuccess.
  ///
  /// In de, this message translates to:
  /// **'PDF-Export bereit zum Teilen.'**
  String get homeExportRangeSuccess;

  /// No description provided for @homeExportRangeError.
  ///
  /// In de, this message translates to:
  /// **'PDF-Export fehlgeschlagen. Bitte erneut versuchen.'**
  String get homeExportRangeError;

  /// No description provided for @dayExportPdfInProgress.
  ///
  /// In de, this message translates to:
  /// **'PDF-Export wird vorbereitet…'**
  String get dayExportPdfInProgress;

  /// No description provided for @dayExportPdfSuccess.
  ///
  /// In de, this message translates to:
  /// **'PDF-Export bereit zum Teilen.'**
  String get dayExportPdfSuccess;

  /// No description provided for @dayExportPdfError.
  ///
  /// In de, this message translates to:
  /// **'PDF-Export fehlgeschlagen. Bitte erneut versuchen.'**
  String get dayExportPdfError;

  /// No description provided for @backupExportTitle.
  ///
  /// In de, this message translates to:
  /// **'Alle Daten exportieren'**
  String get backupExportTitle;

  /// No description provided for @backupExportDescription.
  ///
  /// In de, this message translates to:
  /// **'Sichert alle Tageseinträge, GPS-Tracks, die Besatzungsliste, Notfallkontakte und Fotos dieses Logbuchs in einer einzigen Datei.'**
  String get backupExportDescription;

  /// No description provided for @backupExportButton.
  ///
  /// In de, this message translates to:
  /// **'Alle Daten exportieren'**
  String get backupExportButton;

  /// No description provided for @backupExportInProgress.
  ///
  /// In de, this message translates to:
  /// **'Backup wird vorbereitet…'**
  String get backupExportInProgress;

  /// No description provided for @backupExportSuccess.
  ///
  /// In de, this message translates to:
  /// **'Backup bereit zum Teilen.'**
  String get backupExportSuccess;

  /// No description provided for @backupExportError.
  ///
  /// In de, this message translates to:
  /// **'Backup-Export fehlgeschlagen. Bitte erneut versuchen.'**
  String get backupExportError;

  /// No description provided for @backupRestoreTitle.
  ///
  /// In de, this message translates to:
  /// **'Aus Datei wiederherstellen'**
  String get backupRestoreTitle;

  /// No description provided for @backupRestoreDescription.
  ///
  /// In de, this message translates to:
  /// **'Stellt ein zuvor exportiertes Backup wieder her. Dabei werden alle vorhandenen Daten in diesem Logbuch ersetzt, nicht zusammengeführt.'**
  String get backupRestoreDescription;

  /// No description provided for @backupRestoreButton.
  ///
  /// In de, this message translates to:
  /// **'Aus Datei wiederherstellen'**
  String get backupRestoreButton;

  /// No description provided for @backupRestoreConfirmTitle.
  ///
  /// In de, this message translates to:
  /// **'Alle Daten ersetzen?'**
  String get backupRestoreConfirmTitle;

  /// No description provided for @backupRestoreConfirmBody.
  ///
  /// In de, this message translates to:
  /// **'Beim Wiederherstellen dieses Backups werden alle Tageseinträge, Tracks, Besatzungsmitglieder und Notfallkontakte in diesem Logbuch dauerhaft ersetzt. Dies kann nicht rückgängig gemacht werden.'**
  String get backupRestoreConfirmBody;

  /// No description provided for @backupRestoreInProgress.
  ///
  /// In de, this message translates to:
  /// **'Backup wird wiederhergestellt…'**
  String get backupRestoreInProgress;

  /// No description provided for @backupRestoreSuccess.
  ///
  /// In de, this message translates to:
  /// **'Backup wiederhergestellt.'**
  String get backupRestoreSuccess;

  /// No description provided for @backupRestoreInvalidFile.
  ///
  /// In de, this message translates to:
  /// **'Diese Datei ist kein gültiges Logbook-Backup.'**
  String get backupRestoreInvalidFile;

  /// No description provided for @backupRestoreSchemaTooNew.
  ///
  /// In de, this message translates to:
  /// **'Dieses Backup wurde mit einer neueren App-Version erstellt und kann hier nicht wiederhergestellt werden.'**
  String get backupRestoreSchemaTooNew;

  /// No description provided for @backupRestoreError.
  ///
  /// In de, this message translates to:
  /// **'Wiederherstellung fehlgeschlagen. Bitte erneut versuchen.'**
  String get backupRestoreError;

  /// No description provided for @amendmentDialogTitle.
  ///
  /// In de, this message translates to:
  /// **'Eintrag korrigieren'**
  String get amendmentDialogTitle;

  /// No description provided for @amendmentReasonLabel.
  ///
  /// In de, this message translates to:
  /// **'Grund der Korrektur'**
  String get amendmentReasonLabel;

  /// No description provided for @amendmentReasonHint.
  ///
  /// In de, this message translates to:
  /// **'z.B. Windrichtung nach Kontrolle korrigiert'**
  String get amendmentReasonHint;

  /// No description provided for @amendmentBadgeSingle.
  ///
  /// In de, this message translates to:
  /// **'Korrigiert · {date}'**
  String amendmentBadgeSingle(String date);

  /// No description provided for @amendmentBadgeMultiple.
  ///
  /// In de, this message translates to:
  /// **'{count}× korrigiert · zuletzt {date}'**
  String amendmentBadgeMultiple(int count, String date);

  /// No description provided for @amendmentHistoryTitle.
  ///
  /// In de, this message translates to:
  /// **'Korrekturhistorie'**
  String get amendmentHistoryTitle;

  /// No description provided for @amendmentCurrent.
  ///
  /// In de, this message translates to:
  /// **'Aktuell'**
  String get amendmentCurrent;

  /// No description provided for @amendmentOriginal.
  ///
  /// In de, this message translates to:
  /// **'Originaleintrag'**
  String get amendmentOriginal;

  /// No description provided for @amendmentNoReason.
  ///
  /// In de, this message translates to:
  /// **'Kein Grund angegeben'**
  String get amendmentNoReason;

  /// No description provided for @importLabel.
  ///
  /// In de, this message translates to:
  /// **'Importieren'**
  String get importLabel;

  /// No description provided for @gpxShareErrorEncoding.
  ///
  /// In de, this message translates to:
  /// **'Diese Datei konnte nicht gelesen werden. Exportiere sie erneut aus der Quell-App.'**
  String get gpxShareErrorEncoding;

  /// No description provided for @gpxShareErrorInvalidXml.
  ///
  /// In de, this message translates to:
  /// **'Diese Datei ist kein gültiges GPX-Format.'**
  String get gpxShareErrorInvalidXml;

  /// No description provided for @gpxShareErrorRoutesOnly.
  ///
  /// In de, this message translates to:
  /// **'Diese Datei enthält eine geplante Route, keine aufgezeichnete Strecke. Nur aufgezeichnete Strecken können importiert werden.'**
  String get gpxShareErrorRoutesOnly;

  /// No description provided for @gpxShareErrorWaypointsOnly.
  ///
  /// In de, this message translates to:
  /// **'Diese Datei enthält nur Wegpunkte, keine Strecke.'**
  String get gpxShareErrorWaypointsOnly;

  /// No description provided for @gpxShareErrorEmpty.
  ///
  /// In de, this message translates to:
  /// **'In dieser Datei wurden keine Streckendaten gefunden.'**
  String get gpxShareErrorEmpty;

  /// No description provided for @gpxShareMultiDay.
  ///
  /// In de, this message translates to:
  /// **'Diese Strecke erstreckt sich über {count} Tage ({first} – {last}). Welchem Tag soll sie zugeordnet werden?'**
  String gpxShareMultiDay(int count, String first, String last);

  /// No description provided for @gpxShareNoTimestamps.
  ///
  /// In de, this message translates to:
  /// **'Diese Strecke enthält keine Zeitstempel. Welchem Tag gehört sie an?'**
  String get gpxShareNoTimestamps;

  /// No description provided for @gpxShareConflictIncoming.
  ///
  /// In de, this message translates to:
  /// **'Neu: {date} · {points} Punkte · {start}–{end}'**
  String gpxShareConflictIncoming(
    String date,
    int points,
    String start,
    String end,
  );

  /// No description provided for @gpxShareConflictExisting.
  ///
  /// In de, this message translates to:
  /// **'Vorhanden: {date} · {points} Punkte · {start}–{end}'**
  String gpxShareConflictExisting(
    String date,
    int points,
    String start,
    String end,
  );

  /// No description provided for @gpxShareMergedNote.
  ///
  /// In de, this message translates to:
  /// **'{count} Strecken aus dieser Datei wurden zusammengeführt.'**
  String gpxShareMergedNote(int count);

  /// No description provided for @gpxShareActionReplace.
  ///
  /// In de, this message translates to:
  /// **'Ersetzen'**
  String get gpxShareActionReplace;

  /// No description provided for @gpxShareActionMerge.
  ///
  /// In de, this message translates to:
  /// **'Zusammenführen'**
  String get gpxShareActionMerge;

  /// No description provided for @gpxShareActionDifferent.
  ///
  /// In de, this message translates to:
  /// **'Anderes Datum'**
  String get gpxShareActionDifferent;

  /// No description provided for @gpxShareImported.
  ///
  /// In de, this message translates to:
  /// **'Strecke importiert → {date}'**
  String gpxShareImported(String date);

  /// No description provided for @gpxImportTitle.
  ///
  /// In de, this message translates to:
  /// **'GPX importieren'**
  String get gpxImportTitle;

  /// No description provided for @gpxImportAssignDay.
  ///
  /// In de, this message translates to:
  /// **'Tag zuordnen'**
  String get gpxImportAssignDay;

  /// No description provided for @gpxImportNewEntry.
  ///
  /// In de, this message translates to:
  /// **'Ein neuer Logeintrag wird erstellt'**
  String get gpxImportNewEntry;

  /// No description provided for @gpxImportConflict.
  ///
  /// In de, this message translates to:
  /// **'Für diesen Tag existiert bereits ein Track'**
  String get gpxImportConflict;

  /// No description provided for @gpxImportPoints.
  ///
  /// In de, this message translates to:
  /// **'{count} Streckenpunkte'**
  String gpxImportPoints(int count);

  /// No description provided for @gpxImportDateMismatch.
  ///
  /// In de, this message translates to:
  /// **'Track-Datum in der Datei ist {date} — bist du sicher?'**
  String gpxImportDateMismatch(String date);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
