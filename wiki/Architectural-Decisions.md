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
