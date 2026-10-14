// cli_app.dart, the command line interface of ConvertAll.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// The commands (`convert`, `units`, `types`, `info`, `compatible`) are a thin
// front-end over the very same tool handlers as the MCP server
// (`lib/mcp/mcp_tools.dart`), so that the command line and a connected
// language model always answer the same thing.  `convertall mcp` runs the MCP
// server itself on stdin/stdout.
//
// Exit status:
//   0  success, or `--help`
//   1  wrong usage (missing argument, unknown option, unknown command)
//   2  the operation failed (unknown unit, incompatible units, bad value)
//   3  unexpected failure (unreadable unit data, internal error)

import 'dart:convert' show json;
import 'dart:io' show IOSink, stderr, stdout;

import 'package:args/args.dart';

import '../core/app_info.dart';
import '../core/conversion_engine.dart';
import '../core/unit_database.dart';
import '../core/unit_exceptions.dart';
import '../core/unit_json.dart';
import '../mcp/mcp_protocol.dart';
import '../mcp/mcp_server.dart';
import '../mcp/mcp_stdio.dart';
import '../mcp/mcp_tools.dart';
import 'database_locator.dart';

/// The exit statuses documented above.
abstract final class CliStatus {
  static const ok = 0;
  static const usage = 1;
  static const failed = 2;
  static const internal = 3;
}

/// Run the command line tool.  Returns the exit status.
Future<int> runConvertAllCli(
  List<String> arguments, {
  IOSink? out,
  IOSink? err,
}) async {
  final output = out ?? stdout;
  final errors = err ?? stderr;
  final parser = _buildParser();
  ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (error) {
    errors.writeln('convertall: ${error.message}');
    errors.writeln('Run `convertall --help` for the usage.');
    return CliStatus.usage;
  }
  final options = CliOptions(results);
  final command = results.command;
  final globalHelp = options.flagOf('help', results);
  final commandHelp = command != null && options.flagOf('help', command);
  if (globalHelp || commandHelp) {
    if (commandHelp && command != null) {
      output.writeln(_commandUsage(command.name));
    } else {
      output.writeln(_usage(parser));
    }
    return CliStatus.ok;
  }
  if (options.flag('version')) {
    output.writeln(convertAllVersion);
    return CliStatus.ok;
  }
  if (command == null) {
    errors.writeln(_usage(parser));
    return CliStatus.usage;
  }
  final requestedLanguage = options.option('language');
  final language = resolveLanguage(requestedLanguage);
  if (requestedLanguage != null &&
      requestedLanguage != 'auto' &&
      !requestedLanguage.toLowerCase().startsWith(language)) {
    errors.writeln(
      'convertall: no translation for "$requestedLanguage", using English.',
    );
  }
  UnitDatabase database;
  try {
    database = loadDatabase(
      unitsFile: options.option('units-file'),
      language: language,
    );
  } on UnitDataException catch (error) {
    errors.writeln('convertall: $error');
    return CliStatus.internal;
  }
  final engine = ConversionEngine(database);
  final frontEnd = _ToolFrontEnd(buildConversionTools(engine));
  final commandResults = command;
  try {
    switch (commandResults.name) {
      case 'convert':
        return _convertCommand(frontEnd, commandResults, options, output, errors);
      case 'units':
        return _unitsCommand(frontEnd, commandResults, options, output, errors);
      case 'types':
        return _typesCommand(frontEnd, options, output, errors);
      case 'info':
        return _infoCommand(frontEnd, commandResults, options, output, errors);
      case 'compatible':
        return _compatibleCommand(
          frontEnd,
          commandResults,
          options,
          output,
          errors,
        );
      case 'mcp':
        return await _mcpCommand(engine, options, errors);
      case 'version':
        return _versionCommand(database, options, output);
      default:
        errors.writeln('convertall: unknown command "${commandResults.name}".');
        errors.writeln(_usage(parser));
        return CliStatus.usage;
    }
  } on UnitDataException catch (error) {
    errors.writeln('convertall: $error');
    return CliStatus.internal;
  } on UnitConversionException catch (error) {
    return _reportFailure(error, options, output, errors);
  } catch (error) {
    errors.writeln('convertall: unexpected failure: $error');
    return CliStatus.internal;
  }
}

