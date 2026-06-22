# 8. Recommended Roadmap & Sequencing

**Total elapsed time to first public release: 8–10 weeks**
(with i18n and auth Phase 2.1 running in parallel from week 1)

---

## Immediate — before App Store submission

1. Switch map tiles to MapTiler + Esri API key. (2 days — no dependencies)
   → See [Maps Provider Migration](Maps-Provider-Migration) and [Prompt A1](Implementation-Prompts#a1--map-tile-provider-switch-maptiler--esri)

2. Register Android app in Firebase Console; add `google-services.json`. (1 day)
   → See [Prompt A2](Implementation-Prompts#a2--android-firebase-registration)

---

## Short term — parallel tracks (can run concurrently)

3. **i18n: de/en** (11 days — independent of auth; Emergency Manifest stays English)
   → See [Multilingual Support](Multilingual-Support) and [Prompt A3](Implementation-Prompts#a3--multilingual-german--english)

4. **Auth Phase 2.1** — Firebase Android registration, macOS app separation, enable Auth providers (5 days — begin concurrently with i18n)
   → See [Authentication](Authentication) and [Prompt A4](Implementation-Prompts#a4--authentication-email-apple-google)

---

## Medium term — after auth

5. App Store Connect and Google Play setup, submissions.
6. Set Firebase budget alerts. Deploy without billing.

---

## Later — if/when needed

7. Web subscription + token billing model — only if Firebase cost becomes real or cost recovery is desired.
   → See [Billing & Cost Strategy](Billing-and-Cost-Strategy) and [Prompt A5](Implementation-Prompts#a5--web-subscription--token-billing-optional-implement-later)

8. Additional languages — once ARB infrastructure is in place, each new language is 2–3 days of translation.

9. Nautical chart enhancements — MapTiler nautical style + OpenSeaMap overlay for chart markers.

---

## Full calendar view

| Weeks | Work | Dependency |
|-------|------|-----------|
| 1 | Maps tile switch + Android Firebase registration | None — start here |
| 1–3 | i18n (parallel) | None |
| 2–3 | Auth Phase 2.1 — platform setup | After Android registration |
| 4–5 | Auth Phase 2.2–2.3 — auth UI + data model | After 2.1 |
| 6 | Auth Phase 2.4–2.5 — share model + QA | After 2.3 |
| 7–8 | App Store Connect + Google Play setup, submissions | After auth + i18n complete |
| 8+ | Apple review clock (1–2 weeks) | After submission |
| Later | Web billing (if needed) | Auth must be complete |
