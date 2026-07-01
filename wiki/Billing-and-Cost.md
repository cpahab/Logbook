# Billing & Cost Strategy

**Current decision:** no billing — absorb Firebase costs. **If costs ever grow:** web
subscription + token model (not App Store IAP), detailed below.

---

## The core principle

Firebase cost per active user is small — roughly €0.003–0.006/user/month. The question
isn't "how much does it cost" but "what model avoids paywall complexity in the app while
still allowing cost recovery if the app grows."

## Option comparison

| Model | Dev cost | User cost | Paywall in app | Effort |
|-------|----------|-----------|----------------|--------|
| Absorb Firebase costs (current) | $0–20/mo | None | None | Zero |
| Web subscription + token | $0 | ~€10/yr via Stripe | None — token entry only | ~2 weeks |
| CloudKit (Apple-only) | $0 | None (iCloud quota) | None | ~3 weeks, no Android |
| Full IAP paywall | Firebase costs | ~€2/yr via App Store | Yes — full Apple review | 6–8 weeks |

**Why not IAP:** 30% Apple cut, dedicated subscription review, RevenueCat integration,
paywall UI, webhook infra. Break-even is several hundred paying users — not where this
app is.

## Recommended approach

1. Firebase budget alert at €20/month (email notification).
2. Hard spending cap at €50/month. Note: Firebase disables billing entirely above the
   cap, which also blocks Firestore writes above the Spark free-tier limit — so users see
   sync failures rather than surprise charges. This is the correct trade-off for a small
   independent app.
3. Re-evaluate once there's real usage data; at ~500 active users the bill will likely be
   €2–4/month.
4. Only build the web-subscription model if cost recovery actually becomes necessary.

## Web subscription + token model (if/when needed)

Avoids App Store IAP entirely — explicitly permitted by Apple guidelines when the paid
service is delivered outside the app.

1. User pays via Stripe on a website; the webhook calls a Cloud Function that generates a
   UUID token and emails it.
2. User enters the token in Settings ("Activate sync").
3. A validation Cloud Function checks the token and marks `users/{uid}.subscription.status
   = "active"`.
4. Firestore rules gate write access on that subscription status.

No in-app purchase UI, no Apple billing review, no 30% platform fee.

---

## Firebase free-tier reference (Spark plan)

| Service | Free limit | Notes |
|---------|-----------|-------|
| Firestore reads | 50,000/day | ~10× headroom at 500 users |
| Firestore writes | 20,000/day | ~10× headroom at 500 users |
| Firestore storage | 1 GiB total | Enough for roughly 1,300 users' worth of entries |
| Firebase Storage (GPX tracks) | 5 GiB total | **Most constrained resource** — ~500 users at 10 MB average tracks hits this limit |
| Firebase Auth (email) | 10,000 MAU/month | Not a concern at any realistic scale here |
| Auth (Google/Apple via Identity Platform) | Unlimited | Always free |
| Cloud Functions | 125,000 invocations/month | Only relevant if the token-billing model above is ever built |

**Blaze (pay-as-you-go) estimates:** 100 users → €0 (within free tier) · 500 → €0–1 ·
1,000 → €3–6 · 5,000 → €18–30 · 10,000 → €50–80.

**GPX storage mitigation options**, if the 5 GiB Storage limit becomes a real constraint:
gzip GPX files before upload (60–70% smaller), keep only the most recent N tracks in
Storage with older tracks local-only in Hive, or just move to Blaze (5 GB there is
~€0.13/month — negligible once billing is active anyway).
