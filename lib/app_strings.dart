import 'package:flutter/widgets.dart';

import 'l10n/app_localizations.dart';

extension AuraStrings on BuildContext {
  AppLocalizations get appStrings =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      lookupAppLocalizations(const Locale('ro'));
}
