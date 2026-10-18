// exact_math_test.dart, tests of the exact arithmetic and of the formatting.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// Run with:  flutter test test/core/exact_math_test.dart
//
// The expected strings are the ones the ConvertAll Python implementation
// produces (`source/unitgroup.py`, `formatNumStr`), which calls Python's
// `%G`, `%f` and `%E` formats.  They were checked against Python 3 on the
// values below: `1 in` is exactly `2.54 cm`, `1 mile` exactly `1.609344 km`,
// and `1 in` divided by three is `0.3333333333333333` there, which the
// 8 significant digits of the default notation write `0.33333333`.

import 'package:flutter_test/flutter_test.dart';
import 'package:rational/rational.dart';

import 'package:convertall/core/exact_math.dart';
import 'package:convertall/core/exact_number.dart';
import 'package:convertall/core/number_notation.dart';

void main() {
  group('exact evaluation', () {
    test('reads the decimal forms of the data file', () {
      expect(ExactMath.evaluate('2.54'), Rational.fromInt(127, 50));
      expect(ExactMath.evaluate('0.001'), Rational.fromInt(1, 1000));
      expect(ExactMath.evaluate('.5'), Rational.fromInt(1, 2));
      expect(ExactMath.evaluate('1e9'), Rational.fromInt(1000000000));
      expect(ExactMath.evaluate('2.176434e-8'), Rational.parse('0.00000002176434'));
      expect(ExactMath.evaluate('-40'), Rational.fromInt(-40));
    });

    test('reads the fractions and the operators of the data file', () {
      expect(ExactMath.evaluate('1/16.0'), Rational.fromInt(1, 16));
      expect(ExactMath.evaluate('1200/3937.0'), Rational.fromInt(1200, 3937));
      expect(ExactMath.evaluate('5/9.0'), Rational.fromInt(5, 9));
      expect(ExactMath.evaluate('2 * (3 + 4)'), Rational.fromInt(14));
      expect(ExactMath.evaluate('10^3'), Rational.fromInt(1000));
      expect(ExactMath.evaluate('10^-2'), Rational.fromInt(1, 100));
      expect(ExactMath.evaluate('2**5'), Rational.fromInt(32));
    });

    test('normalises the Unicode minus of six data entries', () {
      expect(
        ExactMath.evaluate('2.176434e\u22128'),
        Rational.parse('0.00000002176434'),
      );
      expect(ExactMath.evaluate('1.380649e\u221223').signum, greaterThan(0));
    });

    test('refuses what is not arithmetic', () {
      expect(ExactMath.tryEvaluate('sqrt(2)'), isNull);
      expect(ExactMath.tryEvaluate('pi'), isNull);
      expect(ExactMath.tryEvaluate('1 in'), isNull);
      expect(ExactMath.tryEvaluate('1/0'), isNull);
      expect(ExactMath.tryEvaluate(''), isNull);
      expect(() => ExactMath.evaluate('abc'), throwsFormatException);
    });

    test('converts a double to the rational it is', () {
      // `double.toString` gives the shortest text that reads back to the same
      // double, so the rational is the exact value of that double.
      expect(ExactMath.fromDouble(2.54), Rational.fromInt(127, 50));
      expect(ExactMath.fromDouble(0.1), Rational.parse('0.1'));
      expect(ExactMath.fromDouble(double.nan), isNull);
      expect(ExactMath.fromDouble(double.infinity), isNull);
    });
  });

  group('rounding and rendering', () {
    test('rounds a decimal place half to even', () {
      Rational parse(String text) => Rational.parse(text);
      expect(ExactMath.roundToScale(parse('2.5'), 0), Rational.fromInt(2));
      expect(ExactMath.roundToScale(parse('3.5'), 0), Rational.fromInt(4));
      expect(ExactMath.roundToScale(parse('-2.5'), 0), Rational.fromInt(-2));
      expect(ExactMath.roundToScale(parse('0.125'), 2), parse('0.12'));
      expect(ExactMath.roundToScale(parse('0.135'), 2), parse('0.14'));
      expect(ExactMath.roundToScale(parse('1234'), -2), Rational.fromInt(1200));
      expect(ExactMath.roundToScale(parse('1250'), -2), Rational.fromInt(1200));
    });

    test('writes the fixed notation like Python %f', () {
      expect(ExactMath.toFixed(ExactMath.evaluate('2.54'), 4), '2.5400');
      expect(ExactMath.toFixed(ExactMath.evaluate('2.54'), 0), '3');
      expect(ExactMath.toFixed(ExactMath.evaluate('-40'), 2), '-40.00');
      expect(ExactMath.toFixed(ExactMath.evaluate('1/3'), 8), '0.33333333');
      // Python: format(29.5735295625, '.12f') == '29.573529562500'.
      expect(ExactMath.toFixed(ExactMath.evaluate('29.5735295625'), 12),
          '29.573529562500');
    });

    test('writes the scientific notation like Python %E', () {
      expect(ExactMath.toScientific(ExactMath.evaluate('1000'), 3), '1.000E+03');
      expect(ExactMath.toScientific(ExactMath.evaluate('1000'), 0), '1E+03');
      expect(ExactMath.toScientific(ExactMath.evaluate('0'), 3), '0.000E+00');
      expect(ExactMath.toScientific(ExactMath.evaluate('2.5e-9'), 2), '2.50E-09');
      expect(ExactMath.toScientific(ExactMath.evaluate('1/3'), 3), '3.333E-01');
      // A carry moves to the next exponent: 9.99 rounds to 10.0E+00.
      expect(ExactMath.toScientific(ExactMath.evaluate('9.999'), 2), '1.000E+01');
    });

    test('writes the engineering notation of the Python tool', () {
      expect(ExactMath.toEngineering(ExactMath.evaluate('1000'), 2), '1.00E+03');
      expect(ExactMath.toEngineering(ExactMath.evaluate('0.0254'), 2), '25.40E-03');
      expect(ExactMath.toEngineering(ExactMath.evaluate('1e-9'), 2), '1.00E-09');
      expect(ExactMath.toEngineering(ExactMath.evaluate('12345'), 2), '12.35E+03');
      expect(ExactMath.toEngineering(ExactMath.evaluate('0.5'), 2), '500.00E-03');
      expect(ExactMath.toEngineering(ExactMath.evaluate('0'), 2), '0.00E+00');
      expect(ExactMath.toEngineering(ExactMath.evaluate('-2500'), 2), '-2.50E+03');
      // 999.99 does not reach 1000: the exponent stays.  (Python:
      // `999990 / 10**3` rounds to 999.99, below the carry.)
      expect(ExactMath.toEngineering(ExactMath.evaluate('999990'), 2), '999.99E+03');
      // A carry at the top of the range moves the exponent by three:
      // 999.999 rounds to 1000.00, which is written 1.00E+06.
      expect(ExactMath.toEngineering(ExactMath.evaluate('999999'), 2), '1.00E+06');
    });

    test('rounds the short notation to significant digits', () {
      Number number(String text) => Number.exact(ExactMath.evaluate(text));
      String render(String text, {int decimals = 8}) =>
          formatNumber(number(text), decimals: decimals);
      expect(render('0'), '0');
      expect(render('100'), '100');
      expect(render('1.609344'), '1.609344');
      expect(render('0.45359237'), '0.45359237');
      expect(render('1e8'), '1E+08');
      expect(render('2.5e-9'), '2.5E-09');
      expect(render('1/3'), '0.33333333');
      expect(render('29.5735295625'), '29.57353');
      expect(render('123456789'), '1.2345679E+08');
      expect(render('0.000123456789'), '0.00012345679');
      expect(render('1.5e-7'), '1.5E-07');
      expect(render('-40'), '-40');
      // A carry to the next exponent, as Python writes it.
      expect(render('99999999.5'), '1E+08');
      expect(render('9.999999'), '9.999999');
      // The notation is the number of significant digits of `%G`.
      expect(render('2.54', decimals: 2), '2.5');
      expect(render('2.54', decimals: 1), '3');
    });

    test('strips the trailing zeros of the short notation', () {
      expect(ExactMath.stripTrailingZeros('2.5400'), '2.54');
      expect(ExactMath.stripTrailingZeros('100.0'), '100');
      expect(ExactMath.stripTrailingZeros('100'), '100');
      expect(ExactMath.stripTrailingZeros('0.00'), '0');
    });

    test('writes the exact text of a factor', () {
      expect(ExactMath.toExactText(Rational.fromInt(127, 50)), '2.54');
      expect(ExactMath.toExactText(Rational.fromInt(1, 1000)), '0.001');
      expect(ExactMath.toExactText(Rational.fromInt(5, 9)), '5/9');
      expect(ExactMath.toExactText(Rational.fromInt(-40)), '-40');
      expect(ExactMath.toExactText(Rational.zero), '0');
    });
  });

  group('numbers and notations', () {
    test('keeps an exact value exact through the arithmetic', () {
      final inch = Number.exact(Rational.fromInt(127, 50));
      final metre = Number.exact(Rational.fromInt(1, 100));
      expect((inch / metre).isExact, isTrue);
      expect((inch / metre).asFractionText, '127/50');
      expect((inch * Number.exact(Rational.fromInt(3))).asFractionText, '381/50');
      expect(Number.exact(Rational.fromInt(2, 3)).pow(2).asFractionText, '4/9');
      // A fractional exponent cannot stay exact.
      expect(Number.exact(Rational.fromInt(4)).pow(0.5).isExact, isFalse);
      expect(
        Number.exact(Rational.fromInt(4)).pow(0.5).toDouble(),
        closeTo(2.0, 1e-12),
      );
    });

    test('mixes an exact and a float value', () {
      final exact = Number.exact(Rational.fromInt(1, 4));
      final mixed = exact + Number.approximate(0.5);
      expect(mixed.isExact, isFalse);
      expect(mixed.toDouble(), 0.75);
    });

    test('reads a value from text', () {
      expect(Number.tryParse('1/8')!.asFractionText, '1/8');
      expect(Number.tryParse('-3.5')!.asFractionText, '-7/2');
      expect(Number.tryParse('abc'), isNull);
      expect(Number.tryParse(''), isNull);
    });

    test('names the notations, with the Python aliases', () {
      expect(notationFromName('general'), NumberNotation.short);
      expect(notationFromName('SHORT'), NumberNotation.short);
      expect(notationFromName('fixed'), NumberNotation.fixed);
      expect(notationFromName('decimal'), NumberNotation.fixed);
      expect(notationFromName('sci'), NumberNotation.scientific);
      expect(notationFromName('eng'), NumberNotation.engineering);
      expect(notationFromName('nonsense'), isNull);
      expect(notationName(NumberNotation.scientific), 'scientific');
      expect(maxDecimals, 12);
    });
  });
}
