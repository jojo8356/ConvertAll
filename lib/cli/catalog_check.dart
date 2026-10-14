// catalog_check.dart, the validation of the unit catalogues.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// The equivalent of the Python `unitDataTest` (`source/cmdline.py`), run by
// `-t`, `--test` and `--test-all`: every unit of the catalogue is parsed,
// reduced to base units, its factor is checked (finite and positive) and its
// equation is evaluated, so that a malformed entry of the data file is caught
// before it reaches a user.  The messages and the exit status are the ones of
// the Python implementation: `units.json: 626 units`, then either
// `All units pass tests` or the failures grouped by message followed by
// `Impacts:  <units>`.
//
// The Dart tool reads `assets/units.json` instead of `assets/units.dat`, and a
// translated catalogue (`assets/units_fr.json`) carries the type names only:
// `--all` validates the unit data and then every translation next to it, which
// is the same intent (every installed catalogue is checked).

import 'dart:convert' show json;
import 'dart:io' show File;

import '../core/exact_number.dart';
import '../core/logging.dart';
import '../core/unit_database.dart';
import '../core/unit_exceptions.dart';
import '../core/unit_expression.dart';

/// The logger of the catalogue validation.
final _checkLog = loggerFor('check');

/// One failure of the validation: a message, and the units it touches.
class CatalogProblem {
  CatalogProblem(this.message, this.units);

  /// The reason, e.g. `Invalid conversion for "foo"`.
  final String message;

  /// The names of the units that raised it, sorted.
  final List<String> units;

  Map<String, Object?> toJson() => {'message': message, 'units': units};
}

/// The result of validating one catalogue.
class CatalogReport {
  CatalogReport({
    required this.name,
    required this.unitCount,
    required this.problems,
    this.path,
  });

  /// The file name, as the Python tool prints it (`units.dat`).
  final String name;

  /// The full path, for the JSON output.
  final String? path;

  /// The number of units (or translated names) that were read.
  final int unitCount;

  /// Every failure, grouped by message.
  final List<CatalogProblem> problems;

  /// True when nothing failed.
  bool get isValid => problems.isEmpty;

  Map<String, Object?> toJson() => {
    'name': name,
    if (path != null) 'path': path,
    'units': unitCount,
    'valid': isValid,
    if (problems.isNotEmpty)
      'problems': problems.map((problem) => problem.toJson()).toList(),
  };
}

/// Validate one catalogue.
///
/// [database] is the catalogue when the caller already read it (which is
/// always the case from the command line); it is read from [path] otherwise.
CatalogReport checkCatalogue(String? path, {UnitDatabase? database}) {
  final data = database ?? UnitDatabase.fromFiles(unitsPath: path!);
  final problems = <String, List<String>>{};
  void record(String message, String unit) =>
      problems.putIfAbsent(message, () => <String>[]).add(unit);

  for (final unit in data.units) {
    try {
      // The factor of the data entry itself: a catalogue that stores a
      // negative or an infinite factor must be refused here, not by a
      // surprising result at conversion time.
      if (!unit.factor.toDouble().isFinite || unit.factor.toDouble() <= 0) {
        record('Invalid factor for "${unit.name}"', unit.name);
        continue;
      }
      final group = UnitGroup.parse(unit.name, data);
      if (!group.isValid) {
        record('Invalid unit "${unit.name}"', unit.name);
        continue;
      }
      group.reduce();
      if (!group.isLinearOrLegal) {
        record('Invalid non-linear use of "${unit.name}"', unit.name);
        continue;
      }
      if (group.isLinear) {
        if (!group.factor.isFinite || group.factor.toDouble() <= 0) {
          record('Invalid conversion for "${unit.name}"', unit.name);
        }
        continue;
      }
      // Exercise the equation, or the interpolation table: reducing the
      // dimensions is not enough to find a malformed non-linear definition.
      final roundTrip = group.convert(Number.one, group);
      if (!roundTrip.isFinite) {
        record('Non-finite result for "${unit.name}"', unit.name);
      }
    } on UnitConversionException catch (error) {
      record(error.message, unit.name);
    } on UnitDataException catch (error) {
      record('$error', unit.name);
    } catch (error) {
      record('$error', unit.name);
    }
  }
  final sorted = problems.keys.toList()..sort();
  _checkLog.debug(
    '${data.unitCount} units checked, ${problems.length} distinct problem(s)',
  );
  return CatalogReport(
    name: path == null ? 'units.json' : _baseName(path),
    path: path,
    unitCount: data.unitCount,
    problems: [
      for (final message in sorted)
        CatalogProblem(message, problems[message]!..sort()),
    ],
  );
}

/// Validate every catalogue next to [unitsPath]: the unit data itself, then
/// every `units_<language>.json` translation file.
List<CatalogReport> checkEveryCatalogue(String? unitsPath) {
  final reports = <CatalogReport>[checkCatalogue(unitsPath)];
  if (unitsPath == null) return reports;
  final files = File(unitsPath)
      .parent
      .listSync()
      .whereType<File>()
      .where((file) => _isTranslation(_baseName(file.path)))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    reports.add(checkTranslation(file.path, unitsPath: unitsPath));
  }
  return reports;
}

/// Validate a type name translation: the file must be a JSON object of known
/// quantities, and every quantity of the unit data must be translated.
CatalogReport checkTranslation(String path, {required String unitsPath}) {
  final name = _baseName(path);
  final problems = <CatalogProblem>[];
  final data = UnitDatabase.fromFiles(unitsPath: unitsPath);
  final translations = <String, String>{};
  try {
    final decoded = json.decode(File(path).readAsStringSync());
    if (decoded is! Map) {
      problems.add(
        CatalogProblem('The translation must be a JSON object', const []),
      );
    } else {
      decoded.forEach((key, value) {
        if (key is String && value is String) {
          translations[key] = value;
        } else {
          problems.add(
            CatalogProblem('Invalid entry in the translation', ['$key']),
          );
        }
      });
    }
  } on FormatException catch (error) {
    problems.add(CatalogProblem('Invalid JSON: ${error.message}', const []));
  }
  final unknown = translations.keys
      .where((type) => !data.canonicalTypes.contains(type))
      .toList()
    ..sort();
  if (unknown.isNotEmpty) {
    problems.add(CatalogProblem('Unknown quantity in the translation', unknown));
  }
  final missing = data.canonicalTypes
      .where((type) => !translations.containsKey(type))
      .toList()
    ..sort();
  if (missing.isNotEmpty) {
    problems.add(
      CatalogProblem('Missing translation for ${missing.length} quantities', missing),
    );
  }
  if (problems.isEmpty) {
    _checkLog.debug('$name: ${translations.length} translated names checked');
  }
  return CatalogReport(
    name: name,
    path: path,
    unitCount: translations.length,
    problems: problems,
  );
}

bool _isTranslation(String name) =>
    name.startsWith('units_') && name.endsWith('.json');

String _baseName(String path) => path.split(RegExp(r'[/\\]')).last;
