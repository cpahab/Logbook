import 'package:flutter/widgets.dart';
import 'app_localizations.dart';

/// Shorthand for looking up localized strings — `context.l10n.someKey`
/// instead of `AppLocalizations.of(context).someKey` at every call site.
extension BuildContextL10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
