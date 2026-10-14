// mcp_tools.dart, the tools exposed by the ConvertAll MCP server.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// Five read-only tools cover what a language model needs to answer a unit
// question: convert a value, list the quantities, search a unit, describe a
// unit, and list the units compatible with another one.  Every tool declares
// an `inputSchema` (validated before the call), an `outputSchema` (the shape of
// the `structuredContent` member of the result) and its annotations.  The tool
// names follow the rules of the specification: 1 to 128 characters, ASCII
// letters, digits, `_`, `-` and `.` only.

import '../core/conversion_engine.dart';
import '../core/unit_exceptions.dart';
import '../core/unit_json.dart';

/// What a tool call produces.
class ToolOutcome {
  /// A successful call: [text] is read by the model, [structured] matches the
  /// tool's `outputSchema` and is returned as `structuredContent`.
  ToolOutcome.success(String text, {Map<String, Object?>? structured})
    : text = text,
      structured = structured,
      errorCode = null,
      suggestions = const [];

  /// A failed call: the tool was found and the arguments were valid, but the
  /// conversion could not be done (unknown unit, incompatible units, ...).
  ///
  /// The specification reports these inside the result with `isError: true`,
  /// and never as a protocol error, so that the model can read the message and
  /// correct itself.  [errorCode] is one of the [UnitErrorCode] values.
  ToolOutcome.failure(
    String text, {
    this.errorCode,
    this.suggestions = const [],
  }) : text = text,
       structured = null;

  /// Human readable result, or the explanation of the failure.
  final String text;

  /// The structured result, or `null` when the call failed.
  final Map<String, Object?>? structured;

  /// Machine readable failure code, `null` for a successful call.
  final String? errorCode;

  /// Unit names that may have been meant instead, for an unknown unit.
  final List<String> suggestions;

  bool get isError => errorCode != null;
}

/// The hints of a tool, as defined by `ToolAnnotations`.
class ToolAnnotations {
  const ToolAnnotations({
    this.title,
    this.readOnlyHint = true,
    this.destructiveHint = false,
    this.idempotentHint = true,
    this.openWorldHint = false,
  });

  final String? title;

  /// True: no tool of this server modifies anything.
  final bool readOnlyHint;

  final bool destructiveHint;

  /// True: calling a tool twice with the same arguments gives the same result.
  final bool idempotentHint;

  /// False: the tools only use the embedded unit data, no network.
  final bool openWorldHint;

  Map<String, Object?> toJson() => {
    if (title != null) 'title': title,
    'readOnlyHint': readOnlyHint,
    'destructiveHint': destructiveHint,
    'idempotentHint': idempotentHint,
    'openWorldHint': openWorldHint,
  };
}

/// One tool of the server.
class McpTool {
  McpTool({
    required this.name,
    required this.title,
    required this.description,
    required this.inputSchema,
    required this.outputSchema,
    required this.handler,
    this.annotations = const ToolAnnotations(),
  });

  final String name;
  final String title;
  final String description;
  final Map<String, Object?> inputSchema;
  final Map<String, Object?> outputSchema;
  final ToolAnnotations annotations;
  final ToolOutcome Function(Map<String, Object?> arguments) handler;

  /// The tool definition sent by `tools/list`.
  Map<String, Object?> toJson() => {
    'name': name,
    'title': title,
    'description': description,
    'inputSchema': inputSchema,
    'outputSchema': outputSchema,
    'annotations': annotations.toJson(),
  };
}

/// The JSON shape of a unit in the results.
Map<String, Object?> _unitSchema() => {
  'type': 'object',
  'properties': {
    'name': {'type': 'string', 'description': 'Name to use in a conversion.'},
    'type': {'type': 'string', 'description': 'Quantity, e.g. length.'},
    'type_display': {'type': 'string', 'description': 'Translated quantity name.'},
    'unabbrev': {'type': 'string', 'description': 'Spelled out name, when known.'},
    'comment': {'type': 'string', 'description': 'Extra data from the database.'},
    'equivalent': {
      'type': 'string',
      'description': 'Unit this one is defined against ("!" for a base unit).',
    },
    'non_linear': {
      'type': 'boolean',
      'description': 'True when converting needs an equation or a table.',
    },
    'base_unit': {'type': 'boolean', 'description': 'True for a base unit.'},
  },
  'required': ['name', 'type', 'type_display', 'equivalent', 'non_linear', 'base_unit'],
  'additionalProperties': false,
};

