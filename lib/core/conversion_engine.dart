// conversion_engine.dart, the conversion API used by the CLI and the MCP server.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// This is the entry point of the pure-Dart core: it turns the unit data of
// `unit_database.dart` and the expression parser of `unit_expression.dart`
// into the three operations that the command line and the MCP tools expose
// (convert, search and describe), with errors that a language model can act
// on.
//
// The numbers are exact: `Number.exact` for a conversion between linear units
// (the factors are rationals), `Number.approximate` as soon as an equation or
// an interpolation table is involved.  The JSON output says which one answered
// (`exact`, `as_fraction`), and the text formatting is the one of the ConvertAll
// Python implementation (`%G`, `%f`, `%E`), so that the command line prints the
// same characters as the historical program.

import 'exact_math.dart';
import 'exact_number.dart';
import 'logging.dart';
import 'number_notation.dart';
import 'unit_database.dart';
import 'unit_exceptions.dart';
import 'unit_expression.dart';

export 'number_notation.dart' show NumberNotation, notationFromName, notationName;

/// The logger of the conversion operations.
final _log = loggerFor('engine');

/// The result of one conversion.
class UnitConversionResult {
  UnitConversionResult({
    required this.value,
    required this.formatted,
    required this.valueText,
    required this.fromText,
    required this.toText,
    required this.fromReduced,
    required this.toReduced,
    required this.factor,
    required this.fromCategory,
    required this.toCategory,
    required this.notation,
    required this.decimals,
  });

  /// The converted value: exact when the two units are linear, a float when an
  /// equation or an interpolation table was involved.
  final Number value;

  /// The converted value as it is displayed, following [notation].
  final String formatted;

  /// The value as it was typed (`100`, `1/8`, ...).
  final String valueText;

  /// The unit expression converted from, as it was typed.
  final String fromText;

  /// The unit expression converted to, as it was typed.
  final String toText;

  /// The base units of [fromText] (`m / s` for `km/hr`).
  final String fromReduced;

  /// The base units of [toText].
  final String toReduced;

  /// The multiplier from one unit to the other (`to = from * factor`), or
  /// `null` when one of the units is non-linear and there is no constant
  /// multiplier.
  final Number? factor;

  /// The quantity measured by the source unit (`velocity`, `length`, ...).
  final String fromCategory;

  /// The quantity measured by the target unit.
  final String toCategory;

  final NumberNotation notation;

  /// Number of digits used for the decimals.
  final int decimals;

  /// `100 km/hr = 27.777778 m/s`.
  String get summary => '$valueText $fromText = $formatted $toText';

  /// True when the value is an exact rational.
  bool get isExact => value.isExact;

  /// The value as a decimal string when it is exact (`1.609344`, or `5/9` for
  /// a value whose decimal expansion never ends), `null` when it is a float.
  String? get exactValueText => value.asRational == null
      ? null
      : ExactMath.toExactText(value.asRational!);

  /// The value as a reduced fraction (`127/50`), `null` when it is a float.
  String? get asFractionText => value.asFractionText;

  /// The result as a JSON object.  When [detailed] is false only the members
  /// that every conversion has are kept.
  ///
  /// The value is written twice, in the two forms a caller may need: `value`,
  /// the number itself (what the historical protocol sent), and
  /// `value_exact`, the exact decimal or fraction, which is what a script that
  /// must not lose a digit should read.  `exact` says whether the number is
  /// exact.
  Map<String, Object?> toJson({bool detailed = true}) {
    final json = <String, Object?>{
      'result': formatted,
      'value': value.toDouble(),
      'from': fromText,
      'to': toText,
      'exact': value.isExact,
    };
    final exactText = exactValueText;
    if (exactText != null) {
      json['value_exact'] = exactText;
      // The reduced fraction, as the specification's JSON schema writes it
      // (`"as_fraction": "127/50"`).
      json['as_fraction'] = asFractionText;
    }
    if (detailed) {
      json['from_reduced'] = fromReduced;
      json['to_reduced'] = toReduced;
      json['factor'] = factor?.toDouble();
      // The exact multiplier is only known when the conversion went through
      // linear units: with --python-compat, or when an equation is involved,
      // `factor` is a float and there is nothing exact to report.
      if (factor != null && factor!.isExact) {
        json['factor_exact'] = factor!.asFractionText;
      }
      json['from_category'] = fromCategory;
      json['to_category'] = toCategory;
      json['notation'] = notationName(notation);
      json['decimals'] = decimals;
    }
    return json;
  }
}

