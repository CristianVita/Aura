import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'l10n/app_localizations.dart';

extension AuraStrings on BuildContext {
  AppLocalizations get appStrings =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      lookupAppLocalizations(const Locale('ro'));

  String number(num value, {int? digits}) => NumberFormat(
    digits == null ? '0.###' : '0.${'0' * digits}',
    appStrings.localeName,
  ).format(value);

  String dateTime(DateTime value) =>
      DateFormat.yMd(appStrings.localeName).add_Hm().format(value);
}
