// unit_expression.dart, pure-Dart unit expression parser and converter.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// Faithful port of `lib/model/unit_group.dart` for a Dart program without
// Flutter: the only changes are
//  * the unit database is passed in instead of being read from the
//    `UnitController.unitData` static of the GUI;
//  * the editing helpers that only matter for a text cursor
//    (`unitAtPosition`, `replaceUnit`, `replaceExponent`) are not needed here;
//  * `reduce()` is idempotent (it restarts from a factor of 1.0) and cannot
//    crash on a value outside an interpolation table;
//  * the errors carry a machine readable code (see [UnitErrorCode]);
//  * the numeric factors are exact rationals ([Number]) instead of `double`,
//    so `1 in = 2.54 cm` is exact (specification §3.4, "deux moteurs").
//
// Keep this file in sync with `unit_group.dart`: `test/core/parity_test.dart`
// compares both implementations on a matrix of conversions and fails when
// they drift apart.

import 'dart:convert' show json;

import 'package:decimal/decimal.dart';
import 'package:eval_ex/expression.dart';

import 'exact_number.dart';
import 'logging.dart';
import 'unit_database.dart';
import 'unit_exceptions.dart';

/// The logger of the expression parser and the conversion arithmetic.
final _log = loggerFor('units');

/// Common interface of a unit and of a parenthesis subgroup, so that both can
/// appear in a [UnitGroup].
abstract class UnitItem {
  /// True when every unit is known and every exponent is complete.
  bool get isValid;

  /// True when the item is valid and uses only linear units.
  bool get isLinear;

  /// True when the first exponent of the item is positive (`1/s` is not).
  bool get isFirstExpPositive;
}

/// A group of units combined with `*` and `/`, with parenthesis subgroups.
class UnitGroup implements UnitItem {
  UnitGroup(this.database);

  /// Parse [groupString] and return the resulting group.
  factory UnitGroup.parse(String groupString, UnitDatabase database) {
    final group = UnitGroup(database);
    group.parse(groupString);
    return group;
  }

  /// The unit data used to resolve the unit names.
  final UnitDatabase database;

  /// The units and subgroups of this group, in the order they were typed.
  final unitItems = <UnitItem>[];

  /// The reduced form, computed on demand by [reduce].
  UnitGroup? reducedGroup;

  /// Product of the numeric factors of the units of this group.
  ///
  /// An exact rational as long as every unit of the group has an exact factor
  /// and every exponent is an integer; a float when a fractional exponent
  /// (`m^1.5`) or a non-linear unit is involved.
  Number factor = Number.one;

  /// False when the text ends on an opened parenthesis (`(m/s`).
  bool parenthClosed = true;

  /// Parse [groupString] into this group.
  ///
  /// When [clearFirst] is false the parsed items are appended to the existing
  /// ones (used for subgroups, to keep the parenthesis flag set before the
  /// call).
  void parse(String groupString, {bool clearFirst = true}) {
    final text = normalizeExpression(groupString);
    if (clearFirst) {
      unitItems.clear();
      reducedGroup = null;
      factor = Number.one;
      parenthClosed = true;
    }
    var startPos = 0;
    var negativeExp = false;
    // Use a non-greedy regexp for multiple independent parenthesis, and a
    // greedy one for nested parenthesis.
    final regExp = RegExp(r'\([^()]*\)').allMatches(text).length > 1
        ? RegExp(r'\(.*?\)|\(.*$|[\*/]')
        : RegExp(r'\(.*\)|\(.*$|[\*/]');
    final matches = List.of(regExp.allMatches(text));
    while (matches.isNotEmpty) {
      var match = matches.removeAt(0);
      var matchText = match[0]!;
      if (matchText.startsWith('(')) {
        final subgroup = UnitGroup(database);
        if (matchText.endsWith(')')) {
          matchText = matchText.substring(1, matchText.length - 1).trim();
        } else {
          matchText = matchText.substring(1).trim();
          subgroup.parenthClosed = false;
        }
        // Don't clear in order to preserve the parenthesis flag.
        subgroup.parse(matchText, clearFirst: false);
        unitItems.add(subgroup);
        if (negativeExp) {
          for (final unit in subgroup.flatUnits) {
            unit.unitExp = -unit.unitExp;
          }
        }
        if (matches.isNotEmpty) {
          // Consume the operator following the parenthesis.
          match = matches.removeAt(0);
        }
      } else {
        unitItems.add(
          UnitAtom.parse(
            unitString: text.substring(startPos, match.start).trim(),
            database: database,
            negativeExp: negativeExp,
          ),
        );
      }
      startPos = match.end;
      negativeExp = matchText == '/';
    }
    if (unitItems.isEmpty || unitItems.last is UnitAtom) {
      unitItems.add(
        UnitAtom.parse(
          unitString: text.substring(startPos).trim(),
          database: database,
          negativeExp: negativeExp,
        ),
      );
    }
  }

