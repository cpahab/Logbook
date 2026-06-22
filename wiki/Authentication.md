# 4. Future Upgrade: Authentication

**Estimated effort:** ~20 working days
**Dependencies:** Android Firebase registration ([A2](Implementation-Prompts#a2--android-firebase-registration))
**Ready-to-paste prompt:** [Appendix A4](Implementation-Prompts#a4--authentication-email-apple-google)

---

## Decisions already made

- **Providers:** Email/Password, Apple Sign-In, Google Sign-In
- **No grace period** for existing users (developer is the only current user — clean cutover)
- **Platforms:** iOS, Android, macOS

---

## Data model change

The current Firestore structure is keyed by an `installationId` with no access control.
Authentication enables proper access control.

| | Today | After auth |
|--|-------|-----------|
| Firestore path | `logbooks/{installationId}/entries/…` | `boats/{boatId}/entries/…` |
| Access control | None — anyone with the code can read | Firestore rules: only members of the boat |
| User identity | None | `users/{uid}/profile → {boatId, email, createdAt}` |
| Multi-device share | Exchange 8-char installationId | Same boatId, second uid added to members array |
| Migration needed? | N/A (developer only) | Clean start — no migration scripts required |

---

## Android and macOS prerequisites

Before any auth work can be tested on Android or macOS:

- **Android:** Run `flutterfire configure --platforms=android`, add `google-services.json` to `android/app/`, set `applicationId` in `build.gradle`.
- **macOS:** Register a separate Firebase macOS app (currently shares the iOS appId — needs its own for correct Auth OAuth callbacks).
- **Sign in with Apple:** Add the capability to both iOS and macOS Xcode targets; add entitlement files.
- **Google Sign-In:** Add SHA-1 fingerprint to Firebase Console for Android; add reversed-client-id URL scheme to `Info.plist` for iOS.

---

## Work phases

| Phase | Work | Est. days |
|-------|------|-----------|
| 2.1 Platform setup | Firebase Android registration, macOS app separation, enable Auth providers, add `sign_in_with_apple` + `google_sign_in` packages, entitlements and URL schemes | 5 |
| 2.2 Auth UI | Login screen (email + Apple + Google), registration, forgot-password, auth state listener driving GoRouter redirect, account screen in Settings (sign out, delete account) | 5 |
| 2.3 Data model | New Firestore structure, Firestore Security Rules, FirestoreService refactor to use `boatId` from user profile | 5 |
| 2.4 Share model | "Connect another device" flow: enter boatId on second device → uid added to `boats/{boatId}/members`; disconnect / leave boat actions | 3 |
| 2.5 Auth QA | All three providers on all three platforms, account linking edge case, offline auth state persistence | 2 |

---

## Account linking edge case (required)

If a user signs in with Google using the same email address as an existing email/password account,
Firebase throws a `credential-already-in-use` error. The app must catch this and offer a "Link accounts" flow.

This is a required UX path — it is surprisingly common and App Store reviewers test it.

---

## Apple Sign-In requirement

Apple Sign-In is **mandatory** when any social login is offered on iOS (App Store rule 4.8).
Offering Google but not Apple is a rejection reason.