/// The tools of the ConvertAll MCP server.
List<McpTool> buildConversionTools(ConversionEngine engine) => [
  _convertValueTool(engine),
  _listUnitTypesTool(engine),
  _searchUnitsTool(engine),
  _getUnitInfoTool(engine),
  _findCompatibleUnitsTool(engine),
];

/// The guidance sent in `DiscoverResult.instructions` and in the
/// `initialize` result, so that a model knows how to use the server.
String conversionInstructions(ConversionEngine engine) {
  final database = engine.database;
  final types = database.canonicalTypes.take(8).join(', ');
  return 'ConvertAll converts between ${database.unitCount} units of '
      '${database.canonicalTypes.length} quantities ($types, ...). '
      'Write units the way they are typed in the application: names are case '
      'insensitive, `*` multiplies, `/` divides, `^` raises to a power, and a '
      'compound expression such as `km/hr`, `kg*m/s^2` or `ft*lbf/hr` is '
      'allowed. The value argument accepts a calculation (`1/8`, `3*4+1`). '
      'Non-linear units (C, F, gas mark, liter per 100 km, screw size) can '
      'only be converted on their own. Call find_compatible_units before '
      'convert_value when the target unit is not obvious, so that both units '
      'measure the same quantity. Beware of the single letter units: `h` is '
      'the henry (inductance), not the hour, so a speed is written `km/hr` or '
      '`km/hour` and not `km/h`; `l` is the liter.';
}

/// `convert_value`: the main tool.
McpTool _convertValueTool(ConversionEngine engine) {
  return McpTool(
    name: 'convert_value',
    title: 'Convert a value between units',
    description:
        'Convert a number from one unit to another with the ConvertAll unit '
        'database. Use it for any unit question, including currencies-free '
        'physics, cooking, data and astronomy units. '
        '`value` accepts a plain number or a calculation ("1/8", "3*4+1", '
        '"1e6"). `from` and `to` accept simple units ("mile"), abbreviated '
        'ones ("km"), multi-word names ("light year", "fluid ounce") and '
        'compound expressions ("km/hr", "kg*m/s^2", "N*m", "m^2", "s^-1"). '
        'A non-linear unit (C, F, K is linear, gas mark, liter per 100 km, '
        'screw size) can only be converted on its own. Note that `h` is the '
        'henry (inductance) and not the hour: write `km/hr` or `km/hour` for '
        'a speed. On failure the result explains what to fix and names close '
        'matches; the units can be listed with find_compatible_units or '
        'search_units.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'value': {
          'type': ['string', 'number'],
          'minLength': 1,
          'description':
              'Value to convert: a number ("12", "-3.5", "1e6") or a '
              'calculation ("1/8", "3*4+1").',
        },
        'from': {
          'type': 'string',
          'minLength': 1,
          'description': 'Unit to convert from, e.g. "km/hr".',
        },
        'to': {
          'type': 'string',
          'minLength': 1,
          'description': 'Unit to convert to, e.g. "m/s".',
        },
        'notation': {
          'type': 'string',
          'enum': ['short', 'fixed', 'scientific', 'engineering'],
          'description':
              'How the result is written: "short" (default) switches to '
              'scientific notation outside 1e-7..1e+7, "fixed" keeps the '
              'decimals, "scientific" is the 1.5e+3 form, "engineering" uses '
              'powers of 1000.',
        },
        'decimals': {
          'type': 'integer',
          'minimum': 0,
          'maximum': 15,
          'description': 'Number of decimals of the result (default 8).',
        },
        'include_details': {
          'type': 'boolean',
          'default': false,
          'description':
              'Also return the base units the two expressions reduce to, the '
              'multiplier between them, and the quantity each one measures. '
              'Useful to double check that both units belong to the same '
              'quantity.',
        },
      },
      'required': ['value', 'from', 'to'],
      'additionalProperties': false,
    },
    outputSchema: {
      'type': 'object',
      'properties': {
        'result': {
          'type': 'string',
          'description': 'Converted value, formatted for display.',
        },
        'value': {
          'type': 'number',
          'description': 'Converted value as a number.',
        },
        'from': {'type': 'string', 'description': 'Source unit expression.'},
        'to': {'type': 'string', 'description': 'Target unit expression.'},
        'from_reduced': {
          'type': 'string',
          'description': 'Base units of the source expression.',
        },
        'to_reduced': {
          'type': 'string',
          'description': 'Base units of the target expression.',
        },
        'factor': {
          'type': ['number', 'null'],
          'description':
              'Multiplier from one unit to the other, absent (null) when a '
              'non-linear unit is involved.',
        },
        'from_category': {'type': 'string'},
        'to_category': {'type': 'string'},
        'notation': {'type': 'string'},
        'decimals': {'type': 'integer'},
      },
      'required': ['result', 'value', 'from', 'to'],
      'additionalProperties': false,
    },
    annotations: const ToolAnnotations(title: 'Convert a value between units'),
    handler: (arguments) {
      final value = arguments['value'];
      final from = arguments['from'];
      final to = arguments['to'];
      if (value is! String && value is! num) {
        return ToolOutcome.failure(
          '"value" must be a number or a string.',
          errorCode: UnitErrorCode.malformedValue,
        );
      }
      if (from is! String || to is! String) {
        return ToolOutcome.failure(
          '"from" and "to" must be strings.',
          errorCode: UnitErrorCode.invalidUnitExpression,
        );
      }
      final notationName = arguments['notation'];
      NumberNotation? notation;
      if (notationName is String) {
        notation = notationFromName(notationName);
        if (notation == null) {
          return ToolOutcome.failure(
            'Unknown notation "$notationName": use short, fixed, scientific '
            'or engineering.',
            errorCode: UnitErrorCode.malformedValue,
          );
        }
      }
      final decimalsArgument = arguments['decimals'];
      final decimals = decimalsArgument is num ? decimalsArgument.toInt() : null;
      final detailed = arguments['include_details'] == true;
      try {
        final result = engine.convert(
          value: value is num ? '$value' : value as String,
          from: from,
          to: to,
          notation: notation,
          decimals: decimals,
        );
        return ToolOutcome.success(
          _conversionText(result, detailed),
          structured: result.toJson(detailed: detailed),
        );
      } on UnitConversionException catch (error) {
        return _failure(error);
      }
    },
  );
}

