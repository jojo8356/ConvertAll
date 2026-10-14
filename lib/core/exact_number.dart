// exact_number.dart, the number type shared by the conversions and the CLI.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// The specification asks for a single number type the rest of the program
// cannot bypass: a conversion of two linear units produces an **exact**
// rational (`Number.exact`), a conversion going through an equation or an
// interpolation table produces a **float** (`Number.approximate`), and the
// callers can tell the two apart (`isExact`).  That is what makes
// `convertall --json 1 in cm` able to answer `{"exact": true,
// "as_fraction": "127/50"}` while a temperature stays a `double`.
//
// The display notations are the ones of the ConvertAll Python implementation
// (`source/unitgroup.py`, `formatNumStr`), so that the command line prints
// exactly what the historical program printed:
//
//   general      Python `%G`  : significant digits, trailing zeros removed
//   fixed        Python `%f`  : always the same number of decimals
//   scientific   Python `%E`  : `1.000E+03`
//   engineering  exponent multiple of three : `1.00E+03`

import 'dart:math' as math;

import 'package:rational/rational.dart';

import 'exact_math.dart';
import 'number_notation.dart';

/// A conversion result: an exact rational, or a float when an equation or an
/// interpolation table was involved.
sealed class Number implements Comparable<Number> {
  const Number();

  /// The exact value [value].
  factory Number.exact(Rational value) = ExactNumber;

  /// The float [value] (a non-linear unit, or `--python-compat`).
  factory Number.approximate(double value) = FloatNumber;

  /// The value of the expression [text] (`1/8`, `2.5`, `-3.5e-2`), exact when
  /// the expression is arithmetic, or `null` when it cannot be read.
  static Number? tryParse(String text) {
    final exact = ExactMath.tryEvaluate(text);
    if (exact != null) return ExactNumber(exact);
    final value = double.tryParse(text.trim());
    if (value == null || !value.isFinite) return null;
    return FloatNumber(value);
  }

  /// True when the value is an exact rational.
  bool get isExact;

  /// True for a finite value (`inf` and `nan` are not).
  bool get isFinite;

  /// The value as a [Rational] when it is exact, or `null`.
  Rational? get asRational;

  /// The value as a decimal string of the rational, `null` when not exact.
  String? get asFractionText;

  /// The value as a Dart `double`, for the non-linear calculations.
  double toDouble();

  /// True for a value equal to zero.
  bool get isZero => compareTo(zero) == 0;

  /// The value zero, as an exact number.
  static final Number zero = ExactNumber(Rational.zero);

  /// The value one, as an exact number.
  static final Number one = ExactNumber(Rational.one);

  Number operator +(Number other);

  Number operator -(Number other);

  Number operator *(Number other);

  Number operator /(Number other);

  Number operator -();

  /// `this ^ exponent`: exact when the base is exact and the exponent is an
  /// integer, a float otherwise (`m^1.5` is a square root).
  Number pow(num exponent);
}

/// An exact rational value.
final class ExactNumber extends Number {
  const ExactNumber(this.value);

  final Rational value;

  @override
  bool get isExact => true;

  @override
  bool get isFinite => true;

  @override
  Rational? get asRational => value;

  @override
  String? get asFractionText =>
      value.isInteger ? '${value.numerator}' : '${value.numerator}/${value.denominator}';

  @override
  double toDouble() => value.toDouble();

  @override
  Number operator +(Number other) => switch (other) {
    ExactNumber(:final value) => ExactNumber(this.value + value),
    FloatNumber(:final value) => FloatNumber(this.value.toDouble() + value),
  };

  @override
  Number operator -(Number other) => switch (other) {
    ExactNumber(:final value) => ExactNumber(this.value - value),
    FloatNumber(:final value) => FloatNumber(this.value.toDouble() - value),
  };

  @override
  Number operator *(Number other) => switch (other) {
    ExactNumber(:final value) => ExactNumber(this.value * value),
    FloatNumber(:final value) => FloatNumber(this.value.toDouble() * value),
  };

  @override
  Number operator /(Number other) => switch (other) {
    ExactNumber(:final value) => ExactNumber(this.value / value),
    FloatNumber(:final value) => FloatNumber(this.value.toDouble() / value),
  };

  @override
  Number operator -() => ExactNumber(-value);

  @override
  Number pow(num exponent) => exponent is int
      ? ExactNumber(value.pow(exponent))
      : FloatNumber(math.pow(value.toDouble(), exponent).toDouble());

