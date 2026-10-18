// cli_app.dart, the command line interface of ConvertAll.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// The interface is the one of the ConvertAll Python implementation
// (`source/cmdline.py`), extended with the commands of the specification
// (`doc/CLI_RUST_CAHIER_DES_CHARGES.md`) and with a logging layer:
//
//    convertall 1 in cm                 1 in = 2.54 cm
//    convertall -q -f -d 4 1 in cm      1 in = 2.5400 cm
//    convertall -q -- -40 C F           -40 C = -40 F
//    convertall -t                      units.json: 626 units
//                                       All units pass tests
//    convertall --json 1 in cm          {"value": "2.54", "exact": true, ...}
//    convertall --verbose 1 in cm       (the same result, plus a trace on
//                                       stderr: catalogue, request, factors,
//                                       result, duration)
//    convertall units cel               search the catalogue
//    convertall info cal                describe one unit
//    convertall check --all             validate every catalogue
//    convertall doctor                  version, runtime and catalogue
//    convertall -i                      interactive mode
//    convertall mcp                     Model Context Protocol server
//
// The commands share their implementations with the MCP server
// (`lib/mcp/mcp_tools.dart`), so the command line and a connected language
// model always answer the same thing.
//
// Exit status (see [CliStatus]): 0 success, 1 conversion or data error,
// 2 usage error, 3 catalogue error, 130 interrupted.

import 'dart:convert' show json;
import 'dart:io' show IOSink, Platform, stderr, stdout;

import 'package:args/args.dart';

import '../core/app_info.dart';
import '../core/conversion_engine.dart';
import '../core/logging.dart';
import '../core/number_notation.dart';
import '../core/unit_database.dart';
import '../core/unit_exceptions.dart';
import '../core/unit_json.dart';
import '../mcp/mcp_protocol.dart'
    show legacyProtocolVersions, modernProtocolVersion;
import '../mcp/mcp_server.dart';
import '../mcp/mcp_stdio.dart';
import '../mcp/mcp_tools.dart';
import 'catalog_check.dart';
import 'database_locator.dart';
import 'options.dart';
import 'repl.dart';

export 'options.dart' show CliStatus;

/// The logger of the command line itself.
final _cliLog = loggerFor('cli');

/// The version of the JSON documents printed by `--json`.
const cliJsonSchemaVersion = 1;

/// What `doctor` prints when the catalogue was not read from a file (a test
/// builds its database in memory).
const embeddedCatalogue = 'assets/units.json (embedded)';