/// `list_unit_types`: the list of quantities of the database.
McpTool _listUnitTypesTool(ConversionEngine engine) {
  return McpTool(
    name: 'list_unit_types',
    title: 'List the unit types',
    description:
        'List every quantity of the ConvertAll database (length, mass, '
        'temperature, data, energy, pressure, ...) with the number of units it '
        'contains. Use it to learn the available vocabulary, then search_units '
        'or find_compatible_units to get the unit names themselves.',
    inputSchema: {'type': 'object', 'properties': {}, 'additionalProperties': false},
    outputSchema: {
      'type': 'object',
      'properties': {
        'types': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'type': {'type': 'string', 'description': 'Canonical (English) name.'},
              'type_display': {'type': 'string', 'description': 'Displayed name.'},
              'count': {'type': 'integer', 'description': 'Number of units.'},
            },
            'required': ['type', 'type_display', 'count'],
            'additionalProperties': false,
          },
        },
      },
      'required': ['types'],
      'additionalProperties': false,
    },
    annotations: const ToolAnnotations(title: 'List the unit types'),
    handler: (arguments) {
      final types = engine.database.canonicalTypes.map((type) {
        return {
          'type': type,
          'type_display': engine.database.displayTypeOf(type),
          'count': engine.database.countOfType(type),
        };
      }).toList();
      final buffer = StringBuffer(
        '${types.length} unit types, ${engine.database.unitCount} units:',
      );
      for (final type in types) {
        buffer.write('\n- ${type['type']} (${type['type_display']}): ${type['count']}');
      }
      return ToolOutcome.success(
        buffer.toString(),
        structured: {'types': types},
      );
    },
  );
}

