// Feature flags — flip these constants to enable/disable features without
// touching any other code.

// When true, signed-in users with an unverified email address are redirected
// to the VerifyEmailScreen and cannot access the app until they confirm.
// The verification email is always sent on registration regardless of this flag.
// To activate: set to true, then enforce the rule in Firebase Console →
// Authentication → Settings → Email enumeration protection (optional).
const bool kEnforceEmailVerification = false;