  /// Remove every unit of the group.
  void clear() {
    unitItems.clear();
    reducedGroup = null;
    factor = Number.one;
    parenthClosed = true;
  }

  @override
  bool get isValid =>
      unitItems.isNotEmpty &&
      unitItems.every((unit) => unit.isValid) &&
      parenthClosed;

  @override
  bool get isLinear => isValid && unitItems.every((unit) => unit.isLinear);

  /// True for a valid linear group, or for a valid non-linear group made of a
  /// single unit without exponent (the only non-linear forms that can be
  /// converted).
  bool get isLinearOrLegal {
    if (isLinear) return true;
    final flatList = flatUnits;
    return isValid && flatList.length == 1 && flatList.first.unitExp == 1;
  }

  @override
  bool get isFirstExpPositive {
    final flatList = flatUnits;
    return flatList.isEmpty || flatList[0].unitExp >= 0;
  }

  /// Every unit of the group, subgroups flattened, in typing order.
  List<UnitAtom> get flatUnits {
    final result = <UnitAtom>[];
    for (final item in unitItems) {
      if (item is UnitGroup) {
        result.addAll(item.flatUnits);
      } else if (item is UnitAtom) {
        result.add(item);
      }
    }
    return result;
  }

  /// The first unit of the group that is not in the database, or `null`.
  UnitAtom? get firstUnknownUnit {
    for (final atom in flatUnits) {
      if (atom.unitMatch == null || !atom.isExpValid) return atom;
    }
    return null;
  }

  /// True when a parenthesis was opened and never closed.
  bool get hasUnclosedParenthesis {
    if (!parenthClosed) return true;
    for (final item in unitItems) {
      if (item is UnitGroup && item.hasUnclosedParenthesis) return true;
    }
    return false;
  }

  /// True when a non-linear unit is combined with something else, which is not
  /// supported (only a single non-linear unit can be converted).
  bool get hasIllegalNonLinearUse {
    if (!isValid || isLinear) return false;
    return !isLinearOrLegal;
  }

  /// The only unit of a single-unit group, or `null` for a compound group.
  UnitAtom? get singleUnit {
    final flatList = flatUnits;
    return flatList.length == 1 ? flatList.first : null;
  }

  /// Render the group the way it is typed, using `*` and `/`.
  @override
  String toString({bool swapExp = false}) {
    final strList = <String>[];
    for (final unit in unitItems) {
      if (strList.isNotEmpty) {
        var isMultiply = unit.isFirstExpPositive;
        if (swapExp) isMultiply = !isMultiply;
        strList.add(isMultiply ? '*' : '/');
      }
      if (unit is UnitAtom) {
        strList.add(unit.toString(absExp: strList.isNotEmpty || swapExp));
      } else if (unit is UnitGroup) {
        var isSwapped = swapExp;
        if (strList.isNotEmpty && !unit.isFirstExpPositive) {
          isSwapped = !isSwapped;
        }
        final groupText = unit.toString(swapExp: isSwapped);
        strList.add(unit.parenthClosed ? '($groupText)' : '($groupText');
      }
    }
    return strList.join(' ');
  }