/// `search_units`: find a unit by name or by quantity.
McpTool _searchUnitsTool(ConversionEngine engine) {
  return McpTool(
    name: 'search_units',
    title: 'Search units by name or type',
    description:
        'Search the unit database. `query` matches the beginning of any word '
        'of a unit name ("cel" finds Celsius, "ounce" finds fluid ounce and '
        'ounce troy), and `type` keeps only one quantity (accepts the English '
        'name or the displayed one). An empty query lists the whole database '
        'in alphabetical order, which is useful to discover the names. Use '
        'the exact name returned here in convert_value.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description': 'Text to look for at the beginning of a unit name.',
        },
        'type': {
          'type': 'string',
          'description': 'Quantity to restrict the search to, e.g. "volume".',
        },
        'limit': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 200,
          'default': 25,
          'description': 'Maximum number of units to return.',
        },
      },
      'additionalProperties': false,
    },
    outputSchema: {
      'type': 'object',
      'properties': {
        'count': {'type': 'integer', 'description': 'Number of units returned.'},
        'units': {'type': 'array', 'items': _unitSchema()},
      },
      'required': ['count', 'units'],
      'additionalProperties': false,
    },
    annotations: const ToolAnnotations(title: 'Search units by name or type'),
    handler: (arguments) {
      final queryArgument = arguments['query'];
      final query = queryArgument is String ? queryArgument.trim() : '';
      final typeArgument = arguments['type'];
      final type = typeArgument is String ? typeArgument.trim() : '';
      final limitArgument = arguments['limit'];
      final limit = limitArgument is num ? limitArgument.toInt() : 25;
      var results = type.isEmpty
          ? engine.database.partialMatches(query)
          : engine.database.unitsOfType(type);
      if (type.isNotEmpty && query.isNotEmpty) {
        final words = query.toLowerCase().split(RegExp(r'\s+'));
        results = results.where((unit) => unit.isPartialMatch(words)).toList();
      }
      // Alphabetical order: a model reading the list finds a name faster, and
      // the order never depends on the order of the entries in the data file.
      results = List.of(results)
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      final total = results.length;
      if (total > limit) results = results.sublist(0, limit);
      final units = unitListToJson(results);
      final buffer = StringBuffer();
      if (total == 0) {
        buffer.write(
          'No unit matches${query.isEmpty ? '' : ' "$query"'}'
          '${type.isEmpty ? '' : ' in the type "$type"'}. '
          'Try a shorter query, or list_unit_types to see the quantities.',
        );
      } else {
        buffer.write(
          '$total unit${total == 1 ? '' : 's'} match'
          '${query.isEmpty ? '' : ' "$query"'}'
          '${type.isEmpty ? '' : ' in the type "$type"'}'
          '${total > units.length ? ', showing the first ${units.length}' : ''}:',
        );
        for (final unit in results) {
          buffer.write('\n- ${unit.label} [${unit.displayType}]');
          if (unit.isNonLinear) buffer.write(' (non-linear)');
        }
      }
      return ToolOutcome.success(
        buffer.toString(),
        structured: {'count': total, 'units': units},
      );
    },
  );
}

/// `get_unit_info`: everything about one unit.
McpTool _getUnitInfoTool(ConversionEngine engine) {
  return McpTool(
    name: 'get_unit_info',
    title: 'Describe a unit',
    description:
        'Describe one unit: its quantity, its equivalent, the base units it '
        'reduces to, its multiplier, whether it needs an equation or a table '
        '(Celsius, gas mark, ...), and the units it can be converted with. Use '
        'it when a unit name is ambiguous ("ton", "ounce", "cal") or when a '
        'conversion was refused for an incompatible quantity.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'unit': {
          'type': 'string',
          'minLength': 1,
          'description': 'Unit name, e.g. "cal".',
        },
        'compatible_limit': {
          'type': 'integer',
          'minimum': 0,
          'maximum': 200,
          'default': 15,
          'description':
              'Number of compatible units to include (0 lists none of them).',
        },
      },
      'required': ['unit'],
      'additionalProperties': false,
    },
    outputSchema: {
      'type': 'object',
      'properties': {
        'unit': {'type': 'string'},
        'type': {'type': 'string'},
        'type_display': {'type': 'string'},
        'equivalent': {'type': 'string'},
        'factor': {
          'type': 'number',
          'description': 'Multiplier to the base units.',
        },
        'base_units': {'type': 'string', 'description': 'Reduced base units.'},
        'non_linear': {'type': 'boolean'},
        'base_unit': {'type': 'boolean'},
        'unabbrev': {'type': 'string'},
        'comment': {'type': 'string'},
        'from_equation': {
          'type': 'string',
          'description': 'Equation or table used to convert from the unit.',
        },
        'to_equation': {
          'type': 'string',
          'description': 'Equation used to convert to the unit.',
        },
        'compatible_unit_count': {'type': 'integer'},
        'compatible_units': {'type': 'array', 'items': {'type': 'string'}},
      },
      'required': [
        'unit',
        'type',
        'type_display',
        'equivalent',
        'factor',
        'base_units',
        'non_linear',
        'base_unit',
      ],
      'additionalProperties': false,
    },
    annotations: const ToolAnnotations(title: 'Describe a unit'),
    handler: (arguments) {
      final unit = arguments['unit'];
      if (unit is! String) {
        return ToolOutcome.failure(
          '"unit" must be a string.',
          errorCode: UnitErrorCode.unknownUnit,
        );
      }
      final limitArgument = arguments['compatible_limit'];
      final limit = limitArgument is num ? limitArgument.toInt() : 15;
      try {
        final details = engine.describeUnit(unit);
        final structured = details.toJson(compatibleLimit: limit);
        final buffer = StringBuffer(details.unit.label);
        buffer.write(
          ' — ${details.unit.displayType}'
          '${details.unit.isNonLinear ? ', non-linear' : ''}',
        );
        buffer.write('\nDefined as: ${details.unit.equiv}');
        buffer.write(
          '\nBase units: ${details.reduced} '
          '(multiplier ${ConversionEngine.formatValue(details.factor)})',
        );
        if (details.unit.comment.isNotEmpty) {
          buffer.write('\nComment: ${details.unit.comment}');
        }
        final names = details.compatible
            .take(limit < 0 ? 0 : limit)
            .map((record) => record.name)
            .join(', ');
        buffer.write('\nCompatible with ${details.compatible.length} units');
        if (names.isNotEmpty) buffer.write(': $names');
        return ToolOutcome.success(buffer.toString(), structured: structured);
      } on UnitConversionException catch (error) {
        return _failure(error);
      }
    },
  );
}