/// Run the command line tool.  Returns the exit status.
///
/// [out] and [err] default to the process streams; a test can pass its own
/// sinks, and [readLine] its own input for the interactive mode.
Future<int> runConvertAllCli(
  List<String> arguments, {
  IOSink? out,
  IOSink? err,
  String? Function()? readLine,
}) async {
  final output = out ?? stdout;
  final errors = err ?? stderr;
  final parser = buildCliParser();
  ArgResults results;
  try {
    results = parser.parse(normalizeArguments(arguments));
  } on FormatException catch (error) {
    errors.writeln('convertall: ${error.message}');
    errors.writeln();
    errors.writeln(cliUsage(parser));
    return CliStatus.usage;
  }
  final options = CliOptions(results);
  final command = results.command;
  final commandName = command?.name;

  // `--help` and `--version` come first, for the whole line and for a command:
  // they must answer without reading the unit catalogue (the Python test suite
  // checks exactly that), and they are the only two options that do not go
  // through the logging configuration.
  if (options.flag('help')) {
    if (commandName != null && commandName != 'help') {
      output.writeln(
        commandUsage(commandName, parser.commands[commandName]!),
      );
    } else if (command != null && command.rest.isNotEmpty) {
      final name = command.rest.first;
      final commandParser = parser.commands[name];
      output.writeln(
        commandParser == null
            ? cliUsage(parser)
            : commandUsage(name, commandParser),
      );
    } else {
      output.writeln(cliUsage(parser));
    }
    return CliStatus.ok;
  }
  if (options.flag('version')) {
    output.writeln('ConvertAll $convertAllVersion (Dart)');
    return CliStatus.ok;
  }

  // A command line program configures its logging once per run: the sinks of
  // a previous call in the same process (a test, the MCP server hosting the
  // tool) must not capture the records of this one.
  Logging.clearSinks();
  // `--quiet` keeps the result on stdout and lowers the traces to the errors:
  // a script reads a clean stdout and still sees what went wrong.  The order of
  // the decision is the documented one: --log-level, then --verbose, then
  // --quiet, then the environment, then the warning default.
  final logLevel = Logging.configureFromOptions(
    quiet: options.flag('quiet'),
    verbose: options.flag('verbose'),
    explicitLevel: options.option('log-level'),
    logFile: options.option('log-file'),
    json: options.option('log-format') == 'json',
    errorSink: errors,
  );
  _cliLog.debug(
    'convertall $convertAllVersion started with: ${arguments.join(' ')}',
  );
  _cliLog.debug('log level: ${logLevel.label}, results: stdout, logs: stderr');
  if (_cliLog.isEnabled(LogLevel.trace)) {
    // The whole configuration, defaults included: the trace answers "what did
    // the parser actually see?" without a debugger.
    for (final name in parser.options.keys) {
      _cliLog.trace('option $name = ${results[name]}');
    }
    final commandResults = results.command;
    final commandParser =
        commandResults == null ? null : parser.commands[commandResults.name];
    if (commandResults != null && commandParser != null) {
      for (final name in commandParser.options.keys) {
        _cliLog.trace('option ${commandResults.name}.$name = '
            '${commandResults[name]}');
      }
    }
  }

  final watch = Stopwatch()..start();
  // Everything that follows works on the catalogue and reports its failures
  // the same way: a refused conversion on stderr with status 1, a broken
  // catalogue with status 3, an unexpected failure with status 1 and a
  // `critical` record (it is a bug, and it must leave a trace).
  try {
    if (options.flag('runtime-info')) {
      final context = _openCatalogue(options, errors);
      if (context == null) return CliStatus.catalog;
      return _doctorCommand(
        context,
        options,
        output,
        errors,
        forceJson: true,
      );
    }
    final database = _loadCatalogue(options, errors);
    if (database == null) return CliStatus.catalog;
    final engine = ConversionEngine(
      database,
      pythonCompat: options.flag('python-compat'),
    );
    final frontEnd = _ToolFrontEnd(engine);

    // `-t`, `--test` and `--test-all` come first: they replace any command, as
    // they do in the Python tool.
    if (options.flag('test') || options.flag('test-all')) {
      return _checkCommand(
        database,
        all: options.flag('test-all'),
        asJson: options.flag('json'),
        output: output,
      );
    }
    switch (commandName) {
      case 'convert':
        return _convertCommand(frontEnd, command!.rest, options, output, errors);
      case 'units':
        return _unitsCommand(frontEnd, command!, options, output, errors);
      case 'types':
        return _typesCommand(frontEnd, command!, options, output, errors);
      case 'info':
        return _infoCommand(frontEnd, engine, command!, options, output, errors);
      case 'compatible':
        return _compatibleCommand(frontEnd, command!, options, output, errors);
      case 'check':
        return _checkCommand(
          database,
          all: options.flagOf('all', command!) || options.flag('test-all'),
          asJson: options.flag('json'),
          output: output,
        );
      case 'doctor':
        return _doctorCommand(
          _Catalogue(database, engine, frontEnd),
          options,
          output,
          errors,
        );
      case 'repl':
        return _replCommand(engine, options, output, errors, readLine);
      case 'mcp':
        return await _mcpCommand(engine, options, errors);
      case 'version':
        return _versionCommand(database, options, output);
      case 'help':
        final name = command!.rest.isEmpty ? null : command.rest.first;
        final commandParser = name == null ? null : parser.commands[name];
        if (name == null || commandParser == null) {
          output.writeln(cliUsage(parser));
        } else {
          output.writeln(commandUsage(name, commandParser));
        }
        return CliStatus.ok;
      case null:
        // No command: `-i` opens the interactive mode, anything else is the
        // positional form of the Python tool (`convertall 1 in cm`), which is
        // why the conversion options live on the root parser too.
        if (options.flag('interactive')) {
          return _replCommand(engine, options, output, errors, readLine);
        }
        return _convertCommand(frontEnd, results.rest, options, output, errors);
      default:
        errors.writeln('convertall: unknown command "${command!.name}".');
        errors.writeln();
        errors.writeln(cliUsage(parser));
        return CliStatus.usage;
    }
  } on UnitDataException catch (error) {
    _cliLog.error('the unit data could not be used', error: error);
    errors.writeln('Error in unit data - $error');
    return CliStatus.catalog;
  } on UnitConversionException catch (error) {
    return _reportFailure(error, options, output, errors);
  } on FormatException catch (error) {
    _cliLog.error('a value could not be read', error: error);
    errors.writeln('convertall: ${error.message}');
    return CliStatus.failed;
  } catch (error, stackTrace) {
    _cliLog.critical('unexpected failure', error: error, stackTrace: stackTrace);
    errors.writeln('convertall: unexpected failure: $error');
    return CliStatus.failed;
  } finally {
    _cliLog.debug('finished in ${watch.elapsedMilliseconds} ms');
    await Logging.flush();
  }
}

