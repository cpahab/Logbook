# Logbook App — Wiki

A Flutter-based, offline-first sailing logbook for iOS, macOS, and Android.
This wiki documents the current architecture and behavior, and what's still planned.

---

## Contents

| Page | Summary |
|------|---------|
| [Current State](Current-State) | Tech stack, maturity notes, known platform issue |
| [Code Map](Code-Map) | What each source file does; the app's data flow/sync model |
| [Data Model](Data-Model) | Firestore schema, security rules, Hive boxes, sentinel encoding |
| [Features](Features) | Behavior-level walkthrough of every screen |
| [Architectural Decisions](Architectural-Decisions) | Key decisions recorded so they aren't re-litigated |
| [Billing & Cost](Billing-and-Cost) | Current no-billing decision, Firebase cost reference, fallback plan |
| [Roadmap](Roadmap) | What's left before App Store submission, and known gaps |

For a deep dive on the GPS track-cleaning algorithm specifically, see
`docs/GPS-Track-Filtering-Pipeline.docx` in the repository (not in this wiki — it's a
formal technical reference better suited to a standalone document).

---

*Repository: [cpahab/Logbook](https://github.com/cpahab/Logbook) · Current branch: main*