/// `convertall convert VALUE FROM TO`.
int _convertCommand(
  _ToolFrontEnd frontEnd,
  ArgResults command,
  CliOptions options,
  IOSink output,
  IOSink errors,
) {
  final rest = command.rest;
  if (rest.length < 3) {
    errors.writeln(
      'convertall: `convert` needs three arguments: the value, the unit to '
      'convert from and the unit to convert to.',
    );
    errors.writeln('  example: convertall convert 100 km/hr m/s');
    return CliStatus.usage;
  }
  final notation = options.option('notation') ?? 'short';
  final decimalsText = options.option('decimals');
  int? decimals;
  if (decimalsText != null) {
    decimals = int.tryParse(decimalsText);
    if (decimals == null || decimals < 0 || decimals > 15) {
      errors.writeln(
        'convertall: --decimals expects a whole number between 0 and 15.',
      );
      return CliStatus.usage;
    }
  }
  final outcome = frontEnd.call('convert_value', {
    'value': rest[0],
    'from': rest[1],
    'to': rest[2],
    'notation': notation,
    if (decimals != null) 'decimals': decimals,
    'include_details': options.flag('details'),
  });
  return _writeOutcome(outcome, options, output, errors);
}

/// `convertall units [QUERY]`.
int _unitsCommand(
  _ToolFrontEnd frontEnd,
  ArgResults command,
  CliOptions options,
  IOSink output,
  IOSink errors,
) {
  final query = command.rest.join(' ').trim();
  final type = options.option('type');
  final limit = _readLimit(options.option('limit'), 25, errors);
  if (limit == null) return CliStatus.usage;
  final outcome = frontEnd.call('search_units', {
    if (query.isNotEmpty) 'query': query,
    if (type != null && type.isNotEmpty) 'type': type,
    'limit': limit,
  });
  if (options.flag('json')) {
    return _writeJson(outcome, output, errors);
  }
  if (!outcome.isError) {
    final structured = outcome.structured;
    final units = structured?['units'];
    if (units is List) {
      output.writeln(_unitTable(units.cast<Map<String, Object?>>()));
      return CliStatus.ok;
    }
  }
  return _writeOutcome(outcome, options, output, errors);
}

/// `convertall types`.
int _typesCommand(
  _ToolFrontEnd frontEnd,
  CliOptions options,
  IOSink output,
  IOSink errors,
) {
  final outcome = frontEnd.call('list_unit_types', const {});
  if (options.flag('json')) return _writeJson(outcome, output, errors);
  final structured = outcome.structured;
  final types = structured?['types'];
  if (types is List) {
    final buffer = StringBuffer();
    for (final entry in types.cast<Map<String, Object?>>()) {
      final name = '${entry['type']}';
      final display = '${entry['type_display']}';
      final label = name == display ? name : '$name ($display)';
      buffer.writeln('${label.padRight(34)}${entry['count']}');
    }
    output.write(buffer);
    return CliStatus.ok;
  }
  return _writeOutcome(outcome, options, output, errors);
}

/// `convertall info UNIT`.
int _infoCommand(
  _ToolFrontEnd frontEnd,
  ArgResults command,
  CliOptions options,
  IOSink output,
  IOSink errors,
) {
  if (command.rest.isEmpty) {
    errors.writeln('convertall: `info` needs a unit name, e.g. convertall info cal.');
    return CliStatus.usage;
  }
  final limit = _readLimit(
    options.option('compatible-limit'),
    15,
    errors,
    minimum: 0,
  );
  if (limit == null) return CliStatus.usage;
  final outcome = frontEnd.call('get_unit_info', {
    'unit': command.rest.join(' '),
    'compatible_limit': limit,
  });
  return _writeOutcome(outcome, options, output, errors);
}

/// `convertall compatible UNIT`.
int _compatibleCommand(
  _ToolFrontEnd frontEnd,
  ArgResults command,
  CliOptions options,
  IOSink output,
  IOSink errors,
) {
  if (command.rest.isEmpty) {
    errors.writeln(
      'convertall: `compatible` needs a unit, e.g. convertall compatible km/hr.',
    );
    return CliStatus.usage;
  }
  final limit = _readLimit(options.option('limit'), 50, errors);
  if (limit == null) return CliStatus.usage;
  final outcome = frontEnd.call('find_compatible_units', {
    'unit': command.rest.join(' '),
    'limit': limit,
  });
  if (options.flag('json')) return _writeJson(outcome, output, errors);
  if (!outcome.isError) {
    final structured = outcome.structured;
    final units = structured?['units'];
    if (units is List) {
      output.writeln(
        '${structured?['count']} units measure the same thing as '
        '"${structured?['unit']}" (${structured?['category']}):',
      );
      output.writeln(_unitTable(units.cast<Map<String, Object?>>()));
      return CliStatus.ok;
    }
  }
  return _writeOutcome(outcome, options, output, errors);
}