  @override
  int compareTo(Number other) => switch (other) {
    ExactNumber(:final value) => this.value.compareTo(value),
    FloatNumber(:final value) => this.value.toDouble().compareTo(value),
  };

  @override
  bool operator ==(Object other) =>
      other is Number && other.isExact && other.asRational == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => asFractionText!;
}

/// A float value: a non-linear conversion, or an expression the exact parser
/// does not read (`1.5e400` is not finite, `pi` is not arithmetic).
final class FloatNumber extends Number {
  const FloatNumber(this.value);

  final double value;

  @override
  bool get isExact => false;

  @override
  bool get isFinite => value.isFinite;

  @override
  Rational? get asRational => ExactMath.fromDouble(value);

  @override
  String? get asFractionText => asRational?.toString();

  @override
  double toDouble() => value;

  @override
  Number operator +(Number other) => FloatNumber(value + other.toDouble());

  @override
  Number operator -(Number other) => FloatNumber(value - other.toDouble());

  @override
  Number operator *(Number other) => FloatNumber(value * other.toDouble());

  @override
  Number operator /(Number other) => FloatNumber(value / other.toDouble());

  @override
  Number operator -() => FloatNumber(-value);

  @override
  Number pow(num exponent) => exponent is int
      ? FloatNumber(_powDouble(value, exponent))
      : FloatNumber(math.pow(value, exponent).toDouble());

  @override
  int compareTo(Number other) => value.compareTo(other.toDouble());

  @override
  bool operator ==(Object other) =>
      other is Number && !other.isExact && other.toDouble() == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => '$value';

  static double _powDouble(double base, int exponent) {
    var result = 1.0;
    final negative = exponent < 0;
    var remaining = negative ? -exponent : exponent;
    while (remaining > 0) {
      result *= base;
      remaining -= 1;
    }
    return negative ? 1 / result : result;
  }
}

/// [value] written with [notation] and [decimals] digits.
///
/// [decimals] is the number of **significant digits** for
/// [NumberNotation.short] (as Python's `%G` and the graphical application's
/// option do) and the number of digits after the decimal point for the three
/// other notations.
String formatNumber(
  Number value, {
  NumberNotation notation = NumberNotation.short,
  int decimals = 8,
  bool pythonCompat = false,
}) {
  if (!value.isFinite) return value.toDouble().toString();
  var rational = value.asRational;
  if (rational == null) return value.toDouble().toString();
  if (pythonCompat) {
    // The historical implementation computes every factor as a double: this
    // switch makes the CLI print exactly what the Python one printed.
    rational = ExactMath.fromDouble(value.toDouble()) ?? rational;
  }
  final places = decimals.clamp(0, 15);
  switch (notation) {
    case NumberNotation.short:
      return _formatGeneral(rational, places);
    case NumberNotation.fixed:
      return ExactMath.toFixed(rational, places);
    case NumberNotation.scientific:
      return ExactMath.toScientific(rational, places);
    case NumberNotation.engineering:
      return ExactMath.toEngineering(rational, places);
  }
}

/// Python's `%G`: [precision] significant digits, trailing zeros removed, and
/// scientific notation outside `1e-4` .. `1e<precision>`.
///
/// The value is rounded to [precision] significant digits *before* the choice
/// of the notation, so that a carry moves the exponent: 99999999.5 with eight
/// digits is written `1E+08`, exactly as C's `%g` and Python do.
String _formatGeneral(Rational value, int precision) {
  if (value == Rational.zero) return '0';
  final digits = precision < 1 ? 1 : precision;
  final exponent = ExactMath.decimalExponent(value);
  final rounded = ExactMath.roundToScale(value, digits - 1 - exponent);
  final roundedExponent = ExactMath.decimalExponent(rounded);
  if (roundedExponent < -4 || roundedExponent >= digits) {
    final mantissa = ExactMath.roundToScale(
      rounded / ExactMath.powerOfTen(roundedExponent),
      digits - 1,
    );
    final text = ExactMath.stripTrailingZeros(
      ExactMath.toFixed(mantissa, digits - 1),
    );
    return '${text}E${ExactMath.exponentText(roundedExponent)}';
  }
  final places = digits - 1 - roundedExponent;
  return ExactMath.stripTrailingZeros(
    ExactMath.toFixed(rounded, places, signOf: value),
  );
}
