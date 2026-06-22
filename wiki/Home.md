# Logbook App — Upgrade Planning & Architecture

A Flutter-based sailing logbook for iOS, macOS, and Android.
This wiki documents the architecture, completed changes, and planned upgrades.

---

## Contents

| # | Page | Summary |
|---|------|---------|
| 1 | [Current State](Current-State) | Technology stack and where the app stands today |
| 2 | [v1.0.17 Changes](v1.0.17-Changes) | All 17 items implemented in the v1.0.17 session |
| 3 | [Multilingual Support](Multilingual-Support) | German / English implementation plan |
| 4 | [Authentication](Authentication) | Email, Apple, Google auth design |
| 5 | [Billing & Cost Strategy](Billing-and-Cost-Strategy) | Free model, web subscription option |
| 6 | [Maps Provider Migration](Maps-Provider-Migration) | Required before App Store submission |
| 7 | [Cost Risk Analysis](Cost-Risk-Analysis) | Firebase cost estimates and risk mitigation |
| 8 | [Roadmap](Roadmap) | Sequenced plan to first public release |
| A | [Implementation Prompts](Implementation-Prompts) | Copy-paste prompts for future Claude Code sessions |
| B | [Firebase Cost Reference](Firebase-Cost-Reference) | Spark limits and Blaze pricing tables |
| C | [Architectural Decisions](Architectural-Decisions) | Key decisions recorded so they aren't re-litigated |

---

## Quick reference — what to do next

1. **Before any App Store submission:** [Switch map tiles to MapTiler + Esri](Maps-Provider-Migration) (2 days, no dependencies)
2. **For Android:** Register Android app in Firebase Console (see [prompt A2](Implementation-Prompts#a2--android-firebase-registration))
3. **Parallel tracks:** [i18n](Multilingual-Support) and [Auth Phase 2.1](Authentication) can start simultaneously

---

*Repository: [cpahab/Logbook](https://github.com/cpahab/Logbook) · Current branch: main*