/// The catalogue, the engine and the tools, opened once per call.
class _Catalogue {
  _Catalogue(this.database, this.engine, this.tools);

  final UnitDatabase database;
  final ConversionEngine engine;
  final _ToolFrontEnd tools;

  Map<String, Object?> get catalogJson => {
    if (database.sourcePath != null) 'file': database.sourcePath,
    if (database.sourceSha256 != null) 'sha256': database.sourceSha256,
    'units': database.unitCount,
    'quantities': database.canonicalTypes.length,
  };

  void addProvenance(Map<String, Object?> json) {
    json['schema_version'] = cliJsonSchemaVersion;
    json['catalog'] = catalogJson;
    json['tool'] = {'name': 'convertall', 'version': convertAllVersion};
  }
}

/// Read the unit catalogue, reporting a readable failure on stderr.
UnitDatabase? _loadCatalogue(CliOptions options, IOSink errors) {
  final requested = options.option('language');
  final language = resolveLanguage(requested);
  if (requested != null &&
      requested != 'auto' &&
      !requested.toLowerCase().startsWith(language)) {
    _cliLog.warning(
      'no translation for "$requested": the English unit names are used',
    );
  }
  try {
    final database = loadDatabase(
      unitsFile: options.option('units-file'),
      language: language,
    );
    _cliLog.info(
      'catalogue ${database.sourcePath} (${database.unitCount} units, '
      'sha256 ${database.sourceSha256}), language $language',
    );
    return database;
  } on UnitDataException catch (error) {
    _cliLog.error('the unit data could not be loaded', error: error);
    errors.writeln('Error in unit data - $error');
    return null;
  }
}

/// The context of the running command, or `null` when the catalogue failed.
_Catalogue? _openCatalogue(CliOptions options, IOSink errors) {
  final database = _loadCatalogue(options, errors);
  if (database == null) return null;
  final engine = ConversionEngine(database);
  return _Catalogue(database, engine, _ToolFrontEnd(engine));
}

/// The value of `--decimals`, checked like the Python tool does (0 to 12).
int? _readDecimals(CliOptions options, IOSink errors) {
  final text = options.option('decimals');
  if (text == null) return null;
  final value = int.tryParse(text);
  if (value == null || value < 0 || value > maxDecimals) {
    errors.writeln('Decimals must be an integer from 0 to $maxDecimals.');
    return null;
  }
  return value;
}

/// The notation asked for by `-f`, `-s`, `-e` or `-n`, or `null` for the
/// default one.
NumberNotation? _readNotation(CliOptions options, IOSink errors) {
  if (options.flag('fixed-decimals')) return NumberNotation.fixed;
  if (options.flag('sci-notation')) return NumberNotation.scientific;
  if (options.flag('eng-notation')) return NumberNotation.engineering;
  final text = options.option('notation');
  if (text == null) return null;
  final notation = notationFromName(text);
  if (notation == null) {
    errors.writeln(
      'Unknown notation "$text": use ${notationNames.join(', ')}.',
    );
  }
  return notation;
}

