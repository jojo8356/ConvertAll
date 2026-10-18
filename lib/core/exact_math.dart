// exact_math.dart, exact arithmetic on the factors of the unit data.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// The specification (`doc/CLI_RUST_CAHIER_DES_CHARGES.md`, §3.4 of the
// ConvertAll-py repository) asks for two engines: **exact rational numbers**
// for the linear factors, `f64` only for the non-linear units (equations and
// interpolation tables).  The unit data is made of decimal fractions
// (`0.001`, `2.54`, `1/16.0`, `2.176434e-8`), so a rational engine evaluates
// them exactly and `1 in = 2.54 cm` is exact instead of 2.5400000000000005.
//
// The rational type is `Rational` from the `rational` package (BigInt based,
// the same idea as Python's `fractions.Fraction` or C's GMP rationals), the
// only exact arithmetic module published for Dart.  Everything else here —
// the evaluation of the data expressions, the rounding to a decimal place and
// the decimal rendering — is written on top of its integer arithmetic, so no
// `double` ever appears on the exact path.
//
// Rounding follows the scientific convention of Python's `decimal` module and
// of IEEE-754: **half to even** (2.5 → 2, 3.5 → 4).  It applies to exact
// values; a decimal expansion that stops before the rounding position needs
// no rounding at all and is returned untouched.

import 'package:rational/rational.dart';

/// Exact evaluation and rendering of rational numbers.
abstract final class ExactMath {
  /// Ten to the power [exponent] (`10 ^ -3` is 1/1000).
  static Rational powerOfTen(int exponent) => exponent >= 0
      ? Rational(BigInt.from(10).pow(exponent))
      : Rational(BigInt.one, BigInt.from(10).pow(-exponent));

  /// The exact value of [text], or `null` when it is not arithmetic.
  ///
  /// Accepts what the unit data and the command line use: decimal literals
  /// (`2.54`, `.5`), scientific notation (`1e9`, `2.176434e-8`), fractions
  /// (`1/16.0`, `1200/3937.0`), the operators `+ - * /`, parentheses, a
  /// leading sign and an integer power (`10^3`).  Unicode minus signs are
  /// normalised first, since six entries of `assets/units.json` use them.
  static Rational? tryEvaluate(String text) {
    final parser = _ExpressionParser(_normalizeSigns(text));
    try {
      final value = parser.parseExpression();
      parser.expectEnd();
      return value;
    } on FormatException {
      return null;
    }
  }

  /// Like [tryEvaluate], but throws a [FormatException] instead of returning
  /// `null`.
  static Rational evaluate(String text) {
    final value = tryEvaluate(text);
    if (value == null) {
      throw FormatException('Not an exact number: "$text"');
    }
    return value;
  }

  /// The exact value of the [double] [value], or `null` for `inf`/`nan`.
  ///
  /// Dart prints a double with the shortest text that reads back to the same
  /// double, so parsing that text gives the double exactly.  This is how the
  /// non-linear path (which runs in `f64`, as the specification requires)
  /// reaches the same rounding and rendering code as the exact path.
  static Rational? fromDouble(double value) {
    if (!value.isFinite) return null;
    return tryEvaluate(value.toString());
  }

  /// [value] rounded to a multiple of `10^[-scale]`, half to even.
  ///
  /// A positive [scale] rounds to a decimal place (`roundToScale(x, 2)` keeps
  /// two decimals), a negative one to tens, hundreds, ...  The result is
  /// exact: the denominator always divides a power of ten.
  static Rational roundToScale(Rational value, int scale) {
    if (value == Rational.zero) return value;
    final power = powerOfTen(scale < 0 ? -scale : scale).numerator;
    final numerator = scale >= 0 ? value.numerator * power : value.numerator;
    final denominator = scale >= 0 ? value.denominator : value.denominator * power;
    var quotient = numerator ~/ denominator;
    final remainder = numerator.remainder(denominator);
    final twiceRemainder = remainder.abs() * BigInt.two;
    final negative = numerator.isNegative;
    if (twiceRemainder > denominator) {
      quotient += negative ? -BigInt.one : BigInt.one;
    } else if (twiceRemainder == denominator && quotient.isOdd) {
      // Half to even: the tie goes to the even digit.
      quotient += negative ? -BigInt.one : BigInt.one;
    }
    return scale >= 0
        ? Rational(quotient, power)
        : Rational(quotient * power);
  }