/// What the database knows about one unit, plus the units it can be converted
/// with.
class UnitDetails {
  UnitDetails({
    required this.unit,
    required this.reduced,
    required this.factor,
    required this.compatible,
  });

  final UnitRecord unit;

  /// The base units of this unit (`kg * m^2 / s^2` for `Btu`).
  final String reduced;

  /// The multiplier to the base units (exact for a linear unit).
  final Number factor;

  /// The other units of the same category, alphabetical.
  final List<UnitRecord> compatible;

  Map<String, Object?> toJson({int compatibleLimit = 0}) {
    final json = <String, Object?>{
      'unit': unit.name,
      'type': unit.canonicalType,
      'type_display': unit.displayType,
      'equivalent': unit.equiv,
      'factor': factor.toDouble(),
      if (factor.isExact) 'factor_exact': factor.asFractionText,
      'base_units': reduced,
      'non_linear': unit.isNonLinear,
      'base_unit': unit.isBaseUnit,
    };
    if (unit.unabbrev.isNotEmpty) json['unabbrev'] = unit.unabbrev;
    if (unit.comment.isNotEmpty) json['comment'] = unit.comment;
    if (unit.isNonLinear) {
      json['from_equation'] = unit.fromEqn;
      if (unit.toEqn.isNotEmpty) json['to_equation'] = unit.toEqn;
    }
    if (compatibleLimit > 0) {
      json['compatible_unit_count'] = compatible.length;
      json['compatible_units'] = compatible
          .take(compatibleLimit)
          .map((record) => record.name)
          .toList();
    }
    return json;
  }
}

/// The operations offered to the command line and to the MCP tools.
class ConversionEngine {
  ConversionEngine(
    this.database, {
    this.notation = NumberNotation.short,
    this.decimals = 8,
    this.pythonCompat = false,
  });

  /// The unit data.  The same `assets/units.json` as the graphical application.
  final UnitDatabase database;

  /// Default notation for the results (the GUI's `result_notation` default).
  final NumberNotation notation;

  /// Default number of decimals (the GUI's `num_dec_plcs` default).
  final int decimals;

  /// True to compute and print everything as the historical Python
  /// implementation does (factors as doubles, equation residues kept): the
  /// option `--python-compat`, for a script that compares both.
  final bool pythonCompat;

  /// The maximum number of errors' suggestions.
  static const suggestionLimit = 5;

  /// The hint shown when a unit name is not found.
  static const unitSyntaxHint =
      'Units are written with * for multiplication, / for division and ^ for '
      'exponents, e.g. kg * m / s^2 or ft*lbf/hr. Names are case insensitive, '
      'a trailing s is accepted, and m2 / m3 mean m^2 / m^3.';

  Map<String, List<UnitRecord>>? _categoryIndex;
  final _reducedCache = <String, String>{};