/// `convertall [convert] VALUE FROM TO`.
///
/// The first argument is read as the value only when it is a number, exactly
/// as the Python tool does (its `float()` decides): `convertall -q in cm`
/// converts `1.0 in` to `cm` where `convertall -q 1 in cm` converts `1 in`.
/// A calculation (`1/8`, `3*4+1`) is accepted as well, which is the addition
/// of the specification, and `nan` / `inf` are read here so that the answer is
/// "Number must be finite", as in Python.
int _convertCommand(
  _ToolFrontEnd frontEnd,
  List<String> rest,
  CliOptions options,
  IOSink output,
  IOSink errors,
) {
  if (rest.length > 3) {
    errors.writeln(
      'convertall: too many arguments for a conversion: a value, a unit to '
      'convert from and a unit to convert to.',
    );
    errors.writeln();
    errors.writeln(
      commandUsage('convert', buildCliParser().commands['convert']!),
    );
    return CliStatus.usage;
  }
  var value = '1.0';
  var units = rest;
  if (rest.isNotEmpty && isValueArgument(rest.first)) {
    value = rest.first;
    units = rest.sublist(1);
  }
  if (units.length < 2) {
    if (options.flag('quiet')) {
      // The historical behaviour: `-q` without a unit does not prompt, it
      // fails with the same message and the same status as the Python tool.
      errors.writeln(
        units.isEmpty
            ? 'A valid from unit is required'
            : 'A valid to unit is required',
      );
      return CliStatus.failed;
    }
    if (rest.isEmpty) {
      errors.writeln(
        'convertall: give a value and two units, e.g. convertall 1 in cm.',
      );
    } else {
      errors.writeln(
        'convertall: a conversion needs the value, the unit to convert from '
        'and the unit to convert to.',
      );
      errors.writeln(
        '  example: convertall ${rest.join(' ')}${units.length < 2 ? ' cm' : ''}',
      );
    }
    errors.writeln('  or run `convertall -i` for the interactive mode');
    return CliStatus.usage;
  }
  final decimals = _readDecimals(options, errors);
  if (options.option('decimals') != null && decimals == null) {
    return CliStatus.usage;
  }
  final notation = _readNotation(options, errors);
  if (options.option('notation') != null && notation == null) {
    return CliStatus.usage;
  }
  final detailed = options.flag('details');
  _cliLog.debug('converting $value from "${units[0]}" to "${units[1]}"');
  final arguments = <String, Object?>{
    'value': value,
    'from': units[0],
    'to': units[1],
    'python_compat': options.flag('python-compat'),
    'include_details': detailed || options.flag('json'),
  };
  if (notation != null) arguments['notation'] = notationName(notation);
  if (decimals != null) arguments['decimals'] = decimals;
  final outcome = frontEnd.call('convert_value', arguments);
  if (options.flag('json')) {
    return _writeJson(outcome, output, errors, engine: frontEnd.engine);
  }
  if (outcome.isError) {
    return _writeOutcome(outcome, options, output, errors);
  }
  // The historical line, character for character: `1 in = 2.54 cm`.
  final lines = outcome.text.split('\n');
  output.writeln(lines.first);
  if (detailed) {
    for (final line in lines.skip(1)) {
      output.writeln(line);
    }
  }
  _cliLog.info('answer: ${lines.first}');
  return CliStatus.ok;
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
  final type = options.optionOf('type', command);
  final limit = _readLimit(options.optionOf('limit', command), 25, errors);
  if (limit == null) return CliStatus.usage;
  // The tool orders the units by name; `--sort type` groups them by quantity,
  // which the command line does itself (the MCP tool has no such argument).
  final sortByType = options.optionOf('sort', command) == 'type';
  final order = sortByType ? 'type' : 'name';
  _cliLog.debug(
    'searching the catalogue: query "${query.isEmpty ? '*' : query}", '
    'type ${type ?? '*'}, limit $limit, sorted by $order',
  );
  final outcome = frontEnd.call('search_units', {
    if (query.isNotEmpty) 'query': query,
    if (type != null && type.isNotEmpty) 'type': type,
    'limit': limit,
  });
  if (options.flag('json')) return _writeJson(outcome, output, errors);
  if (!outcome.isError) {
    final units = outcome.structured?['units'];
    if (units is List) {
      final listed = units.cast<Map<String, Object?>>();
      if (sortByType) {
        listed.sort(
          (a, b) => '${a['type_display']} ${a['name']}'
              .compareTo('${b['type_display']} ${b['name']}'),
        );
      }
      _cliLog.debug('${units.length} unit(s) listed');
      output.writeln(_unitTable(listed));
      return CliStatus.ok;
    }
  }
  return _writeOutcome(outcome, options, output, errors);
}