  /// The largest integer `e` with `10^e <= |value|`, for a non-zero value.
  static int decimalExponent(Rational value) {
    final abs = value.abs();
    if (abs == Rational.zero) return 0;
    // A first guess from the number of digits of numerator and denominator.
    var exponent = abs.numerator.toString().length -
        abs.denominator.toString().length;
    // Then compare exactly, in both directions (the guess is off by one at
    // most, but the loop also covers values like 999.9999).
    while (abs < powerOfTen(exponent)) {
      exponent -= 1;
    }
    while (abs >= powerOfTen(exponent + 1)) {
      exponent += 1;
    }
    return exponent;
  }

  /// [value] rendered with exactly [decimals] digits after the decimal point.
  ///
  /// The value is rounded first (half to even), so the rendering is a plain
  /// integer division and never loses a digit.  [signOf] carries the sign when
  /// [value] is already rounded (`-0.001` rounded to two decimals is written
  /// `-0.00`, as Python's `%f` does, and not `0.00`).
  static String toFixed(Rational value, int decimals, {Rational? signOf}) {
    final places = decimals < 0 ? 0 : decimals;
    final rounded = roundToScale(value, places);
    final scale = powerOfTen(places).numerator;
    final digits = ((rounded.numerator * scale) ~/ rounded.denominator)
        .abs()
        .toString();
    final padded = digits.padLeft(places + 1, '0');
    final integerPart = padded.substring(0, padded.length - places);
    final fractionPart = places == 0
        ? ''
        : padded.substring(padded.length - places);
    final sign = (signOf ?? value).signum < 0 ? '-' : '';
    return fractionPart.isEmpty
        ? '$sign$integerPart'
        : '$sign$integerPart.$fractionPart';
  }

  /// [value] rendered in scientific notation, `1.000E+03`.
  ///
  /// [decimals] digits follow the decimal point of the mantissa; the exponent
  /// is written with a sign and at least two digits, as Python's `%E` does.
  static String toScientific(Rational value, int decimals) {
    final places = decimals < 0 ? 0 : decimals;
    if (value == Rational.zero) {
      return '${toFixed(value, places)}E+00';
    }
    var exponent = decimalExponent(value);
    var mantissa = roundToScale(value / powerOfTen(exponent), places);
    // Rounding 9.99 may carry into 10.0, which belongs to the next exponent.
    if (mantissa.abs() >= Rational.fromInt(10)) {
      exponent += 1;
      mantissa = roundToScale(value / powerOfTen(exponent), places);
    }
    return '${toFixed(mantissa, places)}E${exponentText(exponent)}';
  }

  /// [value] rendered in engineering notation, `12.35E+03`.
  ///
  /// Same as [toScientific], with the exponent forced to a multiple of three,
  /// as the ConvertAll Python implementation does (`unitgroup.formatNumStr`).
  static String toEngineering(Rational value, int decimals) {
    final places = decimals < 0 ? 0 : decimals;
    if (value == Rational.zero) {
      return '${toFixed(value, places)}E+00';
    }
    var exponent = decimalExponent(value);
    // Floor the exponent to a multiple of three, positive or negative.
    exponent = exponent >= 0 ? (exponent ~/ 3) * 3 : -(((-exponent + 2) ~/ 3) * 3);
    var mantissa = roundToScale(value / powerOfTen(exponent), places);
    if (mantissa.abs() >= Rational.fromInt(1000)) {
      mantissa /= Rational.fromInt(1000);
      exponent += 3;
    }
    return '${toFixed(mantissa, places)}E${exponentText(exponent)}';
  }

  /// `+03`, `-09`, `+00`: the exponent of a scientific notation, as Python
  /// writes it (a sign, then at least two digits).
  static String exponentText(int exponent) {
    final sign = exponent < 0 ? '-' : '+';
    final digits = exponent.abs().toString().padLeft(2, '0');
    return '$sign$digits';
  }

  /// The exact text of [value]: a decimal string when it terminates
  /// (`0.3048`), a fraction otherwise (`5/9`).
  ///
  /// Used by the JSON output and the `doctor` command, where the specification
  /// asks the factors to be strings "quand l'exactitude compte": nothing must
  /// be rounded silently.
  static String toExactText(Rational value) {
    var denominator = value.denominator;
    var twins = 0;
    while (denominator % BigInt.two == BigInt.zero) {
      denominator = denominator ~/ BigInt.two;
      twins += 1;
    }
    var fives = 0;
    final five = BigInt.from(5);
    while (denominator % five == BigInt.zero) {
      denominator = denominator ~/ five;
      fives += 1;
    }
    // A denominator left over means the decimal expansion never stops.
    if (denominator != BigInt.one) return value.toString();
    return toFixed(value, twins > fives ? twins : fives);
  }

