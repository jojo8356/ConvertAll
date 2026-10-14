// convertall_mcp.dart, the Model Context Protocol server of ConvertAll.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2025, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// This entry point only starts the MCP server on stdin/stdout, which is what a
// language model client needs in its configuration file:
//
//   {
//     "command": "dart",
//     "args": ["run", "/path/to/ConvertAll/bin/convertall_mcp.dart"]
//   }
//
// `convertall mcp` does the same thing from the command line tool.  With
// `dart compile exe bin/convertall_mcp.dart -o convertall-mcp`, the server
// becomes a standalone program that needs no Dart SDK at all — remember to ship
// `assets/units.json` next to it, or to point at it with --units-file.
//
// See `docs/MCP.md` for the documentation.

import 'dart:io' show exit, stderr, stdout;

import 'package:args/args.dart';

import 'package:convertall/cli/database_locator.dart';
import 'package:convertall/core/app_info.dart';
import 'package:convertall/core/conversion_engine.dart';
import 'package:convertall/core/unit_exceptions.dart';
import 'package:convertall/mcp/mcp_protocol.dart';
import 'package:convertall/mcp/mcp_server.dart';
import 'package:convertall/mcp/mcp_stdio.dart';

Future<void> main(List<String> arguments) async {
  final status = await _run(arguments);
  await stdout.flush();
  exit(status);
}

Future<int> _run(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'units-file',
      help: 'Path of assets/units.json (default: searched around the program).',
    )
    ..addOption(
      'language',
      abbr: 'l',
      help: 'Language of the unit type names: en (default), fr, or auto.',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Trace the protocol exchanges on stderr.',
    )
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addFlag('version', negatable: false);
  ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln('convertall-mcp: ${error.message}');
    stderr.writeln('Run `convertall_mcp --help` for the usage.');
    return 2;
  }
  if (results.flag('help')) {
    stdout.writeln(_usage(parser));
    return 0;
  }
  if (results.flag('version')) {
    stdout.writeln(convertAllVersion);
    return 0;
  }
  final verbose = results.flag('verbose');
  try {
    final database = loadDatabase(
      unitsFile: results.option('units-file'),
      language: results.option('language'),
    );
    final engine = ConversionEngine(database);
    final server = McpServer(
      engine: engine,
      serverVersion: convertAllVersion,
      logger: verbose
          ? (message) => stderr.writeln('[convertall-mcp] $message')
          : null,
    );
    if (verbose) {
      stderr.writeln(
        '[convertall-mcp] ready: ${database.unitCount} units, protocol '
        'revision $modernProtocolVersion (legacy handshake accepted)',
      );
    }
    installTerminationHandlers(verbose: verbose);
    return await runStdioMcpServer(server, verbose: verbose);
  } on UnitDataException catch (error) {
    stderr.writeln('convertall-mcp: $error');
    return 3;
  }
}

String _usage(ArgParser parser) {
  return 'convertall_mcp $convertAllVersion — Model Context Protocol server\n'
      '\n'
      'Serves the unit conversion database of ConvertAll over stdin/stdout,\n'
      'for a language model client.  Protocol revision $modernProtocolVersion,\n'
      'with the legacy "initialize" handshake accepted.\n'
      '\n'
      'Options:\n'
      '${parser.usage}\n';
}
