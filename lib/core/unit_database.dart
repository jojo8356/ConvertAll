// unit_database.dart, pure-Dart unit database (no Flutter dependency).
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// This is the unit data used by the command line tool (`bin/convertall.dart`)
// and by the MCP server (`bin/convertall_mcp.dart`).  It reads the same
// `assets/units.json` file as the graphical application, so the CLI, the MCP
// server and the GUI always convert with the same numbers.
//
// Differences with the GUI model (`lib/model/unit_data.dart`) are deliberate
// and documented in `docs/MCP.md`:
//  * a unit keeps both its canonical (English) type and its translated display
//    type, instead of having the type replaced in place;
//  * the leading numeric factor of an equivalent is always evaluated with the
//    Unicode minus signs normalised, so the six units stored with `\u2212`
//    (Planck mass, Planck length, ...) work;
//  * nothing is loaded through `rootBundle`: the JSON text is passed in.

import 'dart:convert' show json;
import 'dart:io' show File;

import 'package:eval_ex/expression.dart';
import 'package:rational/rational.dart';

import 'exact_math.dart';
import 'logging.dart';
import 'sha256.dart';
import 'unit_exceptions.dart';

/// The logger of the unit data.
final _log = loggerFor('catalog');

/// Characters used as a minus sign in text typed by hand or copied from a
/// document: hyphen, non-breaking hyphen, figure dash, en dash, em dash, minus
/// sign, small hyphen-minus and fullwidth hyphen-minus.
final _minusSigns = RegExp('[\u2010\u2011\u2012\u2013\u2014\u2212\uFE63\uFF0D]');

/// Space characters that are not the regular space: no-break space, figure
/// space, thin space and narrow no-break space (used as digit separators).
final _spaceLike = RegExp('[\u00A0\u2007\u2009\u202F]');

/// Return [text] with the Unicode minus signs replaced by an ASCII `-` and the
/// exotic spaces replaced by a regular space.  Unit expressions and equations
/// go through this, so that a value copied from a web page or a PDF is
/// readable.
String normalizeExpression(String text) {
  return text.replaceAll(_minusSigns, '-').replaceAll(_spaceLike, ' ').trim();
}

/// Like [normalizeExpression], and the spaces used as digit group separators
/// are removed so that `1 000` is read as `1000`.
///
/// A single comma is also accepted as the decimal separator when the text does
/// not already contain a dot (`1,5` is read as `1.5`).
String normalizeNumberText(String text) {
  var result = normalizeExpression(text).replaceAll(RegExp(r'\s+'), '');
  if (!result.contains('.') && _singleComma.hasMatch(result)) {
    result = result.replaceAll(',', '.');
  }
  return result;
}

final _singleComma = RegExp(r'^[+-]?[0-9]+,[0-9]+$');

/// Evaluate an arithmetic expression such as `1/8`, `2.5*4` or `1e-7`.
///
/// Return `null` when the text is not a valid expression.  Both the raw text
/// and a version stripped of its spaces are tried, then the Unicode minus
/// signs are normalised, so that `- 3` and `\u22123` are accepted.
double? tryEvaluateNumber(String text) {
  final normalized = normalizeExpression(text);
  if (normalized.isEmpty) return null;
  final candidates = <String>[
    normalized,
    normalized.replaceAll(RegExp(r'\s+'), ''),
    normalizeNumberText(text),
  ];
  for (final candidate in candidates) {
    if (candidate.isEmpty) continue;
    try {
      final value = Expression(candidate).eval();
      if (value != null) return value.toDouble();
    } on ExpressionException {
      continue;
    } on FormatException {
      continue;
    }
  }
  return null;
}

/// One unit of the database, with the data needed to convert it.
class UnitRecord {
  UnitRecord._({
    required this.name,
    required this.canonicalType,
    required this.displayType,
    required this.equiv,
    required this.factor,
    required this.fromEqn,
    required this.toEqn,
    required this.unabbrev,
    required this.comment,
    required this.searchTerms,
  });