  /// [text] without its trailing zeros (`2.5400` → `2.54`, `100.0` → `100`).
  static String stripTrailingZeros(String text) {
    if (!text.contains('.')) return text;
    var result = text.replaceFirst(RegExp(r'0+$'), '');
    if (result.endsWith('.')) result = result.substring(0, result.length - 1);
    return result;
  }

  /// Replace every Unicode minus sign of [text] by the ASCII one.
  ///
  /// The data file writes six factors that way (`2.176434e\u22128 kg`), and the
  /// Python implementation leaves them to `eval_ex`; normalising them is
  /// listed among the deliberate differences of `lib/core/unit_expression.dart`.
  static String _normalizeSigns(String text) {
    var result = text;
    for (final sign in _unicodeMinusSigns) {
      result = result.replaceAll(sign, '-');
    }
    return result;
  }

  static const _unicodeMinusSigns = <String>[
    '\u2010', '\u2011', '\u2012', '\u2013', '\u2014', '\u2212', '\uFE63',
    '\uFF0D',
  ];
}

/// A small recursive descent parser for the numeric expressions of the data
/// file, evaluating exactly in rational arithmetic.
class _ExpressionParser {
  _ExpressionParser(this.text);

  final String text;
  int position = 0;

  Rational parseExpression() {
    var value = parseTerm();
    while (true) {
      skipSpaces();
      if (accept('+')) {
        value += parseTerm();
      } else if (accept('-')) {
        value -= parseTerm();
      } else {
        return value;
      }
    }
  }

  Rational parseTerm() {
    var value = parseUnary();
    while (true) {
      skipSpaces();
      if (accept('*')) {
        value *= parseUnary();
      } else if (accept('/')) {
        final divisor = parseUnary();
        if (divisor == Rational.zero) {
          throw const FormatException('Division by zero');
        }
        value /= divisor;
      } else {
        return value;
      }
    }
  }

  Rational parseUnary() {
    skipSpaces();
    if (accept('-')) return -parseUnary();
    if (accept('+')) return parseUnary();
    return parsePower();
  }

  Rational parsePower() {
    final base = parsePrimary();
    skipSpaces();
    // `^` is the ConvertAll exponent, `**` the Python one.
    if (accept('^') || accept('**')) {
      final exponent = parseUnary();
      if (!exponent.isInteger) {
        throw const FormatException('A non integer power is not exact');
      }
      return base.pow(exponent.numerator.toInt());
    }
    return base;
  }

  Rational parsePrimary() {
    skipSpaces();
    if (accept('(')) {
      final value = parseExpression();
      skipSpaces();
      if (!accept(')')) throw const FormatException('Missing ")"');
      return value;
    }
    return parseNumber();
  }

  Rational parseNumber() {
    skipSpaces();
    final start = position;
    while (position < text.length) {
      final char = text[position];
      final isDigit = char.codeUnitAt(0) >= 0x30 && char.codeUnitAt(0) <= 0x39;
      if (isDigit || char == '.') {
        position += 1;
        continue;
      }
      // An exponent belongs to the number ("1e-8"), a signed one included.
      if ((char == 'e' || char == 'E') && position > start) {
        final next = position + 1 < text.length ? text[position + 1] : '';
        final afterSign = position + 2 < text.length ? text[position + 2] : '';
        final isExponent = _isDigit(next) ||
            ((next == '+' || next == '-') && _isDigit(afterSign));
        if (isExponent) {
          position += 1;
          if (next == '+' || next == '-') position += 1;
          continue;
        }
      }
      break;
    }
    if (position == start) {
      throw FormatException('A number was expected at offset $start');
    }
    final literal = text.substring(start, position);
    final value = Rational.tryParse(literal);
    if (value == null) {
      throw FormatException('"$literal" is not a decimal number');
    }
    return value;
  }

  void expectEnd() {
    skipSpaces();
    if (position != text.length) {
      throw FormatException('Unexpected "${text[position]}"');
    }
  }

  void skipSpaces() {
    while (position < text.length && _isSpace(text[position])) {
      position += 1;
    }
  }

  bool accept(String token) {
    if (text.startsWith(token, position)) {
      position += token.length;
      return true;
    }
    return false;
  }

  static bool _isDigit(String character) =>
      character.isNotEmpty &&
      character.codeUnitAt(0) >= 0x30 &&
      character.codeUnitAt(0) <= 0x39;

  static bool _isSpace(String character) =>
      character == ' ' || character == '\t' || character == '\n';
}
