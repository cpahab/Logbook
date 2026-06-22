# 7. Cost Risk Analysis — Running the App for Free

Full reference data is in [Appendix B](Firebase-Cost-Reference).

---

## Firebase free tier capacity (Spark plan)

| Firebase service | Free tier limit | App usage at 500 users | Headroom |
|------------------|----------------|------------------------|----------|
| Firestore reads | 50,000/day | ~5,000/day | 10× margin |
| Firestore writes | 20,000/day | ~2,000/day | 10× margin |
| Firestore storage | 1 GB total | ~365 MB (365 entries × 1 KB × 1,000 users) | Adequate |
| Firebase Storage (GPX) | 5 GB total | ~5 GB (10 MB × 500 users) | At limit |
| Firebase Auth (email) | 10,000/month | Trivial | Fine |
| Auth (Google/Apple) | Unlimited on Identity Platform | — | Free |

---

## Blaze (pay-as-you-go) cost estimates

| Active users | Estimated monthly Firebase cost |
|-------------|--------------------------------|
| 100 | €0 (Spark free tier covers all) |
| 500 | €0–1 |
| 1,000 | €3–6 |
| 5,000 | €18–30 |
| 10,000 | €50–80 |

---

## Risk mitigation

- Set a Firebase billing budget **alert at €20/month** (email notification).
- Set a **hard spending cap at €50/month** (Firebase automatically disables billing — note: this also disables Firestore writes above the Spark limit, so users would see sync failures rather than unexpected charges).
- A runaway read/write bug is the main risk. Firebase's billing console shows per-operation usage in near-real-time — monitor this for the first week after any sync-related code change.

---

## Verdict

Running completely free is financially sound for the foreseeable life of a niche sailing logbook.
Getting to 1,000 active users — where cost reaches €5/month — is itself a significant milestone.
The entire first year of Firebase costs will likely be under €50 total.
