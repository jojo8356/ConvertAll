// unit_exceptions.dart, exceptions for the pure-Dart conversion core.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.

/// Thrown when the unit database itself is unusable (bad asset, bad
/// equivalent, circular definition).  This is a data or installation problem,
/// not a user input problem.
class UnitDataException implements Exception {
  UnitDataException(this.message);

  /// Human readable description of the problem.
  final String message;

  @override
  String toString() => message;
}

/// Machine readable codes carried by a [UnitConversionException].
///
/// They are stable identifiers shared by the CLI (`--json` output, in the
/// `error_code` field) and by the MCP server (in the `error_code` member of
/// the structured tool output and inside the error message).
abstract final class UnitErrorCode {
  /// The value could not be read as a number or an expression.
  static const malformedValue = 'malformed_value';

  /// The unit expression does not name existing units.
  static const unknownUnit = 'unknown_unit';

  /// The unit expression is syntactically wrong (unclosed parenthesis,
  /// dangling operator, ...).
  static const invalidUnitExpression = 'invalid_unit_expression';

  /// The two units do not measure the same quantity.
  static const incompatibleUnits = 'incompatible_units';

  /// A non-linear unit (Celsius, gas mark, ...) was combined with another
  /// unit or given an exponent, which is not supported.
  static const nonLinearUnit = 'non_linear_unit';

  /// The value is outside the range covered by a non-linear unit.
  static const outOfRange = 'out_of_range';

  /// The unit data contains a circular definition.
  static const circularDefinition = 'circular_definition';

  /// A unit name is ambiguous (several units match it exactly).
  static const ambiguousUnit = 'ambiguous_unit';
}

/// Thrown when a conversion cannot be carried out.  These exceptions are
/// expected events: they are turned into an `isError` tool result by the MCP
/// server and into a non-zero exit status by the CLI, never into a crash.
class UnitConversionException implements Exception {
  UnitConversionException(
    this.message,
    this.code, {
    this.suggestions = const [],
    this.hint,
  });

  /// Human readable explanation, meant to be read by a user *or* by a
  /// language model that has to correct its own input.
  final String message;

  /// One of the [UnitErrorCode] values.
  final String code;

  /// Unit names that may have been meant instead (used for unknowns).
  final List<String> suggestions;

  /// Optional extra guidance, e.g. the accepted unit syntax.
  final String? hint;

  @override
  String toString() {
    final buffer = StringBuffer(message);
    if (suggestions.isNotEmpty) {
      buffer.write(' Did you mean: ${suggestions.join(', ')}?');
    }
    if (hint != null) {
      buffer.write(' ($hint)');
    }
    return buffer.toString();
  }
}