  /// Read [text] as a number or as a calculation (`1/8`, `2*4+1`, `1e-7`).
  ///
  /// The value is read **exactly** when the expression is arithmetic: a user
  /// who types `1/8` gets `0.125` and not `0.12500000000000003`.  Expressions
  /// the exact parser does not know (`sqrt(2)`, `pi`) fall back to the
  /// evaluator of the graphical application and come back as floats.
  Number parseValue(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw UnitConversionException(
        'The value is empty.',
        UnitErrorCode.malformedValue,
        hint: 'Give a number or a calculation, e.g. 12, -3.5, 1/8, 2*4+1 or 1e6.',
      );
    }
    // `nan` and `inf` are numbers for both languages; the Python tool refuses
    // them with this message, so the Dart one does too.
    if (_isNonFiniteText(trimmed)) {
      _log.warning('refused: "$trimmed" is not finite');
      throw UnitConversionException(
        'Number must be finite',
        UnitErrorCode.malformedValue,
        hint: 'Give a finite number or a calculation, e.g. 12, -3.5, 1/8 or 1e6.',
      );
    }
    final exact = ExactMath.tryEvaluate(trimmed);
    if (exact != null) {
      _log.debug('"$trimmed" read as the exact number ${ExactMath.toExactText(exact)}');
      return Number.exact(exact);
    }
    final approximate = tryEvaluateNumber(trimmed);
    if (approximate == null || !approximate.isFinite) {
      _log.warning('refused: "$trimmed" is not a readable number');
      throw UnitConversionException(
        approximate == null
            ? 'Cannot read "$trimmed" as a number or a calculation.'
            : 'Number must be finite',
        UnitErrorCode.malformedValue,
        hint: 'Accepted forms: 12, -3.5, 1/8, 2*4+1, 1e6, 1.5e-3.',
      );
    }
    _log.debug('"$trimmed" read as the float $approximate');
    return Number.approximate(approximate);
  }

  /// Parse a unit expression and raise an actionable error when it is not
  /// usable.  [label] is the name of the field, used in the message (`from` or
  /// `to` for a conversion).
  UnitGroup parseGroupOrThrow(String text, {String label = 'unit'}) {
    final trimmed = normalizeExpression(text);
    if (trimmed.isEmpty) {
      throw UnitConversionException(
        'The $label expression is empty.',
        UnitErrorCode.invalidUnitExpression,
        hint: unitSyntaxHint,
      );
    }
    final group = UnitGroup.parse(trimmed, database);
    if (group.isValid) {
      if (group.hasIllegalNonLinearUse) {
        _log.warning(
          'refused: "$trimmed" combines a non-linear unit with something else',
        );
        throw UnitConversionException(
          '"$trimmed" combines a non-linear unit with something else.  A '
          'non-linear unit (Celsius, Fahrenheit, gas mark, liter per 100 km, '
          'screw size, ...) can only be converted on its own, without an '
          'exponent and without another unit.',
          UnitErrorCode.nonLinearUnit,
          hint: 'Convert it alone, e.g. from "C" to "F".',
        );
      }
      return group;
    }
    if (group.hasUnclosedParenthesis) {
      throw UnitConversionException(
        'There is an unclosed "(" in the $label expression "$trimmed".',
        UnitErrorCode.invalidUnitExpression,
        hint: unitSyntaxHint,
      );
    }
    for (final atom in group.flatUnits) {
      if (atom.displayName.isEmpty) {
        throw UnitConversionException(
          'The $label expression "$trimmed" is incomplete: it ends with an '
          'operator, or an operator is repeated.',
          UnitErrorCode.invalidUnitExpression,
          hint: unitSyntaxHint,
        );
      }
      if (!atom.isExpValid) {
        throw UnitConversionException(
          'The exponent of "${atom.displayName}" in the $label expression '
          '"$trimmed" is not complete.',
          UnitErrorCode.invalidUnitExpression,
          hint: 'Write an exponent after ^, for example m^2 or s^-1.',
        );
      }
      if (atom.unitMatch == null) {
        final name = atom.displayName;
        final suggestions = suggestionsFor(name);
        final available = ' (${database.unitCount} units are available)';
        _log.warning(
          'refused: unknown $label unit "$name" in "$trimmed"'
          '${suggestions.isEmpty ? '' : ', did you mean ${suggestions.join(', ')}'}',
        );
        throw UnitConversionException(
          'The unit "$name" in the $label expression "$trimmed" is not known$available.',
          UnitErrorCode.unknownUnit,
          suggestions: suggestions,
          hint: unitSyntaxHint,
        );
      }
    }
    throw UnitConversionException(
      'The $label expression "$trimmed" is not a valid unit expression.',
      UnitErrorCode.invalidUnitExpression,
      hint: unitSyntaxHint,
    );
  }

  /// The unit names that may have been meant instead of [name]: the units
  /// whose words start with the text, then, when there are none, the units
  /// whose name contains the text (a good catch for a spelling mistake in the
  /// middle of a word, e.g. "kilgrame").
  List<String> suggestionsFor(String name) {
    final text = normalizeExpression(name).toLowerCase();
    if (text.isEmpty) return const [];
    var matches = database.partialMatches(text, limit: suggestionLimit);
    if (matches.isEmpty && text.length >= 3) {
      matches = database.units
          .where((unit) => unit.name.toLowerCase().contains(text))
          .take(suggestionLimit)
          .toList();
    }
    return matches.map((record) => record.name).toList();
  }

  /// The exact unit record for a name, with suggestions when it is not found.
  UnitRecord requireUnit(String name) {
    final trimmed = normalizeExpression(name);
    if (trimmed.isEmpty) {
      throw UnitConversionException(
        'The unit name is empty.',
        UnitErrorCode.unknownUnit,
        hint: unitSyntaxHint,
      );
    }
    final record = database.exactMatch(trimmed);
    if (record != null) return record;
    final suggestions = suggestionsFor(trimmed);
    _log.warning(
      'refused: unknown unit "$trimmed"'
      '${suggestions.isEmpty ? '' : ', did you mean ${suggestions.join(', ')}'}',
    );
    throw UnitConversionException(
      'The unit "$trimmed" is not known.',
      UnitErrorCode.unknownUnit,
      suggestions: suggestions,
      hint: unitSyntaxHint,
    );
  }

  /// The quantity measured by a unit expression: the unit type for a single
  /// unit (`length`), the type of the compound when all the units share one
  /// (`energy` for `N*m`), the reduced base units otherwise (`kg * m / s^2`).
  String describeCategory(UnitGroup group) {
    final atoms = group.flatUnits;
    final types = <String>{};
    for (final atom in atoms) {
      final match = atom.unitMatch;
      if (match == null) return group.reducedText;
      types.add(match.displayType);
    }
    if (types.length == 1) return types.first;
    if (atoms.length == 1) return atoms.first.unitMatch!.displayType;
    final compatibleTypes =
        (_categories[group.reducedText] ?? const <UnitRecord>[])
        .map((unit) => unit.displayType)
        .toSet();
    if (compatibleTypes.length == 1) return compatibleTypes.first;
    return group.reducedText;
  }

  /// Convert [value] from [from] to [to].
  UnitConversionResult convert({
    required String value,
    required String from,
    required String to,
    NumberNotation? notation,
    int? decimals,
    bool? pythonCompat,
  }) {
    final number = parseValue(value);
    final fromText = normalizeExpression(from);
    final toText = normalizeExpression(to);
    final fromGroup = parseGroupOrThrow(fromText, label: 'from');
    final toGroup = parseGroupOrThrow(toText, label: 'to');
    if (!fromGroup.isCategoryMatch(toGroup)) {
      _log.warning(
        'refused: "$fromText" (${describeCategory(fromGroup)}) and '
        '"$toText" (${describeCategory(toGroup)}) are not compatible',
      );
      throw UnitConversionException(
        'Cannot convert from "$fromText" '
        '(${describeCategory(fromGroup)}) to "$toText" '
        '(${describeCategory(toGroup)}): these units do not measure the same '
        'quantity.',
        UnitErrorCode.incompatibleUnits,
        hint: 'List the units that can be converted with this one first '
            '(the find_compatible_units tool of the MCP server, or '
            '`convertall compatible <unit>`).',
      );
    }
    final usedNotation = notation ?? this.notation;
    final usedDecimals = (decimals ?? this.decimals).clamp(0, 15);
    // The Python compatibility mode computes with the factors as doubles, as
    // the historical implementation did: the same operations in the same
    // order, therefore the same bits.
    final compat = pythonCompat ?? this.pythonCompat;
    if (compat) {
      fromGroup.factor = Number.approximate(fromGroup.factor.toDouble());
      toGroup.factor = Number.approximate(toGroup.factor.toDouble());
    }
    var result = fromGroup.convert(
      number,
      toGroup,
      useBinaryFloatEquations: compat,
    );
    final isLinear = fromGroup.isLinear && toGroup.isLinear;
    _log.debug(
      '${fromGroup.reducedText.isEmpty ? fromText : fromGroup.reducedText} '
      '-> ${toGroup.reducedText.isEmpty ? toText : toGroup.reducedText}: '
      'factor ${fromGroup.factor.asFractionText ?? fromGroup.factor} / '
      '${toGroup.factor.asFractionText ?? toGroup.factor}',
    );
    // A conversion that goes through an equation (Celsius, Fahrenheit, gas
    // mark, liter per 100 km, screw size) adds constants of the order of a
    // hundred and subtracts them again: the mathematical result 0 comes back
    // as a residue of a few 1e-14, and the freezing point of water reads
    // "5.68434188608e-14 C" instead of "0 C".  Since the equations themselves
    // are known to ten significant figures at best, anything below 1e-10 is
    // zero.  (The graphical application keeps the residue in its display; the
    // command line and the MCP server, which show the number to a reader,
    // round it away.)
    if (!compat && !result.isExact && !result.isZero && result.toDouble().abs() < 1e-10) {
      _log.debug(
        'the residue ${result.toDouble()} of a non-linear conversion is '
        'rounded to zero',
      );
      // Keep the provenance: zero came through a floating-point equation and
      // must not acquire an exact fraction merely because its display snaps.
      result = Number.approximate(0.0);
    }
    // An overflow (a table index out of range, a huge power) must be a refused
    // conversion and not a printed "Infinity", as in the Python tool.
    if (!result.isFinite) {
      _log.error('the result of "$fromText" -> "$toText" is not finite');
      throw UnitConversionException(
        'Conversion result is not finite',
        UnitErrorCode.outOfRange,
        hint: 'The value is too large for this conversion.',
      );
    }
    _log.debug(
      'result ${result.asFractionText ?? result.toDouble()} '
      '(${result.isExact ? 'exact' : 'float'})',
    );
    return UnitConversionResult(
      value: result,
      formatted: formatValue(
        result,
        notation: usedNotation,
        decimals: usedDecimals,
        pythonCompat: compat,
      ),
      valueText: normalizeNumberText(value),
      // The expressions as they were given (not the expanded form), so that
      // the summary reads `100 km/hr = 27.777778 m/s`.
      fromText: fromText,
      toText: toText,
      fromReduced: fromGroup.reducedText,
      toReduced: toGroup.reducedText,
      factor: isLinear ? fromGroup.factor / toGroup.factor : null,
      fromCategory: describeCategory(fromGroup),
      toCategory: describeCategory(toGroup),
      notation: usedNotation,
      decimals: usedDecimals,
    );
  }

  /// Everything the database knows about [name].
  UnitDetails describeUnit(String name) {
    final record = requireUnit(name);
    final group = UnitGroup.parse(record.name, database);
    group.reduce();
    final compatible = compatibleUnits(record.name)
        .where((unit) => unit.name != record.name)
        .toList();
    return UnitDetails(
      unit: record,
      reduced: group.reducedGroup?.toString() ?? '',
      factor: group.factor,
      compatible: compatible,
    );
  }

  /// The units that can be converted with [unitText], alphabetical.
  ///
  /// This is the operation a language model needs most: it answers "what can I
  /// convert metres to?" without guessing names.
  List<UnitRecord> compatibleUnits(String unitText, {int limit = 50}) {
    final group = parseGroupOrThrow(unitText, label: 'unit');
    final key = group.reducedText;
    final matches = List.of(_categories[key] ?? const <UnitRecord>[]);
    if (limit > 0 && matches.length > limit) {
      return matches.sublist(0, limit);
    }
    return matches;
  }

  /// The number of units that can be converted with [unitText].
  int compatibleUnitCount(String unitText) {
    final group = parseGroupOrThrow(unitText, label: 'unit');
    return (_categories[group.reducedText] ?? const <UnitRecord>[]).length;
  }

  /// The units of the database, grouped by their reduced form.  Built on the
  /// first call, then reused: the data never changes while the process runs.
  Map<String, List<UnitRecord>> get _categories {
    final cached = _categoryIndex;
    if (cached != null) return cached;
    final index = <String, List<UnitRecord>>{};
    for (final record in database.units) {
      final key = _reducedKeyOf(record);
      if (key == null) continue;
      index.putIfAbsent(key, () => <UnitRecord>[]).add(record);
    }
    for (final records in index.values) {
      records.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    _log.debug(
      'indexed ${database.unitCount} units in ${index.length} groups of '
      'compatible units',
    );
    _categoryIndex = index;
    return index;
  }

  /// The reduced form of a single unit record, or `null` when it cannot be
  /// reduced (a non-linear unit combined with something else, a bad entry).
  String? _reducedKeyOf(UnitRecord record) {
    final cached = _reducedCache[record.name];
    if (cached != null) return cached;
    try {
      final group = UnitGroup.parse(record.name, database);
      if (!group.isLinearOrLegal) return null;
      final key = group.reducedText;
      _reducedCache[record.name] = key;
      return key;
    } on UnitConversionException {
      return null;
    }
  }

  /// Print [value] with the notation of the ConvertAll Python implementation
  /// (`%G`, `%f`, `%E`, engineering): the same characters as the historical
  /// command line, computed without any rounding of the exact path.
  ///
  /// An exact value is rendered from its rational; a float is first brought
  /// back to the shortest decimal that identifies it, so that a residue of
  /// `5.68434188608e-14` does not print as a dozen meaningless digits.
  static String formatValue(
    Number value, {
    NumberNotation notation = NumberNotation.short,
    int decimals = 8,
    bool pythonCompat = false,
  }) => formatNumber(
    value,
    notation: notation,
    decimals: decimals,
    pythonCompat: pythonCompat,
  );

  /// True when [text] is `nan`, `inf` or `infinity`, with an optional sign and
  /// any case (`float()` accepts them in Python, then the range check fails).
  static bool _isNonFiniteText(String text) {
    var name = text.trim().toLowerCase();
    if (name.startsWith('+') || name.startsWith('-')) {
      name = name.substring(1);
    }
    return name == 'nan' || name == 'inf' || name == 'infinity';
  }

  /// [value] as a `double`, for the callers that need a number rather than a
  /// `Number` (the MCP `structuredContent`).
  static double valueAsDouble(Number value) => value.toDouble();
}
