// parity_test.dart, the core engine against the model of the graphical app.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// Run with:  flutter test test/core/parity_test.dart
//
// `lib/core/` reimplements the algorithm of `lib/model/unit_group.dart` in
// pure Dart (no Flutter), because a command line program cannot read the
// Flutter asset bundle nor the shared preferences.  Two copies of an
// algorithm drift apart as soon as one of them is edited alone: this test
// reduces every unit of the database and converts a matrix of values with
// both implementations, and fails on the first difference.
//
// Known, deliberate divergence: six entries of `assets/units.json` store
// their factor with a Unicode minus sign (`2.176434e-8`).  The core
// normalises the sign before reading the number, the model hands the raw
// text to `eval_ex`; those six units are tested separately at the end
// instead of being compared.

import 'dart:convert' show json;
import 'dart:io' show File;
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

// The core, in pure Dart.
import 'package:convertall/core/conversion_engine.dart' as core;
import 'package:convertall/core/unit_database.dart' as core;
import 'package:convertall/core/unit_exceptions.dart' as core;
import 'package:convertall/core/unit_expression.dart' as core;

// The model of the graphical application.
import 'package:convertall/model/unit_controller.dart' as gui;
import 'package:convertall/model/unit_data.dart' as gui;
import 'package:convertall/model/unit_group.dart' as gui;

/// The unit data, read once from the data file of the repository.
List<dynamic> readUnitData() =>
    json.decode(File('assets/units.json').readAsStringSync()) as List<dynamic>;

/// The core engine over the real data file.
core.ConversionEngine buildCoreEngine() => core.ConversionEngine(
  core.UnitDatabase.fromJsonTexts(
    File('assets/units.json').readAsStringSync(),
  ),
);

