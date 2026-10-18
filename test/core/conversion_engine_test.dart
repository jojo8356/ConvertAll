// conversion_engine_test.dart, tests of the pure-Dart conversion core.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// Run with:  flutter test test/core/conversion_engine_test.dart
//
// The tests read the real `assets/units.json`, so they check the data as well
// as the code.  The expected numbers come from the graphical model
// (`lib/model/unit_group.dart`); `test/core/parity_test.dart` compares both
// implementations unit by unit.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rational/rational.dart';

import 'package:convertall/core/conversion_engine.dart';
import 'package:convertall/core/exact_number.dart';
import 'package:convertall/core/unit_database.dart';
import 'package:convertall/core/unit_exceptions.dart';

/// The engine under test, built from the unit data of the checkout.
ConversionEngine buildEngine() {
  final unitsJson = File('assets/units.json').readAsStringSync();
  return ConversionEngine(UnitDatabase.fromJsonTexts(unitsJson));
}

/// Assert that [actual] is within [relative] of [expected].
///
/// Accepts a [Number] as well as a `double`: the core returns an exact
/// rational for a conversion between linear units, and its double value is the
/// one the graphical model computes.
void expectClose(Object? actual, double expected, {double relative = 1e-12}) {
  final value = actual is Number ? actual.toDouble() : actual! as num;
  final tolerance = math.max(expected.abs() * relative, 1e-30);
  expect(
    value,
    closeTo(expected, tolerance),
    reason: '$actual is not within $relative of $expected',
  );
}

Matcher throwsConversionError(String code) => throwsA(
  isA<UnitConversionException>().having(
    (error) => error.code,
    'error code',
    code,
  ),
);