/// `convertall types`.
int _typesCommand(
  _ToolFrontEnd frontEnd,
  ArgResults command,
  CliOptions options,
  IOSink output,
  IOSink errors,
) {
  final outcome = frontEnd.call('list_unit_types', const {});
  if (options.flag('json')) return _writeJson(outcome, output, errors);
  if (outcome.isError) {
    return _writeOutcome(outcome, options, output, errors);
  }
  final types = outcome.structured?['types'];
  if (types is! List) return _writeOutcome(outcome, options, output, errors);
  final entries = types.cast<Map<String, Object?>>();
  if (options.flagOf('count', command)) {
    output.writeln('${entries.length} quantities');
    return CliStatus.ok;
  }
  final buffer = StringBuffer();
  for (final entry in entries) {
    final name = '${entry['type']}';
    final display = '${entry['type_display']}';
    final label = name == display ? name : '$name ($display)';
    buffer.writeln('${label.padRight(34)}${entry['count']}');
  }
  output.write(buffer);
  return CliStatus.ok;
}

/// `convertall info UNIT`.
int _infoCommand(
  _ToolFrontEnd frontEnd,
  ConversionEngine engine,
  ArgResults command,
  CliOptions options,
  IOSink output,
  IOSink errors,
) {
  if (command.rest.isEmpty) {
    errors.writeln(
      'convertall: `info` needs a unit name, e.g. convertall info cal.',
    );
    return CliStatus.usage;
  }
  final limit = _readLimit(
    options.optionOf('compatible-limit', command),
    15,
    errors,
    minimum: 0,
    option: '--compatible-limit',
  );
  if (limit == null) return CliStatus.usage;
  final started = Stopwatch()..start();
  final outcome = frontEnd.call('get_unit_info', {
    'unit': command.rest.join(' '),
    'compatible_limit': limit,
  });
  // `info` shows every field the database knows, in the order a reader wants
  // them (the JSON keeps the same names).
  if (options.flag('json')) {
    return _writeJson(outcome, output, errors, engine: engine);
  }
  if (outcome.isError) {
    return _writeOutcome(outcome, options, output, errors);
  }
  // The `info` command shows the details of the unit, not only its name: the
  // same fields as the JSON, in the order a reader wants them.
  final details = outcome.structured;
  if (details == null) return _writeOutcome(outcome, options, output, errors);
  output.writeln(_unitInfoText(details));
  _cliLog.debug('unit described in ${started.elapsedMilliseconds} ms');
  return CliStatus.ok;
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
  final limit = _readLimit(options.optionOf('limit', command), 50, errors);
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

/// `convertall check [--all]`, `-t`, `--test`, `--test-all`: validate the
/// catalogues (the equivalent of the Python `unitDataTest`).
int _checkCommand(
  UnitDatabase database, {
  required bool all,
  required bool asJson,
  required IOSink output,
}) {
  final reports = all
      ? checkEveryCatalogue(database.sourcePath)
      : [checkCatalogue(database.sourcePath, database: database)];
  final failed = reports.where((report) => !report.isValid).toList();
  if (asJson) {
    output.writeln(
      json.encode({
        'schema_version': cliJsonSchemaVersion,
        'ok': failed.isEmpty,
        'catalogs': reports.map((report) => report.toJson()).toList(),
        'tool': {'name': 'convertall', 'version': convertAllVersion},
      }),
    );
    return failed.isEmpty ? CliStatus.ok : CliStatus.catalog;
  }
  final buffer = StringBuffer();
  for (final report in reports) {
    buffer.writeln('${report.name}: ${report.unitCount} units');
    if (report.isValid) {
      buffer.writeln('All units pass tests');
      continue;
    }
    for (final problem in report.problems) {
      buffer
        ..writeln(problem.message)
        ..writeln('   Impacts:  ${problem.units.join(', ')}')
        ..writeln();
    }
  }
  output.write(buffer.toString());
  if (failed.isEmpty) {
    _cliLog.info(
      '${reports.length} catalogue(s) validated, all units pass tests',
    );
    return CliStatus.ok;
  }
  _cliLog.error('${failed.length} catalogue(s) failed the tests');
  return CliStatus.catalog;
}

/// `convertall doctor`, `--runtime-info`: what the tool is and what it read.
int _doctorCommand(
  _Catalogue catalogue,
  CliOptions options,
  IOSink output,
  IOSink errors, {
  bool forceJson = false,
}) {
  final database = catalogue.database;
  final versions = [modernProtocolVersion, ...legacyProtocolVersions];
  // `doctor` reports the display settings, so they are checked here too: an
  // unusable value is a usage error, not a silently ignored option.
  final notation = _readNotation(options, errors);
  if (options.option('notation') != null && notation == null) {
    return CliStatus.usage;
  }
  final decimals = _readDecimals(options, errors);
  if (options.option('decimals') != null && decimals == null) {
    return CliStatus.usage;
  }
  final info = <String, Object?>{
    'application': 'ConvertAll',
    'version': convertAllVersion,
    'runtime': 'Dart',
    'dart_version': Platform.version,
    'operating_system': Platform.operatingSystem,
    'operating_system_version': Platform.operatingSystemVersion,
    'locale': Platform.localeName,
    'language': resolveLanguage(options.option('language')),
    'units': database.unitCount,
    'unit_types': database.canonicalTypes.length,
    'catalog': catalogue.catalogJson,
    'notation': notationName(notation ?? NumberNotation.short),
    'decimals': decimals ?? 8,
    'log_level': Logging.level.label,
    'mcp_protocol_versions': versions,
    'website': convertAllWebsite,
  };
  catalogue.addProvenance(info);
  if (forceJson || options.flag('json')) {
    output.writeln(json.encode(info));
    return CliStatus.ok;
  }
  final buffer = StringBuffer()
    ..writeln(
      'ConvertAll ${info['version']} (Dart '
      '${Platform.version.split(' ').first})',
    )
    ..writeln('Website:      ${info['website']}')
    ..writeln(
      'Units:        ${info['units']} in ${info['unit_types']} quantities',
    )
    ..writeln('Catalogue:    ${database.sourcePath ?? embeddedCatalogue}');
  if (database.sourceSha256 != null) {
    buffer.writeln('SHA-256:      ${database.sourceSha256}');
  }
  if (database.typeNamesPath != null) {
    buffer.writeln('Unit names:   ${database.typeNamesPath}');
  }
  buffer
    ..writeln('Language:     ${info['language']}')
    ..writeln('Notation:     ${info['notation']}, ${info['decimals']} decimal(s)')
    ..writeln('MCP:          protocol revisions ${versions.join(', ')}');
  output.write(buffer.toString());
  return CliStatus.ok;
}

/// `convertall repl`, `-i`: the interactive mode of the Python tool.
int _replCommand(
  ConversionEngine engine,
  CliOptions options,
  IOSink output,
  IOSink errors,
  String? Function()? readLine,
) {
  final decimals = _readDecimals(options, errors);
  if (options.option('decimals') != null && decimals == null) {
    return CliStatus.usage;
  }
  final notation = _readNotation(options, errors);
  if (options.option('notation') != null && notation == null) {
    return CliStatus.usage;
  }
  _cliLog.info('interactive mode, enter an empty line to leave');
  return runRepl(
    engine,
    notation: notation,
    decimals: decimals,
    output: output,
    errors: errors,
    readLine: readLine,
  );
}

/// `convertall mcp`: run the MCP server on stdin/stdout.
Future<int> _mcpCommand(
  ConversionEngine engine,
  CliOptions options,
  IOSink errors,
) async {
  final serverLog = loggerFor('mcp.server');
  final server = McpServer(
    engine: engine,
    serverVersion: convertAllVersion,
    logger: serverLog.isEnabled(LogLevel.debug) ? serverLog.debug : null,
  );
  _cliLog.info(
    'MCP server ready: ${engine.database.unitCount} units, protocol revision '
    '$modernProtocolVersion (legacy: ${legacyProtocolVersions.join(', ')}), '
    'language ${resolveLanguage(options.option('language'))}',
  );
  installTerminationHandlers(verbose: _cliLog.isEnabled(LogLevel.debug));
  return runStdioMcpServer(server);
}

/// `convertall version`: the version and what was loaded.
int _versionCommand(UnitDatabase database, CliOptions options, IOSink output) {
  final versions = [modernProtocolVersion, ...legacyProtocolVersions];
  if (options.flag('json')) {
    output.writeln(
      json.encode({
        'schema_version': cliJsonSchemaVersion,
        'ok': true,
        'application': 'ConvertAll',
        'name': 'convertall',
        'version': convertAllVersion,
        'runtime': 'Dart',
        'units': database.unitCount,
        'unit_types': database.canonicalTypes.length,
        'catalog': {
          if (database.sourcePath != null) 'file': database.sourcePath,
          if (database.sourceSha256 != null) 'sha256': database.sourceSha256,
        },
        'mcp_protocol_versions': versions,
        'tool': {'name': 'convertall', 'version': convertAllVersion},
      }),
    );
    return CliStatus.ok;
  }
  output.writeln('ConvertAll $convertAllVersion (Dart)');
  output.writeln(
    '${database.unitCount} units in ${database.canonicalTypes.length} quantities',
  );
  output.writeln('MCP protocol revisions: ${versions.join(', ')}');
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
    _cliLog.warning('the request failed: ${outcome.text}');
    return CliStatus.failed;
  }
  output.writeln(outcome.text);
  return CliStatus.ok;
}