  /// Build a record from one entry of `assets/units.json`.
  ///
  /// [localizeType] translates the canonical English type name into the
  /// display language (see `assets/units_fr.json`); when it is `null` the
  /// canonical name is used.
  factory UnitRecord.fromJson(
    Map<String, Object?> data, {
    String Function(String canonicalType)? localizeType,
  }) {
    final name = data['name'] as String?;
    if (name == null || name.isEmpty) {
      throw UnitDataException('Unit data entry without a name.');
    }
    final canonicalType = (data['type'] as String?) ?? 'unknown';
    final fromEqn = (data['fromeqn'] as String?) ?? '';
    final toEqn = (data['toeqn'] as String?) ?? '';
    final unabbrev = (data['unabbrev'] as String?) ?? '';
    final comment = (data['comment'] as String?) ?? '';
    var equiv = normalizeExpression((data['equiv'] as String?) ?? '');
    var factor = Rational.one;
    // A linear unit is stored as "<number> <unit>", e.g. "0.001 kg": the
    // number becomes the factor and the rest is the equivalent unit.  Units
    // with an equation (`fromeqn`) keep their equivalent unchanged, since
    // their factor is the one of the unit they are linearised to.
    //
    // The factor is read **exactly** (`1/16.0` is 1/16, `2.176434e-8` is the
    // decimal it looks like): that is what makes `1 in = 2.54 cm` exact on the
    // command line.  The float evaluation of `eval_ex` stays as a fallback
    // for a hand edited catalogue the exact parser does not read.
    if (fromEqn.isEmpty) {
      final parts = equiv.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
      if (parts.length > 1) {
        final exact = ExactMath.tryEvaluate(parts.first);
        final fallback = exact == null
            ? tryEvaluateNumber(parts.first)
            : null;
        final value = exact ??
            (fallback == null ? null : ExactMath.fromDouble(fallback));
        if (value != null) {
          if (exact == null) {
            // A warning, not an error: the conversion still works, but the
            // result may carry a binary rounding artefact.
            _log.warning(
              'the factor "$name = ${parts.first}" is not an exact decimal, '
              'it is read as ${ExactMath.toExactText(value)}',
            );
          }
          factor = value;
          equiv = parts.sublist(1).join(' ');
        }
      }
    }
    if (equiv.isEmpty) {
      throw UnitDataException('Invalid equivalent for unit "$name".');
    }
    return UnitRecord._(
      name: name,
      canonicalType: canonicalType,
      displayType: localizeType?.call(canonicalType) ?? canonicalType,
      equiv: equiv,
      factor: factor,
      fromEqn: fromEqn,
      toEqn: toEqn,
      unabbrev: unabbrev,
      comment: comment,
      searchTerms: name.toLowerCase().split(RegExp(r'\s+')),
    );
  }

  /// The unit name as typed by the user (`cm`, `km/hr` is not a unit, `mile`).
  final String name;

  /// The type as stored in the data (`length`, `mass`, ...).
  final String canonicalType;

  /// The type as shown to the user, translated when a language pack is loaded.
  final String displayType;

  /// The equivalent unit, without its leading numeric factor (`kg` for
  /// `gram`, `!` for a base unit, `!!` for a placeholder).
  final String equiv;

  /// The exact factor of the equivalent (`1/1000` for `gram`).
  ///
  /// Rational and not `double`: a linear conversion multiplies and divides
  /// these factors, and the result is exact as long as no equation or
  /// interpolation table is involved (specification §3.4).
  final Rational factor;

  /// The factor as text: `0.3048`, or `5/9` when the decimal never terminates.
  String get factorText => ExactMath.toExactText(factor);

  /// Equation used to convert *from* the unit (empty for a linear unit).
  final String fromEqn;

  /// Equation used to convert *to* the unit (empty for a linear unit).
  final String toEqn;

  /// Spelled out name used as a hint, e.g. `kilometer` for `km`.
  final String unabbrev;

  /// Free-form comment from the data (`metric`, `non-linear`, ...).
  final String comment;

  /// Lower-case words of [name], used by the partial matching.
  final List<String> searchTerms;

  /// True for the eleven units defined as a base (`m`, `kg`, ... `equiv: "!"`).
  bool get isBaseUnit => equiv.startsWith('!');

