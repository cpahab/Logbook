/// Base type for app-specific exceptions. Currently unused — no subclass
/// exists yet in the codebase; error handling elsewhere throws/catches
/// platform and package exceptions directly instead.
class AppException implements Exception {}