void main() {
  late ConversionEngine engine;

  setUpAll(() {
    engine = buildEngine();
  });

  group('unit database', () {
    test('loads the units of the application', () {
      expect(engine.database.unitCount, 626);
      expect(engine.database.canonicalTypes.length, 52);
    });

    test('matches a name ignoring case and spaces', () {
      expect(engine.database.exactMatch('DEG C')?.name, 'deg C');
      expect(engine.database.exactMatch(' degc ')?.name, 'deg C');
      expect(engine.database.exactMatch('not a unit'), isNull);
    });

    test('finds units by the beginning of a word', () {
      final names = engine.database
          .partialMatches('cel')
          .map((unit) => unit.name)
          .toList();
      expect(names, contains('Celsius'));
      expect(names, contains('Celsius degree'));
    });

    test('finds units by type and counts them', () {
      final volume = engine.database.unitsOfType('volume');
      expect(volume, isNotEmpty);
      expect(volume.length, engine.database.countOfType('volume'));
      expect(volume.map((unit) => unit.name), contains('liter'));
    });
  });

  group('values', () {
    test('reads plain numbers and calculations exactly', () {
      // The value itself is exact: `1/8` is the rational 1/8, not the double
      // 0.125 rounded from a division (the specification §3.4).
      expect(engine.parseValue('12').asFractionText, '12');
      expect(engine.parseValue('-3.5').asFractionText, '-7/2');
      expect(engine.parseValue('1/8').asFractionText, '1/8');
      expect(engine.parseValue('1/8').isExact, isTrue);
      expect(engine.parseValue('1/8').toDouble(), 0.125);
      expect(engine.parseValue('3*4+1').asFractionText, '13');
      expect(engine.parseValue('1e6').asFractionText, '1000000');
      expect(engine.parseValue('2.5e-3').asFractionText, '1/400');
      expect(engine.parseValue('10^3').asFractionText, '1000');
    });

    test('tolerates a Unicode minus, digit group spaces and a decimal comma', () {
      expect(engine.parseValue('\u22125').toDouble(), -5.0);
      // These two forms are not arithmetic: they go through the evaluator of
      // the graphical application and come back as floats.
      expect(engine.parseValue('1 000').toDouble(), 1000.0);
      expect(engine.parseValue('1,5').toDouble(), 1.5);
    });

    test('reports a value that cannot be read', () {
      expect(
        () => engine.parseValue('abc'),
        throwsConversionError(UnitErrorCode.malformedValue),
      );
      expect(
        () => engine.parseValue('   '),
        throwsConversionError(UnitErrorCode.malformedValue),
      );
    });
  });

  group('conversion', () {
    test('converts a simple length', () {
      final result = engine.convert(value: '1', from: 'mile', to: 'km');
      expectClose(result.value, 1.609344);
      expect(result.formatted, '1.609344');
      expect(result.summary, '1 mile = 1.609344 km');
      expectClose(result.factor!, 1.609344);
    });

    test('converts a compound expression', () {
      final result = engine.convert(value: '100', from: 'km/hr', to: 'm/s');
      expectClose(result.value, 27.77777777777778);
      // `%G` with the default precision of 8: eight *significant* digits, the
      // characters the Python implementation prints.
      expect(result.formatted, '27.777778');
      expect(result.fromReduced, 'm / s');
      expect(result.toReduced, 'm / s');
      expect(result.fromCategory, 'm / s');
    });

    test('accepts abbreviations, plurals and squares', () {
      expectClose(
        engine.convert(value: '1', from: 'pounds', to: 'kg').value,
        0.45359237,
      );
      expectClose(
        engine.convert(value: '1', from: 'meters', to: 'm').value,
        1.0,
      );
      expectClose(engine.convert(value: '1', from: 'm2', to: 'm^2').value, 1.0);
      expectClose(engine.convert(value: '60', from: 'mph', to: 'km/hr').value, 96.56064);
    });

    test('converts a fraction value', () {
      final result = engine.convert(value: '1/8', from: 'cup', to: 'ml');
      expectClose(result.value, 29.5735295625);
      // The default precision is that of the Python tool: 8 significant
      // digits in the general notation, so `%G` stops at 29.57353.
      expect(result.summary, '1/8 cup = 29.57353 ml');
      final precise = engine.convert(
        value: '1/8',
        from: 'cup',
        to: 'ml',
        decimals: 12,
      );
      expect(precise.formatted, '29.5735295625');
    });

    test('converts energy and power units', () {
      expectClose(engine.convert(value: '1', from: 'Btu', to: 'J').value, 1055.05585262);
      expect(
        engine.convert(value: '1', from: 'Btu', to: 'J').formatted,
        '1055.0559',
      );
      expect(engine.convert(value: '1', from: 'kWh', to: 'J').formatted, '3600000');
      expectClose(engine.convert(value: '2', from: 'N*m', to: 'J').value, 2.0);
      expectClose(engine.convert(value: '1', from: 'W', to: 'J/s').value, 1.0);
      expectClose(
        engine.convert(value: '1', from: 'acre', to: 'm^2').value,
        4046.8564224,
      );
      expect(
        engine.convert(value: '1', from: 'acre', to: 'm^2').formatted,
        '4046.8564',
      );
    });

    test('converts the units stored with a Unicode minus sign', () {
      // Six units of the data file use U+2212 in their equivalent; the plain
      // Dart core normalises it, the graphical model does not (see
      // parity_test.dart).
      final result = engine.convert(value: '1', from: 'planck mass', to: 'g');
      expectClose(result.value, 2.176434e-05);
      // An exponent below 1e-4 switches `%G` to the scientific notation, as in
      // the Python tool.
      expect(result.formatted, '2.176434E-05');
    });

    test('converts temperatures through their equations', () {
      final boiling = engine.convert(value: '100', from: 'C', to: 'F');
      expectClose(boiling.value, 212.0, relative: 1e-9);
      expect(boiling.formatted, '212');
      expect(
        boiling.isExact,
        isFalse,
        reason: 'an equation runs in floating point, as the specification asks',
      );
      final freezing = engine.convert(value: '32', from: 'F', to: 'C');
      // The floating point residue of the equations (5.7e-14) is rounded
      // away: the freezing point is reported as 0, not as 5.68434188608e-14.
      expect(freezing.value.toDouble(), 0.0);
      expect(freezing.formatted, '0');
      // The compatibility mode reproduces the historical answer, residue and
      // all, which is what `--python-compat` is for.
      final compat = ConversionEngine(engine.database, pythonCompat: true)
          .convert(value: '32', from: 'F', to: 'C');
      expect(compat.value.toDouble(), isNot(0.0));
      expect(compat.formatted, startsWith('5.684'));
      expectClose(engine.convert(value: '0', from: 'C', to: 'K').value, 273.15);
      expectClose(engine.convert(value: '20', from: 'C', to: 'C').value, 20.0);
    });

    test('interpolates a value table', () {
      final gasMarkToC = engine.convert(value: '4', from: 'Gas mark', to: 'C');
      expectClose(gasMarkToC.value, 180.0, relative: 1e-9);
      expect(gasMarkToC.formatted, '180');
      final half = engine.convert(value: '0.5', from: 'Gas mark', to: 'K');
      expectClose(half.value, 393.15, relative: 1e-9);
    });

    test('converts a reciprocal unit', () {
      final result = engine.convert(value: '10', from: 'liter per 100 km', to: 'mpg');
      expectClose(result.value, 23.52145833333333, relative: 1e-9);
      expect(result.factor, isNull, reason: 'a non-linear unit has no constant factor');
    });
  });

  group('refusals', () {
    test('refuses units of different quantities', () {
      expect(
        () => engine.convert(value: '1', from: 'kg', to: 'm'),
        throwsConversionError(UnitErrorCode.incompatibleUnits),
      );
    });

    test('explains that h is the henry and not the hour', () {
      // A common mistake: `km/h` is kilometre per henry (inductance), the
      // hour is `hr` or `hour`.
      expect(
        () => engine.convert(value: '100', from: 'km/h', to: 'm/s'),
        throwsConversionError(UnitErrorCode.incompatibleUnits),
      );
      expectClose(
        engine.convert(value: '100', from: 'km/hr', to: 'm/s').value,
        27.77777777777778,
      );
      expectClose(
        engine.convert(value: '100', from: 'km/hour', to: 'm/s').value,
        27.77777777777778,
      );
    });

    test('reports an unknown unit and suggests close names', () {
      try {
        engine.convert(value: '1', from: 'metr', to: 'm');
        fail('the conversion should have been refused');
      } on UnitConversionException catch (error) {
        expect(error.code, UnitErrorCode.unknownUnit);
        expect(error.message, contains('metr'));
        // Units whose name starts with the text.
        expect(error.suggestions, contains('metre'));
        expect(error.toString(), contains('Did you mean'));
      }
      // Units whose name contains the text, when no name starts with it.
      try {
        engine.convert(value: '1', from: 'logram', to: 'kg');
        fail('the conversion should have been refused');
      } on UnitConversionException catch (error) {
        expect(error.suggestions, contains('kilogram'));
      }
    });

    test('refuses to combine a non-linear unit', () {
      expect(
        () => engine.convert(value: '1', from: 'C*m', to: 'K*m'),
        throwsConversionError(UnitErrorCode.nonLinearUnit),
      );
      expect(
        () => engine.convert(value: '1', from: 'C^2', to: 'K^2'),
        throwsConversionError(UnitErrorCode.nonLinearUnit),
      );
    });

    test('refuses an incomplete expression', () {
      expect(
        () => engine.convert(value: '1', from: 'm/', to: 'm'),
        throwsConversionError(UnitErrorCode.invalidUnitExpression),
      );
      expect(
        () => engine.convert(value: '1', from: 'm//s', to: 'm/s'),
        throwsConversionError(UnitErrorCode.invalidUnitExpression),
      );
      expect(
        () => engine.convert(value: '1', from: '(m/s', to: 'm/s'),
        throwsConversionError(UnitErrorCode.invalidUnitExpression),
      );
      expect(
        () => engine.convert(value: '1', from: '', to: 'm'),
        throwsConversionError(UnitErrorCode.invalidUnitExpression),
      );
    });

    test('refuses a value outside the range of a table', () {
      expect(
        () => engine.convert(value: '20', from: 'Gas mark', to: 'C'),
        throwsConversionError(UnitErrorCode.outOfRange),
      );
    });
  });

  group('compatible units', () {
    test('lists the units of the same quantity', () {
      final speeds = engine.compatibleUnits('km/hr').map((unit) => unit.name).toList();
      expect(speeds, contains('mph'));
      expect(speeds, contains('knot'));
      expect(speeds, contains('kph'));
      expect(speeds, isNot(contains('kg')));

      final volumes = engine
          .compatibleUnits('ml')
          .map((unit) => unit.name)
          .toList();
      expect(volumes, contains('cup'));
      expect(volumes, contains('liter'));
    });

    test('counts the compatible units', () {
      expect(
        engine.compatibleUnitCount('km/hr'),
        engine.compatibleUnits('km/hr', limit: 0).length,
      );
      expect(engine.compatibleUnitCount('m'), greaterThan(20));
    });

    test('lists the compatible units of a non-linear unit', () {
      final temperatures = engine
          .compatibleUnits('C')
          .map((unit) => unit.name)
          .toList();
      expect(temperatures, contains('F'));
      expect(temperatures, contains('K'));
      expect(temperatures, contains('Gas mark'));
    });

    test('describes a unit', () {
      final details = engine.describeUnit('Btu');
      expect(details.unit.canonicalType, 'energy');
      expect(details.reduced, 'kg * m^2 / s^2');
      expect(details.compatible.map((unit) => unit.name), contains('J'));
      expect(details.unit.isNonLinear, isFalse);

      final celsius = engine.describeUnit('C');
      expect(celsius.unit.isNonLinear, isTrue);
      expect(celsius.reduced, 'K');
    });
  });

  group('formatting', () {
    test('writes the notation of the Python implementation', () {
      // `%G` with 8 significant digits: the exact characters the historical
      // command line prints.
      expect(ConversionEngine.formatValue(Number.approximate(0.0)), '0');
      expect(ConversionEngine.formatValue(Number.approximate(100.0)), '100');
      expect(ConversionEngine.formatValue(Number.approximate(1.609344)), '1.609344');
      expect(ConversionEngine.formatValue(Number.approximate(1 / 3)), '0.33333333');
      expect(ConversionEngine.formatValue(Number.approximate(1e8)), '1E+08');
      expect(ConversionEngine.formatValue(Number.approximate(2.5e-9)), '2.5E-09');
    });

    test('renders an exact rational without a rounding artefact', () {
      expect(
        ConversionEngine.formatValue(Number.exact(Rational.parse('2.54'))),
        '2.54',
      );
      // 1/16 has a terminating decimal, 5/9 does not: the first is printed as
      // a decimal, the second is rounded to the notation.
      expect(
        ConversionEngine.formatValue(Number.exact(Rational.fromInt(1, 16)), decimals: 12),
        '0.0625',
      );
      expect(
        ConversionEngine.formatValue(Number.exact(Rational.fromInt(5, 9))),
        '0.55555556',
      );
    });

    test('honours the number of decimals', () {
      expect(
        ConversionEngine.formatValue(
          Number.approximate(1 / 3),
          notation: NumberNotation.fixed,
          decimals: 3,
        ),
        '0.333',
      );
      expect(
        ConversionEngine.formatValue(
          Number.approximate(1 / 3),
          notation: NumberNotation.scientific,
          decimals: 2,
        ),
        '3.33E-01',
      );
      expect(
        ConversionEngine.formatValue(
          Number.approximate(1234.5),
          notation: NumberNotation.engineering,
          decimals: 4,
        ),
        '1.2345E+03',
      );
    });

    test('accepts notation aliases', () {
      expect(notationFromName('ENG'), NumberNotation.engineering);
      expect(notationFromName('auto'), NumberNotation.short);
      expect(notationFromName('nonsense'), isNull);
      expect(notationName(NumberNotation.fixed), 'fixed');
    });

    test('converts with an explicit notation', () {
      final result = engine.convert(
        value: '1',
        from: 'mile',
        to: 'm',
        notation: NumberNotation.fixed,
        decimals: 2,
      );
      expect(result.formatted, '1609.34');
    });

    test('keeps the exact value of a linear conversion', () {
      final inch = engine.convert(value: '1', from: 'in', to: 'cm');
      expect(inch.isExact, isTrue);
      expect(inch.asFractionText, '127/50');
      expect(inch.exactValueText, '2.54');
      expect(inch.formatted, '2.54');
      expect(inch.summary, '1 in = 2.54 cm');
      final json = inch.toJson();
      expect(json['value'], 2.54);
      expect(json['value_exact'], '2.54');
      expect(json['exact'], true);
      expect(json['as_fraction'], '127/50');
      // A conversion through an equation has no exact value.
      final celsius = engine.convert(value: '100', from: 'C', to: 'F');
      expect(celsius.isExact, isFalse);
      expect(celsius.exactValueText, isNull);
      expect(celsius.toJson()['value_exact'], isNull);
      expect(celsius.toJson()['as_fraction'], isNull);
      expect(celsius.toJson()['exact'], false);
    });

    test('writes the multiplier as a number and as an exact string', () {
      final result = engine.convert(value: '1', from: 'mile', to: 'km');
      expect(result.factor!.toDouble(), 1.609344);
      expect(result.toJson()['factor'], 1.609344);
      expect(result.toJson()['factor_exact'], '25146/15625');
      expect(
        engine.convert(value: '1', from: 'C', to: 'F').factor,
        isNull,
        reason: 'a non-linear conversion has no constant multiplier',
      );
    });
  });
}