/// `convertall mcp`: run the MCP server on stdin/stdout.
Future<int> _mcpCommand(
  ConversionEngine engine,
  CliOptions options,
  IOSink errors,
) async {
  final verbose = options.flag('verbose');
  final server = McpServer(
    engine: engine,
    serverVersion: convertAllVersion,
    logger: verbose
        ? (message) => errors.writeln('[convertall-mcp] $message')
        : null,
  );
  if (verbose) {
    errors.writeln(
      '[convertall-mcp] ${engine.database.unitCount} units ready, protocol '
      'revision $modernProtocolVersion (legacy: ${legacyProtocolVersions.join(', ')})',
    );
  }
  installTerminationHandlers(verbose: verbose);
  return runStdioMcpServer(server, verbose: verbose);
}

/// `convertall version`.
int _versionCommand(UnitDatabase database, CliOptions options, IOSink output) {
  final versions = [modernProtocolVersion, ...legacyProtocolVersions].join(', ');
  if (options.flag('json')) {
    output.writeln(
      json.encode({
        'ok': true,
        'name': 'convertall',
        'version': convertAllVersion,
        'units': database.unitCount,
        'unit_types': database.canonicalTypes.length,
        'mcp_protocol_versions': versions.split(', '),
      }),
    );
    return CliStatus.ok;
  }
  output.writeln('convertall $convertAllVersion');
  output.writeln(
    '${database.unitCount} units in ${database.canonicalTypes.length} '
    'quantities',
  );
  output.writeln('MCP protocol revisions: $versions');
  return CliStatus.ok;
}

/// Write the human text of a successful call, or the failure.
int _writeOutcome(
  ToolOutcome outcome,
  CliOptions options,
  IOSink output,
  IOSink errors,
) {
  if (options.flag('json')) return _writeJson(outcome, output, errors);
  if (outcome.isError) {
    errors.writeln('convertall: ${outcome.text}');
    if (outcome.suggestions.isNotEmpty) {
      errors.writeln('  did you mean: ${outcome.suggestions.join(', ')}?');
    }
    return CliStatus.failed;
  }
  output.writeln(outcome.text);
  return CliStatus.ok;
}

/// Write the JSON envelope of a call.
int _writeJson(ToolOutcome outcome, IOSink output, IOSink errors) {
  if (outcome.isError) {
    output.writeln(
      json.encode(
        errorToJson(
          outcome.text,
          code: outcome.errorCode,
          suggestions: outcome.suggestions,
        ),
      ),
    );
    return CliStatus.failed;
  }
  final envelope = <String, Object?>{'ok': true};
  final structured = outcome.structured;
  if (structured != null) envelope.addAll(structured);
  output.writeln(json.encode(envelope));
  return CliStatus.ok;
}

/// The failure reported for a conversion error raised outside a tool.
int _reportFailure(
  UnitConversionException error,
  CliOptions options,
  IOSink output,
  IOSink errors,
) {
  if (options.flag('json')) {
    output.writeln(
      json.encode(
        errorToJson(
          error.message,
          code: error.code,
          suggestions: error.suggestions,
        ),
      ),
    );
  } else {
    errors.writeln('convertall: ${error.toString()}');
  }
  return CliStatus.failed;
}

/// A two column table of units.
String _unitTable(List<Map<String, Object?>> units) {
  if (units.isEmpty) return 'No unit to show.';
  var nameWidth = 4;
  var typeWidth = 4;
  for (final unit in units) {
    final name = '${unit['name']}';
    final type = '${unit['type_display']}';
    if (name.length > nameWidth) nameWidth = name.length;
    if (type.length > typeWidth) typeWidth = type.length;
  }
  if (nameWidth > 32) nameWidth = 32;
  if (typeWidth > 24) typeWidth = 24;
  final buffer = StringBuffer();
  buffer.writeln(
    '${'NAME'.padRight(nameWidth)}  ${'TYPE'.padRight(typeWidth)}  DETAILS',
  );
  for (final unit in units) {
    final name = '${unit['name']}'.padRight(nameWidth);
    final type = '${unit['type_display']}'.padRight(typeWidth);
    final details = <String>[];
    final unabbrev = unit['unabbrev'];
    if (unabbrev is String && unabbrev.isNotEmpty) details.add(unabbrev);
    final comment = unit['comment'];
    if (comment is String && comment.isNotEmpty) details.add(comment);
    // The data already marks some non-linear units in their comment.
    if (unit['non_linear'] == true &&
        !details.any((text) => text.toLowerCase().contains('non-linear'))) {
      details.add('non-linear');
    }
    buffer.writeln('$name  $type  ${details.join(', ')}');
  }
  return buffer.toString().trimRight();
}

