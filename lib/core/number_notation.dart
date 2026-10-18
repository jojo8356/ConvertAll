// number_notation.dart, the notations shared by the GUI, the CLI and the MCP.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// The notation was an enum of `conversion_engine.dart`; it lives in its own
// file because `lib/core/exact_number.dart` (the arithmetic) and the engine
// (the operations) both need it, and neither should depend on the other.

/// How a result is written.
///
/// The names are the ones of the graphical application's `result_notation`
/// preference; the ConvertAll Python implementation calls the default one
/// `general` and the specification follows it, so both names are accepted by
/// [notationFromName].
enum NumberNotation {
  /// Significant digits, trailing zeros removed (the default; `%/G` in the
  /// Python implementation, "short" in the graphical application).
  short,

  /// A fixed number of decimals, zeros kept (`0.30480000`).
  fixed,

  /// Scientific notation, `1.000E+03`.
  scientific,

  /// Scientific notation with the exponent on a multiple of three, `1.00E+03`.
  engineering,
}

/// The notation for a name (`short`, `general`, `fixed`, `scientific`,
/// `engineering`, and the accepted aliases), or `null` when it is unknown.
NumberNotation? notationFromName(String name) {
  switch (name.trim().toLowerCase()) {
    case 'short':
    case 'general':
    case 'auto':
    case 'default':
    case 'auto-short':
      return NumberNotation.short;
    case 'fixed':
    case 'decimal':
    case 'fixed-decimals':
      return NumberNotation.fixed;
    case 'scientific':
    case 'sci':
    case 'exponential':
      return NumberNotation.scientific;
    case 'engineering':
    case 'eng':
    case 'engineering3':
      return NumberNotation.engineering;
    default:
      return null;
  }
}

/// The canonical name of a notation (`short`, `fixed`, `scientific`,
/// `engineering`).
String notationName(NumberNotation notation) => switch (notation) {
  NumberNotation.short => 'short',
  NumberNotation.fixed => 'fixed',
  NumberNotation.scientific => 'scientific',
  NumberNotation.engineering => 'engineering',
};

/// The names accepted by `--notation`, for the help text and the errors.
const notationNames = <String>[
  'short',
  'fixed',
  'scientific',
  'engineering',
];

/// The maximum number of decimals, as the Python implementation
/// (`UnitGroup.maxDecPlcs = 12`) and the graphical application's option.
const maxDecimals = 12;