  /// True for the placeholder units removed from the reduced forms.
  bool get isPlaceholder => equiv == '!!' || name == 'unit';

  /// True when the unit needs an equation or a table to be converted
  /// (Celsius, gas mark, liter per 100 km, ...).
  bool get isNonLinear => fromEqn.isNotEmpty;

  /// `m` or `meter (m)`, the label used in listings.
  String get label => unabbrev.isEmpty ? name : '$name ($unabbrev)';

  /// True if the unit's words match one of the words of [wordList], by prefix.
  bool isPartialMatch(List<String> wordList) {
    for (final word in wordList) {
      if (word.isEmpty) continue;
      for (final key in searchTerms) {
        if (key.startsWith(word)) return true;
      }
    }
    return false;
  }

  @override
  String toString() => name;
}

/// The unit database: the list of units, indexed for exact and partial lookup.
class UnitDatabase {
  UnitDatabase._(this.units, this._typeNames);

  /// All the units, in the order of the data file.
  final List<UnitRecord> units;

  /// Display type names, sorted, without duplicates.
  final List<String> _typeNames;

  final _byKey = <String, UnitRecord>{};
  final _byType = <String, List<UnitRecord>>{};
  final _byName = <String, UnitRecord>{};

  /// The path of the units file this database was read from, when there is
  /// one (`null` for the assets embedded in the application).
  String? sourcePath;

  /// The SHA-256 of the units file, when it was read from disk.
  String? sourceSha256;

  /// The path of the type name translation file, when there is one.
  String? typeNamesPath;

  /// Number of units in the database.
  int get unitCount => units.length;

  /// The canonical (English) type names, sorted.
  List<String> get canonicalTypes {
    final types = units.map((unit) => unit.canonicalType).toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return types;
  }

  /// The units of a type, in catalogue order.
  List<UnitRecord> recordsOfType(String type) =>
      List.unmodifiable(_byType[type] ?? const <UnitRecord>[]);

  /// Load the database from the JSON texts.
  ///
  /// [unitsJson] is the content of `assets/units.json`; [typeNamesJson] is the
  /// optional content of a translation file such as `assets/units_fr.json`.
  static UnitDatabase fromJsonTexts(
    String unitsJson, {
    String? typeNamesJson,
    String? sourcePath,
    String? sourceSha256,
    String? typeNamesPath,
  }) {
    final typeNames = <String, String>{};
    if (typeNamesJson != null && typeNamesJson.trim().isNotEmpty) {
      final decoded = json.decode(typeNamesJson);
      if (decoded is Map) {
        decoded.forEach((key, value) {
          if (key is String && value is String) typeNames[key] = value;
        });
      }
    }
    final decodedUnits = json.decode(unitsJson);
    if (decodedUnits is! List) {
      throw UnitDataException('The unit data must be a JSON list of units.');
    }
    final database = fromDataList(decodedUnits, typeNames: typeNames);
    database.sourcePath = sourcePath;
    database.sourceSha256 = sourceSha256;
    database.typeNamesPath = typeNamesPath;
    return database;
  }

  /// Build the database from an already decoded `units.json`.
  static UnitDatabase fromDataList(
    List<Object?> dataList, {
    Map<String, String> typeNames = const {},
  }) {
    final units = <UnitRecord>[];
    final typeNamesSeen = <String>{};
    for (final item in dataList) {
      if (item is! Map) {
        throw UnitDataException('Invalid entry in the unit data.');
      }
      final record = UnitRecord.fromJson(
        item.cast<String, Object?>(),
        localizeType: (canonicalType) => typeNames[canonicalType] ?? canonicalType,
      );
      units.add(record);
      typeNamesSeen.add(record.displayType);
    }
    final names = typeNamesSeen.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return UnitDatabase._(units, names);
  }