int? _readLimit(String? text, int fallback, IOSink errors, {int minimum = 1}) {
  if (text == null) return fallback;
  final value = int.tryParse(text);
  if (value == null || value < minimum || value > 500) {
    errors.writeln(
      'convertall: --limit expects a whole number between $minimum and 500.',
    );
    return null;
  }
  return value;
}

/// The options shared by the tool and its commands.
ArgParser _addCommonOptions(ArgParser parser) {
  parser
    ..addFlag(
      'json',
      negatable: false,
      help: 'Print the result as JSON (errors too, on stdout).',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Trace the MCP exchanges on stderr.',
    )
    ..addOption(
      'language',
      abbr: 'l',
      help: 'Language of the unit type names: en (default), fr, or auto.',
    )
    ..addOption(
      'units-file',
      help: 'Path of assets/units.json (default: searched around the tool).',
    );
  return parser;
}

ArgParser _buildParser() {
  final parser = _addCommonOptions(ArgParser(allowTrailingOptions: true))
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.')
    ..addFlag('version', negatable: false, help: 'Show the version.');
  parser.addCommand(
    'convert',
    _addCommonOptions(ArgParser())
      ..addOption(
        'notation',
        abbr: 'n',
        allowed: ['short', 'fixed', 'scientific', 'engineering'],
        defaultsTo: 'short',
        help: 'How the result is written.',
      )
      ..addOption(
        'decimals',
        abbr: 'd',
        help: 'Number of decimals of the result (0 to 15, default 8).',
      )
      ..addFlag(
        'details',
        negatable: false,
        help: 'Also show the base units, the multiplier and the quantity.',
      )
      ..addFlag('help', abbr: 'h', negatable: false),
  );
  parser.addCommand(
    'units',
    _addCommonOptions(ArgParser())
      ..addOption('type', abbr: 't', help: 'Restrict to one quantity.')
      ..addOption('limit', abbr: 'm', help: 'Maximum number of units (1 to 500).')
      ..addFlag('help', abbr: 'h', negatable: false),
  );
  parser.addCommand(
    'types',
    _addCommonOptions(ArgParser())..addFlag('help', abbr: 'h', negatable: false),
  );
  parser.addCommand(
    'info',
    _addCommonOptions(ArgParser())
      ..addOption(
        'compatible-limit',
        help: 'Number of compatible units to list (0 to 500, default 15).',
      )
      ..addFlag('help', abbr: 'h', negatable: false),
  );
  parser.addCommand(
    'compatible',
    _addCommonOptions(ArgParser())
      ..addOption('limit', abbr: 'm', help: 'Maximum number of units (1 to 500).')
      ..addFlag('help', abbr: 'h', negatable: false),
  );
  parser.addCommand(
    'mcp',
    _addCommonOptions(ArgParser())..addFlag('help', abbr: 'h', negatable: false),
  );
  parser.addCommand(
    'version',
    _addCommonOptions(ArgParser())..addFlag('help', abbr: 'h', negatable: false),
  );
  return parser;
}

String _usage(ArgParser parser) {
  final buffer = StringBuffer()
    ..writeln('convertall $convertAllVersion — unit conversion')
    ..writeln()
    ..writeln('Usage: convertall [global options] <command> [options] [arguments]')
    ..writeln()
    ..writeln('Commands:')
    ..writeln('  convert VALUE FROM TO   convert a value between two units')
    ..writeln('  units [QUERY]           list or search units')
    ..writeln('  types                   list the quantities of the database')
    ..writeln('  info UNIT               describe one unit')
    ..writeln('  compatible UNIT         list the units it can be converted with')
    ..writeln('  mcp                     serve the Model Context Protocol on stdio')
    ..writeln('  version                 show the version')
    ..writeln()
    ..writeln('Examples:')
    ..writeln('  convertall convert 100 km/hr m/s')
    ..writeln('  convertall convert 1/8 cup ml')
    ..writeln('  convertall --json convert 37 C F')
    ..writeln('  convertall units --type volume --limit 10')
    ..writeln('  convertall compatible "light year"')
    ..writeln('  convertall info cal')
    ..writeln()
    ..writeln('Global options:')
    ..writeln(parser.usage)
    ..writeln()
    ..writeln('Units are written with * for multiplication, / for division and ^')
    ..writeln('for exponents: km/hr, kg*m/s^2, m^2, ft*lbf/hr.  The unit data is')
    ..writeln('the same assets/units.json file as the graphical application.');
  return buffer.toString();
}

