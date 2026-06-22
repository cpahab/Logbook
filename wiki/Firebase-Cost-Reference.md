# Appendix B — Firebase Cost Reference

---

## Spark plan (free) limits

| Service | Free limit | What exceeds it |
|---------|-----------|-----------------|
| Firestore reads | 50,000 / day | Active users doing many reads on app open |
| Firestore writes | 20,000 / day | Heavy logging days with many timeline entries |
| Firestore storage | 1 GiB total | Approximately 1,300 users with a full year of entries |
| Firebase Storage | 5 GiB total | Approximately 500 users with 10 MB of GPX tracks each |
| Firebase Auth (email) | 10,000 MAU / month | Not a concern at early scale |
| Auth (Google / Apple) | Unlimited on Identity Platform | Always free |
| Cloud Functions invocations | 125,000 / month | Only relevant if billing webhooks are added |

---

## Blaze pricing (after free tier)

| Service | Price |
|---------|-------|
| Firestore reads | $0.06 per 100,000 |
| Firestore writes | $0.18 per 100,000 |
| Firestore storage | $0.18 per GiB/month |
| Firebase Storage | $0.026 per GiB/month |
| Cloud Functions | $0.40 per million invocations + compute time |

---

## Budget protection setup

In Firebase Console → Project Settings → Usage and billing:

1. Set a **budget alert at €20/month** (email notification to you)
2. Set a **spending limit at €50/month**

> **Important:** The spending limit prevents runaway costs but will cause Firestore
> writes to fail once hit — users will see sync errors rather than unexpected charges.
> This is the correct trade-off for a small independent app.

---

## GPX storage note

Firebase Storage is the most constrained free resource for this app.
GPX track files can be 1–10 MB each. At 500 users with 10 MB average:
that's 5 GB — right at the Spark plan limit.

Options if this becomes a constraint:
- Compress GPX files before upload (gzip reduces them 60–70%)
- Store only the most recent N tracks in Storage; older tracks local-only
- Move to Blaze plan (~€0.026/GB/month — 5 GB is €0.13/month, negligible)