  /// Calculate the reduced equivalent unit and the factor of the group.
  ///
  /// The equivalent of every unit is expanded until only base units are left
  /// (`km/hr` becomes `m / s` with a factor of 0.2777...).  Do nothing if the
  /// group is invalid, and nothing at all when called twice.
  void reduce() {
    if (reducedGroup != null || !isValid) return;
    final rawReducedList = <UnitAtom>[];
    var count = 0;
    // Restart from one so that the method is idempotent.
    factor = Number.one;
    final expandedList = flatUnits;
    while (expandedList.isNotEmpty) {
      count += 1;
      if (count > 5000) {
        throw UnitConversionException(
          'Circular unit definition while reducing "$this".',
          UnitErrorCode.circularDefinition,
        );
      }
      final unit = expandedList.removeAt(0);
      final match = unit.unitMatch;
      if (match == null) continue;
      if (match.equiv.startsWith('!')) {
        rawReducedList.add(unit.duplicate());
      } else {
        final newGroup = UnitGroup(database)..parse(match.equiv);
        final newList = newGroup.flatUnits;
        for (final newUnit in newList) {
          newUnit.unitExp *= unit.unitExp;
        }
        expandedList.addAll(newList);
        // The factor of the unit is raised to the power of its exponent: exact
        // for an integer exponent (`km/hr` -> `1/3.6`), an approximation for a
        // fractional one (`m^1.5` is a square root), which the logger reports.
        final exponent = unit.unitExp;
        final contribution = Number.exact(match.factor).pow(exponent);
        if (!contribution.isExact && exponent is double) {
          _log.debug(
            'the exponent $exponent of "${match.name}" is not an integer: '
            'the factor of "$this" is only approximate',
          );
        }
        factor *= contribution;
      }
    }
    rawReducedList.sort(
      (a, b) => (a.unitMatch?.name.toLowerCase() ?? '').compareTo(
        b.unitMatch?.name.toLowerCase() ?? '',
      ),
    );
    final reducedList = <UnitAtom>[];
    for (final unit in rawReducedList) {
      if (reducedList.isNotEmpty && unit.unitMatch == reducedList.last.unitMatch) {
        reducedList.last.unitExp += unit.unitExp;
      } else {
        reducedList.add(unit);
      }
    }
    reducedList.removeWhere(
      (unit) =>
          unit.unitMatch!.equiv == '!!' ||
          unit.unitMatch!.name == 'unit' ||
          unit.unitExp == 0,
    );
    final reduced = UnitGroup(database);
    reduced.unitItems.addAll(reducedList);
    reducedGroup = reduced;
  }

  /// The reduced form (`m / s` for `km/hr`), or an empty string when the group
  /// cannot be reduced.
  String get reducedText {
    reduce();
    return reducedGroup?.toString() ?? '';
  }

  /// True when both groups reduce to the same base units (`km/hr` and `m/s`).
  bool isCategoryMatch(UnitGroup otherGroup) {
    if (!isLinearOrLegal || !otherGroup.isLinearOrLegal) return false;
    reduce();
    otherGroup.reduce();
    final mine = reducedGroup;
    final other = otherGroup.reducedGroup;
    if (mine == null || other == null) return false;
    return mine.toString() == other.toString();
  }

  /// Convert [value] from this group into [toGroup].
  ///
  /// Assumes that [isCategoryMatch] was checked before.  The result is exact
  /// when both groups are linear (`1 in` -> `2.54 cm`); it is a float as soon
  /// as an equation or an interpolation table is used (`0 C` -> `273.15 K`),
  /// because those are defined in floating point by the specification.
  Number convert(Number value, UnitGroup toGroup) {
    var result = value;
    if (isLinear) {
      result *= factor;
    } else {
      result = _nonLinearCalc(result, true) * factor;
    }
    if (toGroup.isLinear) {
      result /= toGroup.factor;
    } else {
      result = toGroup._nonLinearCalc(result / toGroup.factor, false);
    }
    return result;
  }