/// Write the JSON answer of a call.
///
/// The members are the ones of the MCP `structuredContent`, plus the
/// provenance a script needs to trace a result back to its catalogue
/// (specification annexe C): `schema_version`, `catalog` and `tool`.
int _writeJson(
  ToolOutcome outcome,
  IOSink output,
  IOSink errors, {
  ConversionEngine? engine,
}) {
  final document = <String, Object?>{'schema_version': cliJsonSchemaVersion};
  if (outcome.isError) {
    document
      ..['ok'] = false
      ..['error'] = outcome.text
      ..['exit_status'] = CliStatus.failed;
    if (outcome.errorCode != null) document['error_code'] = outcome.errorCode;
    if (outcome.suggestions.isNotEmpty) {
      document['suggestions'] = outcome.suggestions;
    }
    _cliLog.warning('the request failed: ${outcome.text}');
    output.writeln(json.encode(document));
    return CliStatus.failed;
  }
  document['ok'] = true;
  final structured = outcome.structured;
  if (structured != null) document.addAll(structured);
  if (engine != null) {
    final database = engine.database;
    document['catalog'] = {
      if (database.sourcePath != null) 'file': database.sourcePath,
      if (database.sourceSha256 != null) 'sha256': database.sourceSha256,
      'units': database.unitCount,
    };
  }
  document['tool'] = {'name': 'convertall', 'version': convertAllVersion};
  output.writeln(json.encode(document));
  return CliStatus.ok;
}

