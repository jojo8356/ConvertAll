// database_locator.dart, finding and loading the unit data for the CLI and the
// MCP server.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// The graphical application loads the units through the Flutter asset bundle;
// a command line program has to find the file itself.  The order is: the
// `--units-file` option, then the `CONVERTALL_UNITS_FILE` environment
// variable, then a list of places relative to the script, the executable and
// the working directory.  The unit data is never modified, so a checkout and
// an installed copy behave the same.

import 'dart:io';

import '../core/unit_database.dart';
import '../core/unit_exceptions.dart';

/// The environment variable that overrides the unit data file.
const unitsFileEnvironmentVariable = 'CONVERTALL_UNITS_FILE';

/// The languages for which the unit type names are translated.
const supportedLanguages = <String>['en', 'fr'];

/// Resolve the path of `assets/units.json`.
///
/// Throws a [UnitDataException] with the list of the places that were tried
/// when nothing is found.
String locateUnitsFile({String? explicitPath, String? language}) {
  if (explicitPath != null && explicitPath.isNotEmpty) {
    return explicitPath;
  }
  final fromEnvironment = Platform.environment[unitsFileEnvironmentVariable];
  if (fromEnvironment != null && fromEnvironment.isNotEmpty) {
    return fromEnvironment;
  }
  final tried = <String>[];
  for (final candidate in unitsFileCandidates()) {
    tried.add(candidate);
    if (File(candidate).existsSync()) return candidate;
  }
  throw UnitDataException(
    'The unit data file was not found. Point to it with --units-file or with '
    'the $unitsFileEnvironmentVariable environment variable.\n'
    'Tried:\n  ${tried.join('\n  ')}',
  );
}

/// The paths tried by [locateUnitsFile], in order.
Iterable<String> unitsFileCandidates() sync* {
  final directories = <String>{};
  final script = Platform.script;
  if (script.scheme == 'file') {
    directories.add(File.fromUri(script).parent.path);
  }
  directories.add(File(Platform.resolvedExecutable).parent.path);
  var directory = Directory.current.path;
  directories.add(directory);
  // A checkout: bin/convertall.dart is two levels below the data file, so the
  // parents cover `dart run bin/convertall.dart` and `dart run` from anywhere
  // inside the repository.
  for (var level = 0; level < 4; level++) {
    final parent = Directory(directory).parent.path;
    if (parent == directory) break;
    directory = parent;
    directories.add(directory);
  }
  final seen = <String>{};
  for (final dir in directories) {
    for (final relative in const [
      'assets/units.json',
      '../assets/units.json',
      'data/units.json',
      'share/convertall/units.json',
      'convertall/assets/units.json',
    ]) {
      final path = _normalize('$dir/$relative');
      if (seen.add(path)) yield path;
    }
  }
}

/// The path of the translated type names for [language], or `null` for English
/// (which is the same file as the unit data) or when the file does not exist.
String? locateTypeNamesFile(String unitsPath, String? language) {
  if (language == null || language == 'en') return null;
  final candidate = '${File(unitsPath).parent.path}/units_$language.json';
  return File(candidate).existsSync() ? candidate : null;
}

/// Load the unit database.
///
/// [language] selects the file of translated type names when it exists;
/// `auto` follows the locale environment variables.
UnitDatabase loadDatabase({
  String? unitsFile,
  String? language,
  String? typeNamesFile,
}) {
  final resolvedLanguage = resolveLanguage(language);
  final path = locateUnitsFile(explicitPath: unitsFile, language: resolvedLanguage);
  final typesPath = typeNamesFile ?? locateTypeNamesFile(path, resolvedLanguage);
  return UnitDatabase.fromFiles(unitsPath: path, typeNamesPath: typesPath);
}

/// Resolve the language code: `auto` and the empty value follow `LC_ALL`,
/// `LC_MESSAGES` and `LANG`, anything unknown falls back to `en`.
String resolveLanguage(String? requested) {
  var code = requested?.trim().toLowerCase();
  if (code == null || code.isEmpty || code == 'auto') {
    code = Platform.environment['LC_ALL'] ??
        Platform.environment['LC_MESSAGES'] ??
        Platform.environment['LANG'] ??
        'en';
    code = code.trim().toLowerCase();
  }
  // `fr_FR.UTF-8`, `fr-fr`, `fr` all mean `fr`.
  final separator = code.indexOf(RegExp('[_@.]'));
  if (separator > 0) code = code.substring(0, separator);
  final dash = code.indexOf('-');
  if (dash > 0) code = code.substring(0, dash);
  if (supportedLanguages.contains(code)) return code;
  return 'en';
}

/// Remove the `..` segments of a path, so that the list shown to the user when
/// nothing is found stays readable.
String _normalize(String path) {
  final parts = <String>[];
  final absolute = path.startsWith('/');
  for (final segment in path.split(RegExp(r'[/\\]'))) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..' && parts.isNotEmpty && parts.last != '..') {
      parts.removeLast();
      continue;
    }
    parts.add(segment);
  }
  final joined = parts.join('/');
  return absolute ? '/$joined' : joined;
}