  /// Apply the equation of a non-linear unit, or interpolate its table.
  Number _nonLinearCalc(Number value, bool isFrom) {
    final unit = flatUnits.first.unitMatch!;
    final number = value.toDouble();
    double? result;
    if (unit.toEqn.isNotEmpty) {
      // Regular equations, e.g. Celsius: "x + 273.15".  They run in double
      // precision, as the specification requires (§3.4): the equations are
      // written for `f64` and must give the same answer as the other
      // implementations.
      try {
        final expr = Expression(isFrom ? unit.fromEqn : unit.toEqn);
        expr.setDecimalVariable('x', Decimal.parse(number.toString()));
        result = expr.eval()?.toDouble();
      } on ExpressionException {
        result = null;
      } on FormatException {
        result = null;
      }
      _log.debug(
        'equation "${isFrom ? unit.fromEqn : unit.toEqn}" applied to '
        '$number for "${unit.name}"',
      );
    } else {
      // Interpolation between the points of a table, e.g. gas mark.
      result = _interpolate(unit, number, isFrom);
    }
    if (result == null) {
      throw UnitConversionException(
        'Invalid equation for unit "${unit.name}".',
        UnitErrorCode.invalidUnitExpression,
      );
    }
    return Number.approximate(result);
  }

  /// Interpolate [value] in the conversion table stored in the unit data.
  double _interpolate(UnitRecord unit, double value, bool isFrom) {
    List<Object?>? decoded;
    try {
      final data = json.decode(unit.fromEqn);
      if (data is List) decoded = data;
    } on FormatException {
      decoded = null;
    }
    if (decoded == null || decoded.length < 2) {
      throw UnitConversionException(
        'Invalid conversion table for unit "${unit.name}".',
        UnitErrorCode.invalidUnitExpression,
      );
    }
    final pairs = <List<double>>[];
    for (final pair in decoded) {
      if (pair is List && pair.length >= 2 && pair[0] is num && pair[1] is num) {
        pairs.add([(pair[0] as num).toDouble(), (pair[1] as num).toDouble()]);
      }
    }
    if (pairs.length < 2) {
      throw UnitConversionException(
        'Invalid conversion table for unit "${unit.name}".',
        UnitErrorCode.invalidUnitExpression,
      );
    }
    if (!isFrom) {
      // The table is stored from the unit to the base unit; the reverse
      // conversion swaps every pair.
      for (final pair in pairs) {
        final tmp = pair[0];
        pair[0] = pair[1];
        pair[1] = tmp;
      }
    }
    pairs.sort((a, b) => a[0].compareTo(b[0]));
    if (value < pairs.first[0] || value > pairs.last[0]) {
      throw UnitConversionException(
        'The value $value is outside the range '
        '${pairs.first[0]} to ${pairs.last[0]} supported by "${unit.name}".',
        UnitErrorCode.outOfRange,
      );
    }
    var pos = pairs.indexWhere((pair) => value <= pair[0]);
    if (pos == 0) pos = 1;
    final lower = pairs[pos - 1];
    final upper = pairs[pos];
    final span = upper[0] - lower[0];
    if (span == 0) {
      throw UnitConversionException(
        'Invalid conversion table for unit "${unit.name}": duplicate values.',
        UnitErrorCode.invalidUnitExpression,
      );
    }
    return (value - lower[0]) / span * (upper[1] - lower[1]) + lower[1];
  }
}

/// A single unit with its exponent (`cm`, `s^-1`, `m^2`).
class UnitAtom implements UnitItem {
  UnitAtom._({
    this.unitName,
    this.unitMatch,
    required this.unitExp,
    this.partialExp,
    required this.isExpValid,
  });