/// Fill the unit data of the GUI model from the same file.
///
/// The graphical application does this in `UnitData.loadData()`, which reads
/// the Flutter asset bundle and the saved language preference; a test cannot
/// use either, and the parity of the conversion algorithm does not depend on
/// the language of the type names, so the fields are filled directly.
void loadModelData(List<dynamic> units) {
  final data = gui.UnitController.unitData..reset();
  for (final item in units) {
    final unit = gui.UnitDatum(item);
    data.unitList.add(unit);
    data.unitMap[unit.name.toLowerCase().replaceAll(' ', '')] = unit;
    if (!data.typeList.contains(unit.type)) data.typeList.add(unit.type);
  }
  data.typeList.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

/// The reduced form of [expression] with the model of the GUI (`null` when the
/// model cannot reduce it).
String? modelReduced(String expression) {
  final group = gui.UnitGroup()..parse(expression);
  if (!group.isValid) return null;
  // The reduction is private; `isCategoryMatch` is the public way to trigger
  // it, which is what the application calls before a conversion.
  final twin = gui.UnitGroup()..parse(expression);
  group.isCategoryMatch(twin);
  return group.reducedGroup?.toString();
}

/// The value of a conversion with the model of the GUI, or `null` when the
/// model refuses the conversion.
double? modelConvert(double value, String from, String to) {
  final fromGroup = gui.UnitGroup()..parse(from);
  final toGroup = gui.UnitGroup()..parse(to);
  if (!fromGroup.isValid || !toGroup.isValid) return null;
  if (!fromGroup.isCategoryMatch(toGroup)) return null;
  return fromGroup.convert(value, toGroup);
}

/// The value of a conversion with the core engine.
///
/// The core answers an exact rational whenever the two units are linear;
/// [Number.toDouble] gives the double the model computes, so that the two
/// implementations stay comparable bit for bit.
double coreConvert(double value, String from, String to) =>
    coreEngine.convert(value: '$value', from: from, to: to).value.toDouble();

late core.ConversionEngine coreEngine;

void main() {
  final units = readUnitData();

  setUpAll(() {
    coreEngine = buildCoreEngine();
    loadModelData(units);
  });

  group('data file', () {
    test('both implementations see the same units', () {
      expect(gui.UnitController.unitData.unitList.length, 626);
      expect(coreEngine.database.unitCount, 626);
      expect(gui.UnitController.unitData.typeList.length, 52);
      expect(coreEngine.database.canonicalTypes.length, 52);
    });
  });

  group('reduction', () {
    test('every unit reduces to the same base units', () {
      var compared = 0;
      final divergent = <String>[];
      for (final item in units) {
        final name = item['name'] as String;
        if (skipForUnicodeMinus.contains(name)) continue;
        final expected = modelReduced(name);
        final actual = core.UnitGroup.parse(name, coreEngine.database)
            .reducedText;
        if (expected != actual) {
          divergent.add('$name: model "$expected" != core "$actual"');
        }
        compared += 1;
      }
      expect(divergent, isEmpty, reason: divergent.join('\n'));
      // Guard against a test that compares nothing.
      expect(compared, 620);
    });

    test('every unit reduces with the same factor', () {
      final divergent = <String>[];
      for (final item in units) {
        final name = item['name'] as String;
        if (skipForUnicodeMinus.contains(name)) continue;
        final group = gui.UnitGroup()..parse(name);
        group.isCategoryMatch(gui.UnitGroup()..parse(name));
        final coreGroup = core.UnitGroup.parse(name, coreEngine.database);
        coreGroup.reduce();
        final actual = coreGroup.factor.toDouble();
        final tolerance = math.max(1e-15, group.factor.abs() * 1e-12);
        if ((group.factor - actual).abs() > tolerance) {
          divergent.add('$name: model ${group.factor} != core ${coreGroup.factor}');
        }
      }
      expect(divergent, isEmpty, reason: divergent.join('\n'));
    });

    test('compound expressions reduce the same way', () {
      for (final expression in expressions) {
        final expected = modelReduced(expression);
        final actual = core.UnitGroup.parse(expression, coreEngine.database)
            .reducedText;
        expect(actual, expected, reason: expression);
        // A reduced form that is empty on both sides would hide a problem.
        if (!expression.startsWith('#')) {
          expect(actual, isNotEmpty, reason: expression);
        }
      }
    });
  });

  group('conversion', () {
    test('the matrix of conversions gives the same values', () {
      var compared = 0;
      final divergent = <String>[];
      for (final conversion in conversions) {
        final value = conversion[0] as double;
        final from = conversion[1] as String;
        final to = conversion[2] as String;
        final expected = modelConvert(value, from, to);
        final actual = coreConvert(value, from, to);
        if (expected == null) {
          divergent.add('$value $from -> $to: the model refuses it');
          continue;
        }
        // The GUI deliberately accumulates binary factor rounding while the
        // core keeps rational factors. Compare their numeric results within a
        // scale-aware tolerance; equations are only specified to about 1e-9.
        final usesEquation =
            !core.UnitGroup.parse(from, coreEngine.database).isLinear ||
            !core.UnitGroup.parse(to, coreEngine.database).isLinear;
        final tolerance = usesEquation
            ? 1e-9
            : math.max(1e-15, expected.abs() * 1e-12);
        final same = (expected - actual).abs() <= tolerance;
        if (!same) {
          divergent.add('$value $from -> $to: $expected != $actual');
        }
        compared += 1;
      }
      expect(divergent, isEmpty, reason: divergent.join('\n'));
      expect(compared, conversions.length);
    });

    test('both implementations agree on what cannot be converted', () {
      for (final conversion in impossibleConversions) {
        final value = conversion[0] as double;
        final from = conversion[1] as String;
        final to = conversion[2] as String;
        expect(
          modelConvert(value, from, to),
          isNull,
          reason: '$from -> $to should be refused by the model',
        );
        expect(
          () => coreConvert(value, from, to),
          throwsA(isA<core.UnitConversionException>()),
          reason: '$from -> $to should be refused by the core',
        );
      }
    });
  });

  group('known divergences', () {
    test('the six units with a Unicode minus carry the right factor', () {
      // `assets/units.json` writes the factor of these six entries with a
      // Unicode minus sign, e.g. "2.176434e\u22128 kg".  The core normalises
      // the sign, so the value is exact; the model gives the raw text to
      // `eval_ex`, whose handling of U+2212 decides the outcome.  The values
      // below are the ones the data means, and the ones the CLI, the MCP
      // server and `conversion_engine_test.dart` rely on.
      const expectedFactors = <String, double>{
        'Planck mass': 2.176434e-8,
        'Planck length': 1.616255e-35,
        'Planck time': 5.391247e-44,
        'elementary charge': 1.602176634e-19,
        'Boltzmann constant': 1.380649e-23,
        'vacuum permittivity': 8.8541878188e-12,
      };
      expect(expectedFactors.length, skipForUnicodeMinus.length);
      for (final entry in expectedFactors.entries) {
        final details = coreEngine.describeUnit(entry.key);
        expect(
          details.factor.toDouble(),
          closeTo(entry.value, entry.value * 1e-12),
          reason: entry.key,
        );
      }
    });

    test('the core keeps the exact factors of the data file', () {
      // The exact engine reads `1/16.0` as the rational 1/16 and `2.54` as
      // 127/50, so the multiplications do not accumulate binary rounding.
      final mile = coreEngine.convert(value: '1', from: 'mile', to: 'km');
      expect(mile.isExact, isTrue);
      expect(mile.asFractionText, '25146/15625');
      expect(mile.value.toDouble(), 1.609344);
      final inch = coreEngine.convert(value: '1', from: 'in', to: 'cm');
      expect(inch.value.toDouble(), 2.54);
      final pounds = coreEngine.convert(value: '1', from: 'pound', to: 'kg');
      expect(pounds.value.toDouble(), 0.45359237);
      final ounces = coreEngine.convert(value: '16', from: 'ounce', to: 'pound');
      expect(ounces.asFractionText, '1');
    });

    test('the core reports an equation result near zero as zero', () {
      // eval_ex currently evaluates these equations with Decimal values, so
      // the GUI may already get zero. The core guarantees the public answer is
      // zero while still marking it approximate because an equation was used.
      expect(modelConvert(32.0, 'F', 'C'), closeTo(0.0, 1e-10));
      final freezing = coreEngine.convert(value: '32', from: 'F', to: 'C');
      expect(freezing.value.toDouble(), 0.0);
      expect(freezing.isExact, isFalse);
      expect(modelConvert(0.0, 'C', 'F'), closeTo(32.0, 1e-9));
      expect(coreConvert(0.0, 'C', 'F'), closeTo(32.0, 1e-9));
    });

    test('the factors of the other units are the ones of the data file', () {
      // A regression guard for the reading of the "<number> <unit>" form.
      expect(coreConvert(1.0, 'gram', 'kg'), 0.001);
      expect(coreConvert(1.0, 'km', 'm'), 1000);
      expect(coreConvert(1.0, 'mile', 'km'), 1.609344);
      expect(coreConvert(1.0, 'acre', 'm^2'), 4046.8564224);
      expect(coreConvert(1.0, 'kWh', 'J'), 3600000);
      expect(coreConvert(1.0, 'Btu', 'J'), 1055.05585262);
    });
  });
}

/// The units whose factor is stored with a Unicode minus sign: the model and
/// the core cannot be compared on them (see the "known divergences" group).
const skipForUnicodeMinus = <String>{
  'Planck mass',
  'Planck length',
  'Planck time',
  'elementary charge',
  'Boltzmann constant',
  'vacuum permittivity',
};

/// Expressions that both implementations must reduce identically.
const expressions = <String>[
  'km/hr',
  'm/s',
  'mi/hr',
  'm/s^2',
  'kg*m/s^2',
  'N*m',
  'W*h',
  'J/s',
  'ft*lbf/hr',
  'Btu/hr',
  'kg/m^3',
  'g/cm^3',
  'J/K',
  'farad/m',
  '1/s',
  '1/mol',
  'm^2',
  'm2',
  'm3',
  'm^-1',
  's^-1',
  'kg*m/(s^2)',
  '(kg*m)/(s^2)',
  'au/day',
  'light speed * day',
  'avogadro',
  'lambert',
  'W',
  'kWh',
  'mpg',
  'liter per 100 km',
  'deg C',
  'Celsius degree',
  'fluid ounce',
  'ounce troy',
  'cal',
  'kcal',
  'atm',
  'psi',
  'bit/s',
];

/// Conversions that both implementations must compute identically.
/// The value is given as a `double`, since the model receives its value from
/// the text field of the interface and not from a parser.
const conversions = <List<Object>>[
  [100.0, 'km/hr', 'm/s'],
  [60.0, 'mi/hr', 'km/hr'],
  [1.0, 'mile', 'km'],
  [1.0, 'mile', 'm'],
  [0.125, 'cup', 'ml'],
  [1.0, 'Btu', 'J'],
  [1.0, 'acre', 'm^2'],
  [1.0, 'kWh', 'J'],
  [1.0, 'g', 'kg'],
  [1000.0, 'kg', 'g'],
  [100.0, 'C', 'F'],
  [32.0, 'F', 'C'],
  [0.0, 'C', 'K'],
  [273.15, 'K', 'C'],
  [4.0, 'Gas mark', 'C'],
  [0.5, 'Gas mark', 'K'],
  [10.0, 'liter per 100 km', 'mpg'],
  [30.0, 'mpg', 'liter per 100 km'],
  [1.0, 'screw size', 'in'],
  [1.0, 'ton', 'kg'],
  [2.5, 'gallon', 'liter'],
  [1.0, 'psi', 'kPa'],
  [1.0, 'light year', 'm'],
  [1.0, 'nautical mile', 'm'],
  [3600.0, 's', 'hr'],
  [1.0, 'W', 'J/s'],
  [1.0, 'lambert', 'cd/cm^2'],
  [1.0, 'avogadro', '1/mol'],
  [8.0, 'bit', 'byte'],
  [1.0, 'byte', 'bit'],
];

/// Conversions both implementations must refuse: different quantities.
const impossibleConversions = <List<Object>>[
  [1.0, 'kg', 'm'],
  [1.0, 'C', 'kg'],
  [1.0, 'liter', 's'],
  [1.0, 'Btu', 'W'],
  [1.0, 'm^2', 'm^3'],
];