  /// Load the database from files on disk.  Used by the CLI and the MCP server.
  ///
  /// The path and the SHA-256 of the file are kept on the database: the JSON
  /// output and `doctor` report them, so that a result can always be traced
  /// back to the catalogue that produced it (specification annexe C).
  static UnitDatabase fromFiles({
    required String unitsPath,
    String? typeNamesPath,
  }) {
    final unitsFile = File(unitsPath);
    if (!unitsFile.existsSync()) {
      throw UnitDataException('Unit data file not found: $unitsPath');
    }
    _log.info('reading the unit data from $unitsPath');
    String? typeNamesJson;
    if (typeNamesPath != null) {
      final typeNamesFile = File(typeNamesPath);
      if (typeNamesFile.existsSync()) {
        typeNamesJson = typeNamesFile.readAsStringSync();
      }
    }
    final database = fromJsonTexts(
      unitsFile.readAsStringSync(),
      typeNamesJson: typeNamesJson,
      sourcePath: unitsPath,
      sourceSha256: sha256HexOfFileSync(unitsPath),
      typeNamesPath: typeNamesPath,
    );
    _log.info(
      '${database.unitCount} units in ${database.canonicalTypes.length} '
      'quantities loaded from $unitsPath',
    );
    return database;
  }

  /// Fill the lookup indexes.  Called once, by the constructor callers.
  void _index() {
    if (_byKey.isNotEmpty) return;
    for (final unit in units) {
      _byKey[unit.name.toLowerCase().replaceAll(' ', '')] = unit;
      _byName.putIfAbsent(unit.name, () => unit);
      final keys = {
        unit.canonicalType.toLowerCase(),
        unit.displayType.toLowerCase(),
      };
      for (final key in keys) {
        _byType.putIfAbsent(key, () => <UnitRecord>[]).add(unit);
      }
    }
  }

  /// The display type names, sorted (translated when a language pack is used).
  List<String> get displayTypes => List.unmodifiable(_typeNames);

  /// The exact match for a unit name, ignoring case and spaces (`deg C` is
  /// found by `degc`) or `null`.
  UnitRecord? exactMatch(String name) {
    _index();
    final key = normalizeExpression(name).toLowerCase().replaceAll(' ', '');
    return _byKey[key];
  }

  /// A [UnitRecord] for every unit of the database, by exact name.
  UnitRecord? byExactName(String name) {
    _index();
    return _byName[normalizeExpression(name)];
  }

  /// The units whose name starts with one of the words of [searchTerm].
  ///
  /// An empty search term returns the whole list.
  List<UnitRecord> partialMatches(String searchTerm, {int? limit}) {
    final term = normalizeExpression(searchTerm).toLowerCase();
    if (term.isEmpty) {
      return _limited(units, limit);
    }
    final wordList = term.split(RegExp(r'\s+'));
    final matches = units.where((unit) => unit.isPartialMatch(wordList)).toList();
    return _limited(matches, limit);
  }

  /// The units of a type, matched on the canonical or the display name,
  /// ignoring case.  An unknown type returns an empty list.
  List<UnitRecord> unitsOfType(String type, {int? limit}) {
    _index();
    final key = normalizeExpression(type).toLowerCase();
    final direct = _byType[key];
    if (direct != null) return _limited(List.of(direct), limit);
    final prefixMatches = <UnitRecord>[];
    final seen = <String>{};
    _byType.forEach((typeKey, records) {
      if (typeKey.startsWith(key) || key.startsWith(typeKey)) {
        for (final record in records) {
          if (seen.add(record.name)) prefixMatches.add(record);
        }
      }
    });
    return _limited(prefixMatches, limit);
  }

  /// The number of units of a type (canonical or display name).
  int countOfType(String type) => unitsOfType(type).length;

  /// The canonical type name for a canonical or display type name, or the
  /// input when it cannot be resolved.
  String canonicalTypeOf(String type) {
    _index();
    final key = normalizeExpression(type).toLowerCase();
    for (final unit in units) {
      final canonical = unit.canonicalType.toLowerCase();
      final display = unit.displayType.toLowerCase();
      if (canonical == key || display == key) {
        return unit.canonicalType;
      }
    }
    return type;
  }

  List<UnitRecord> _limited(List<UnitRecord> records, int? limit) {
    if (limit == null || limit < 0 || records.length <= limit) return records;
    return records.sublist(0, limit);
  }
}