/// `find_compatible_units`: what a unit can be converted to.
McpTool _findCompatibleUnitsTool(ConversionEngine engine) {
  return McpTool(
    name: 'find_compatible_units',
    title: 'List the units compatible with a unit',
    description:
        'List every unit that can be converted with the given one, that is '
        'every unit of the same quantity. Accepts a compound expression '
        '("km/hr" lists mph, knot, m/s, ...). Call it before convert_value when '
        'the target unit is not certain: it prevents the "these units do not '
        'measure the same quantity" failure, and it answers questions such as '
        '"what can I convert litres to?".',
    inputSchema: {
      'type': 'object',
      'properties': {
        'unit': {
          'type': 'string',
          'minLength': 1,
          'description': 'Unit or expression, e.g. "km/hr" or "liter".',
        },
        'limit': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 500,
          'default': 50,
          'description': 'Maximum number of units to return.',
        },
      },
      'required': ['unit'],
      'additionalProperties': false,
    },
    outputSchema: {
      'type': 'object',
      'properties': {
        'unit': {'type': 'string', 'description': 'The unit as it was given.'},
        'category': {
          'type': 'string',
          'description': 'Quantity measured, or the reduced base units.',
        },
        'count': {'type': 'integer', 'description': 'Number of compatible units.'},
        'units': {'type': 'array', 'items': _unitSchema()},
      },
      'required': ['unit', 'category', 'count', 'units'],
      'additionalProperties': false,
    },
    annotations: const ToolAnnotations(title: 'List compatible units'),
    handler: (arguments) {
      final unit = arguments['unit'];
      if (unit is! String) {
        return ToolOutcome.failure(
          '"unit" must be a string.',
          errorCode: UnitErrorCode.unknownUnit,
        );
      }
      final limitArgument = arguments['limit'];
      final limit = limitArgument is num ? limitArgument.toInt() : 50;
      try {
        final all = engine.compatibleUnits(unit, limit: 0);
        final shown = all.length > limit ? all.sublist(0, limit) : all;
        final group = engine.parseGroupOrThrow(unit, label: 'unit');
        final category = engine.describeCategory(group);
        final buffer = StringBuffer(
          '${all.length} units can be converted with "$unit" ($category)'
          '${shown.length < all.length ? ', showing the first ${shown.length}' : ''}:',
        );
        for (final record in shown) {
          buffer.write('\n- ${record.label}');
        }
        return ToolOutcome.success(
          buffer.toString(),
          structured: {
            'unit': unit,
            'category': category,
            'count': all.length,
            'units': unitListToJson(shown),
          },
        );
      } on UnitConversionException catch (error) {
        return _failure(error);
      }
    },
  );
}

/// The text block of a successful conversion.
String _conversionText(UnitConversionResult result, bool detailed) {
  final buffer = StringBuffer(result.summary);
  if (detailed) {
    buffer.write(
      '\nBase units: ${result.fromText} = ${result.fromReduced}; '
      '${result.toText} = ${result.toReduced}',
    );
    final factor = result.factor;
    if (factor != null) {
      final formatted = ConversionEngine.formatValue(
        factor,
        notation: result.notation,
        decimals: result.decimals,
      );
      buffer.write('\nMultiplier: 1 ${result.fromText} = $formatted ${result.toText}');
    }
    buffer.write(
      '\nQuantity: ${result.fromCategory} -> ${result.toCategory}',
    );
  }
  return buffer.toString();
}

/// Turn a core exception into a failed tool outcome.
ToolOutcome _failure(UnitConversionException error) => ToolOutcome.failure(
  error.message,
  errorCode: error.code,
  suggestions: error.suggestions,
);