/// The failure reported for a conversion error raised outside a tool.
int _reportFailure(
  UnitConversionException error,
  CliOptions options,
  IOSink output,
  IOSink errors,
) {
  _cliLog.warning('the request failed: ${error.message}');
  if (options.flag('json')) {
    final document = <String, Object?>{
      'schema_version': cliJsonSchemaVersion,
      'exit_status': CliStatus.failed,
      'tool': {'name': 'convertall', 'version': convertAllVersion},
    };
    document.addAll(
      errorToJson(
        error.message,
        code: error.code,
        suggestions: error.suggestions,
      ),
    );
    output.writeln(json.encode(document));
  } else {
    errors.writeln('convertall: ${error.message}');
    if (error.suggestions.isNotEmpty) {
      errors.writeln('  did you mean: ${error.suggestions.join(', ')}?');
    }
    if (error.hint != null) errors.writeln('  hint: ${error.hint}');
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
  final buffer = StringBuffer()
    ..writeln(
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
    if (unit['non_linear'] == true &&
        !details.any((text) => text.toLowerCase().contains('non-linear'))) {
      details.add('non-linear');
    }
    buffer.writeln('$name  $type  ${details.join(', ')}');
  }
  return buffer.toString().trimRight();
}

/// The detailed text of one unit, as `convertall info` shows it.
String _unitInfoText(Map<String, Object?> details) {
  final buffer = StringBuffer();
  final display = '${details['type_display']}';
  final canonical = '${details['type']}';
  buffer.writeln(
    '${details['unit']} — $display${display == canonical ? '' : ' ($canonical)'}',
  );
  final unabbrev = details['unabbrev'];
  if (unabbrev != null) buffer.writeln('  Name:       $unabbrev');
  buffer.writeln('  Equivalent: ${details['equivalent']}');
  final factor = details['factor_exact'] ?? details['factor'];
  if (factor != null) buffer.writeln('  Factor:     $factor');
  buffer.writeln('  Base units: ${details['base_units']}');
  if (details['non_linear'] == true) {
    buffer
      ..writeln('  Non-linear: yes')
      ..writeln('  From:       ${details['from_equation']}');
    if (details['to_equation'] != null) {
      buffer.writeln('  To:         ${details['to_equation']}');
    }
  }
  final comment = details['comment'];
  if (comment != null) buffer.writeln('  Comment:    $comment');
  final compatible = details['compatible_units'];
  if (compatible is List && compatible.isNotEmpty) {
    buffer.writeln(
      '  Converts with ${details['compatible_unit_count']} units: '
      '${compatible.join(', ')}',
    );
  }
  return buffer.toString().trimRight();
}

/// Read a bounded whole number from an option.
int? _readLimit(
  String? text,
  int fallback,
  IOSink errors, {
  int minimum = 1,
  String option = '--limit',
}) {
  if (text == null) return fallback;
  final value = int.tryParse(text);
  if (value == null || value < minimum || value > 500) {
    errors.writeln(
      'convertall: $option expects a whole number between $minimum and 500.',
    );
    return null;
  }
  return value;
}

/// The front-end over the tool handlers shared with the MCP server.
class _ToolFrontEnd {
  _ToolFrontEnd(this.engine)
    : _tools = {for (final tool in buildConversionTools(engine)) tool.name: tool};

  /// The engine behind the tools, so that a caller can report the catalogue
  /// that produced an answer.
  final ConversionEngine engine;
  final Map<String, McpTool> _tools;

  ToolOutcome call(String name, Map<String, Object?> arguments) {
    final tool = _tools[name];
    if (tool == null) {
      throw StateError('The tool "$name" does not exist.');
    }
    final outcome = tool.handler(arguments);
    if (outcome.isError && outcome.structured == null) {
      // The failure is reported by the caller on stderr and by the exit
      // status; the trace keeps the machine readable code.
      _cliLog.trace('tool $name refused: ${outcome.errorCode}');
    }
    return outcome;
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

  /// The value of an option of the command itself, which the parser validates
  /// (a `defaultsTo` value is *not* an answer of the user, so it is ignored).
  String? optionOf(String name, ArgResults command) {
    if (!_wasParsed(command, name)) return null;
    final value = command[name];
    return value is String ? value : null;
  }

  bool _wasParsed(ArgResults results, String name) =>
      results.options.contains(name) && results.wasParsed(name);
}
