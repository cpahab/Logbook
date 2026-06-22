# 5. Future Upgrade: Billing & Cost Strategy

**Current recommendation:** No billing — absorb Firebase costs
**If costs grow:** Web subscription + token model (see below)
**Ready-to-paste prompt (if needed):** [Appendix A5](Implementation-Prompts#a5--web-subscription--token-billing-optional-implement-later)

---

## The core principle

The developer does not want to subsidise cloud storage costs. However, the actual Firebase
cost per user is very small — roughly €0.003–0.006 per active user per month. The question
is therefore not "how much does it cost" but "what model avoids paywall complexity in the app
while still recovering costs if the app grows."

---

## Option comparison

| Model | Dev cost | User cost | Paywall in app | Android | Effort |
|-------|----------|-----------|----------------|---------|--------|
| Absorb Firebase costs | $0–20/mo | None | None | Yes | Zero |
| CloudKit (Apple platforms only) | $0 | None (iCloud quota) | None | No | 3 weeks |
| Web subscription + token | $0 | ~€10/yr via Stripe | None — token entry only | Yes | 2 weeks |
| Local network sync (Bonjour) | $0 | None | None | Yes | 3 weeks |
| Full IAP paywall | Firebase costs | ~€2/yr via App Store | Yes — full Apple review | Yes | 6–8 weeks |

---

## Recommended approach

**Deploy without any billing now. Add web subscription later only if Firebase costs become real.**

1. Set a Firebase budget alert at €20/month (email notification).
2. Set a hard spending cap at €50/month (Firebase automatically disables billing — note: this also disables Firestore writes above the Spark limit, so users would see sync failures rather than unexpected charges).
3. At ~500 active users, evaluate whether the Firebase bill is meaningful. It will likely be €2–4/month.
4. If cost recovery is needed, implement the web subscription + token model.

> **Why not IAP now?** App Store IAP adds 30% Apple cut, a dedicated review process for subscriptions, RevenueCat integration complexity, paywall UI, Cloud Function webhook infrastructure, and ongoing subscription management. The break-even point is at several hundred paying users — not where the app is today.

---

## Web subscription + token model (detail)

This model avoids App Store IAP entirely and is explicitly permitted by Apple guidelines
when the service is delivered outside the app.

1. User visits `logbuch.app/sync` in a browser and pays via Stripe (e.g. €9.90/year).
2. Stripe webhook calls a Firebase Cloud Function that generates a UUID sync token and emails it to the user.
3. User enters the token in app Settings under "Sync-Code aktivieren."
4. The app sends the token to a Cloud Function that validates it and marks the user's Firestore subscription as active.
5. Firestore Security Rules gate write access on `subscription.status == "active"`.

**Result:** No in-app purchase UI, no Apple review for billing, no 30% platform fee.
