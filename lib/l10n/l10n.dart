// l10n.dart, helpers for the translated messages and on-disk resources.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.

import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/widgets.dart';
import '../main.dart' show prefs;
import 'app_localizations.dart';

/// Shortcut for the generated [AppLocalizations.of], which returns a
/// non-null value (see `nullable-getter: false` in l10n.yaml).
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// The interface language: the saved preference, or the language of the
/// system when the preference is 'system' (the default). Only the languages
/// for which the app has translations are returned, 'en' otherwise.
///
/// This also selects the on-disk resources (the help pages and the unit type
/// names), which live in an 'en' version at the root of the assets and in a
/// per-language sub-directory for the other languages.
String get effectiveLanguage {
  final preference = prefs.getString('language') ?? 'system';
  var language = preference;
  if (language == 'system') {
    language = PlatformDispatcher.instance.locale.languageCode;
  }
  final supported = AppLocalizations.supportedLocales.any(
    (locale) => locale.languageCode == language,
  );
  return supported ? language : 'en';
}