  /// Parse one unit, e.g. `m`, `m^2` or `m^-1`.
  ///
  /// The unit name is unknown when no exact match exists in [database]; the
  /// caller decides whether that is an error.
  factory UnitAtom.parse({
    required String unitString,
    required UnitDatabase database,
    bool negativeExp = false,
  }) {
    final parts = unitString.split('^');
    num unitExp = 1;
    String? partialExp;
    var isExpValid = true;
    if (parts.length > 1) {
      final expText = parts.sublist(1).join().trim();
      final intExp = int.tryParse(expText);
      if (intExp != null) {
        unitExp = intExp;
        if (intExp.abs() == 1) {
          // Keep the partial exponent for the start of typing '1.5' or '-1.5'.
          partialExp = '^$expText';
        } else if (expText == '-0') {
          // Keep the partial exponent for the start of typing '-0.5'.
          partialExp = '^-0';
        }
      } else {
        final doubleExp = double.tryParse(expText);
        if (doubleExp != null) {
          unitExp = doubleExp;
          if (expText.endsWith('.')) {
            // Keep the partial exponent for the start of typing '1.5'.
            partialExp = '^$expText';
          }
        } else {
          partialExp = expText == '.'
              ? '^0.'
              : expText == '-.'
              ? '^-0.'
              : expText.startsWith('-')
              ? '^-'
              : '^';
          isExpValid = false;
        }
      }
    }
    final unitText = parts[0].trim();
    var match = database.exactMatch(unitText);
    if (match == null) {
      if (unitText.endsWith('2') || unitText.endsWith('3')) {
        // 'm2' and 'm3' are squares and cubes.
        final tmpMatch = database.exactMatch(
          unitText.substring(0, unitText.length - 1),
        );
        if (tmpMatch != null && unitExp == 1 && partialExp == null) {
          match = tmpMatch;
          unitExp = unitText.endsWith('2') ? 2 : 3;
        }
      } else if ((unitText.endsWith('s') || unitText.endsWith('S')) &&
          database.partialMatches(unitText).isEmpty) {
        // A trailing 's' is accepted as a plural ('pounds').
        match = database.exactMatch(unitText.substring(0, unitText.length - 1));
      }
    }
    if (negativeExp) {
      unitExp = -unitExp;
      if (isExpValid && partialExp != null) {
        partialExp = partialExp.replaceFirst('^-', '^');
      }
    }
    return UnitAtom._(
      unitName: match == null ? unitText : null,
      unitMatch: match,
      unitExp: unitExp,
      partialExp: partialExp,
      isExpValid: isExpValid,
    );
  }

  /// The typed name, kept when no unit of the database matches it.
  final String? unitName;

  /// The matching unit of the database, or `null`.
  final UnitRecord? unitMatch;

  /// The exponent of the unit, an integer or a double (`m^1.5`).
  num unitExp;

  /// The exponent as typed, kept for a partially typed exponent (`m^1.`).
  String? partialExp;

  /// False when the exponent is not complete (`m^-`).
  final bool isExpValid;

  @override
  bool get isValid => unitMatch != null && isExpValid;

  @override
  bool get isLinear => isValid && unitMatch!.fromEqn.isEmpty;

  @override
  bool get isFirstExpPositive => unitExp >= 0;

  /// The name to show in a message: the typed name, or the resolved one.
  String get displayName => unitMatch?.name ?? unitName ?? '';

  @override
  String toString({bool absExp = false}) {
    final name = unitMatch?.name ?? unitName ?? '';
    if (partialExp != null) {
      return '$name$partialExp';
    }
    final tmpExp = absExp ? unitExp.abs() : unitExp;
    if (tmpExp != 1) {
      return '$name^$tmpExp';
    }
    return name;
  }

  /// A copy of this atom, used while reducing a group.
  UnitAtom duplicate() {
    return UnitAtom._(
      unitName: unitName,
      unitMatch: unitMatch,
      unitExp: unitExp,
      partialExp: partialExp,
      isExpValid: isExpValid,
    );
  }
}