String _commandUsage(String command) {
  const specificOptions = <String, String>{
    'convert':
        '  -n, --notation    short | fixed | scientific | engineering\n'
        '  -d, --decimals    number of decimals (0 to 15, default 8)\n'
        '      --details     also show the base units and the multiplier',
    'units':
        '  -t, --type        restrict to one quantity, e.g. --type volume\n'
        '  -m, --limit       maximum number of units (default 25)',
    'info': '      --compatible-limit  number of compatible units (default 15)',
    'compatible': '  -m, --limit       maximum number of units (default 50)',
  };
  final buffer = StringBuffer();
  switch (command) {
    case 'convert':
      buffer
        ..writeln('convertall convert VALUE FROM TO [options]')
        ..writeln()
        ..writeln('Convert VALUE from one unit to another.  VALUE accepts a')
        ..writeln('number or a calculation (1/8, 3*4+1, 1e6).')
        ..writeln()
        ..writeln('Examples:')
        ..writeln('  convertall convert 100 km/hr m/s')
        ..writeln('  convertall convert 70 F C --details')
        ..writeln('  convertall --json convert 2.5 acre m^2');
    case 'units':
      buffer
        ..writeln('convertall units [QUERY] [options]')
        ..writeln()
        ..writeln('Search the unit database.  QUERY matches the beginning of any')
        ..writeln('word of a unit name: "cel" finds Celsius.');
    case 'info':
      buffer
        ..writeln('convertall info UNIT [options]')
        ..writeln()
        ..writeln('Describe a unit: quantity, equivalent, base units, multiplier')
        ..writeln('and compatibility.  Use it when a name is ambiguous.');
    case 'compatible':
      buffer
        ..writeln('convertall compatible UNIT [options]')
        ..writeln()
        ..writeln('List the units that can be converted with UNIT, which answers')
        ..writeln('"what can I convert X to?".  Accepts "km/hr".');
    case 'mcp':
      buffer
        ..writeln('convertall mcp [options]')
        ..writeln()
        ..writeln('Serve the Model Context Protocol on stdin/stdout, for a')
        ..writeln('language model client.  Nothing but JSON-RPC messages is')
        ..writeln('written to stdout; traces go to stderr with -v.');
    case 'types':
      buffer.writeln('convertall types [options]');
    case 'version':
      buffer.writeln('convertall version [options]');
  }
  buffer
    ..writeln()
    ..writeln('Common options: --json, -l/--language, --units-file');
  final specific = specificOptions[command];
  if (specific != null) {
    buffer
      ..writeln()
      ..writeln('Options:')
      ..writeln(specific);
  }
  return buffer.toString();
}

/// The front-end over the tool handlers.
class _ToolFrontEnd {
  _ToolFrontEnd(List<McpTool> tools)
    : _tools = {for (final tool in tools) tool.name: tool};

  final Map<String, McpTool> _tools;

  ToolOutcome call(String name, Map<String, Object?> arguments) {
    final tool = _tools[name];
    if (tool == null) {
      throw StateError('The tool "$name" does not exist.');
    }
    return tool.handler(arguments);
  }
}

/// Reads an option from the command, falling back to the global value.
class CliOptions {
  CliOptions(this.global) : command = global.command;

  final ArgResults global;
  final ArgResults? command;

  /// True when the flag was given anywhere (before or after the command).
  bool flag(String name) {
    if (command != null && _wasParsed(command!, name)) {
      return command![name] == true;
    }
    return _wasParsed(global, name) && global[name] == true;
  }

  /// True when the flag was given on the given command results.
  bool flagOf(String name, ArgResults results) =>
      _wasParsed(results, name) && results[name] == true;

  /// The option value, from the command when given there, from the global
  /// options otherwise, or `null` when it was never given.
  String? option(String name) {
    if (command != null && _wasParsed(command!, name)) {
      final value = command![name];
      return value is String ? value : null;
    }
    if (_wasParsed(global, name)) {
      final value = global[name];
      return value is String ? value : null;
    }
    return null;
  }

  bool _wasParsed(ArgResults results, String name) =>
      results.options.contains(name) && results.wasParsed(name);
}
