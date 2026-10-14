// convertall.dart, the command line tool of ConvertAll.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2025, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// Usage:
//   dart run bin/convertall.dart convert 100 km/hr m/s
//   dart run bin/convertall.dart units --type volume
//   dart run bin/convertall.dart mcp          (the MCP server on stdio)
//
// The tool uses only the Dart core libraries and three pure Dart packages
// (args, decimal, eval_ex): it never imports Flutter, so it runs with the Dart
// SDK alone.  Compile it into a standalone program with:
//   dart compile exe bin/convertall.dart -o convertall
//
// See `docs/MCP.md` for the documentation.

import 'dart:io' show exit, stdout;

import 'package:convertall/cli/cli_app.dart';

Future<void> main(List<String> arguments) async {
  final status = await runConvertAllCli(arguments);
  // Flush before exiting: `exit` does not wait for pending output.
  await stdout.flush();
  exit(status);
}
