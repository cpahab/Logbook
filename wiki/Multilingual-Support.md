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
