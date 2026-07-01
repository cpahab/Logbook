# Key Architectural Decisions Log

Decisions made during planning — recorded so they don't need to be re-litigated.
Status reflects what actually shipped, which sometimes differs in detail from the
original plan (noted below where it does).

| Decision | Choice made | Status | Reasoning |
|----------|------------|--------|-----------|
| Emergency Manifest / MAYDAY radio script language | Always English | **Implemented** | Maritime safety document used internationally; SOLAS/IMO convention. The rest of the emergency screens *are* localized normally — only the radio-script wording stays English. |
| Auth providers | Email/Password + Apple + Google | **Implemented** | Apple Sign-In is mandatory when offering any social login on iOS (App Store rule 4.8). Google covers Android. Email/Password as universal fallback. |
| Billing model (current) | No billing — absorb Firebase costs | **Standing decision** | Firebase cost is a few euros/month at 1,000 users. Not worth the complexity yet. Revisit if cost exceeds ~€20/month — see [Billing & Cost](Billing-and-Cost). |
| Billing model (if ever needed) | Web subscription + token (not App Store IAP) | Not implemented, kept as the plan | Avoids the 30% platform cut and IAP review; permitted under App Store guidelines when sync is framed as an external service. |
| Map tile provider | MapTiler (nautical + satellite styles) | **Implemented** | OSM's demo tile server and unauthenticated Esri tiles are both policy-violating for published apps. MapTiler is a drop-in `flutter_map` XYZ source with a nautical chart style relevant to sailors. |
| State management | `provider` package, `ChangeNotifier` | **Implemented, unchanged** | Correct for the app's complexity; no migration to Bloc/Riverpod undertaken or needed. |
| Data model | `logbooks/{logbookId}` (not the originally-planned `boats/{boatId}`) | **Implemented, naming differs from the original plan** | The plan predates a rename; the shipped model keeps `logbooks` as the collection name throughout (`logbooks/{id}/entries`, `/members`, `/meta/*`). Functionally equivalent to the plan: auth-gated, membership-based access via Firestore rules. See [Data Model](Data-Model). |
| Multi-device / multi-user share | Code-based join via `shareCodes/{code}` lookup + QR | **Implemented** | A user joins as a `guest` member of the target logbook; the owner manages membership. |
| i18n sentinel fix | Locale-neutral prefixes (`crew:`, `vs:`, `sail:`) in stored data; display strings resolved via `l10n` at render time | **Implemented, extended** | The original fix targeted the `"Besatzung: "` crew-note prefix specifically. The same pattern was extended to vessel-status notes (`vs:oil=…`) and sail state (`sail:full`, `sail:reef1`, …) so none of the persisted, cross-device data is language-locked. See `sail_state_utils.dart`. |
| Storage security rules | Authentication-only (not membership-gated) | **Standing decision, intentionally less strict than Firestore** | Logbook IDs are non-guessable Firestore auto-IDs, so auth alone is considered adequate for now. The stronger cross-service `isMember()` check is deferred until App Check is configured for release builds — see the comment in `storage.rules`. |
