/// Centralized route name constants, referenced by both the route
/// definitions (router.dart) and every navigation call site. Renaming or
/// restructuring a route's path means changing it in one place (router.dart)
/// instead of hunting down every hardcoded path string across the app, and
/// a typo'd constant name is a compile error instead of a silent runtime
/// navigation failure.
class AppRoute {
  AppRoute._();

  static const login = 'login';
  static const register = 'register';
  static const forgotPassword = 'forgotPassword';
  static const verifyEmail = 'verifyEmail';
  static const home = 'home';
  static const gpxImport = 'gpxImport';
  static const dayDetail = 'dayDetail';
  static const settings = 'settings';
  static const crewRoster = 'crewRoster';
  static const tracks = 'tracks';
  static const tracksFullscreen = 'tracksFullscreen';
  static const emergencyManifest = 'emergencyManifest';
  static const mayday = 'mayday';
  static const emergencyGuide = 'emergencyGuide';
}
