// convertall.dart, the command line tool of ConvertAll.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2025, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// The option notation is the one of the ConvertAll Python implementation
// (`source/cmdline.py`), so a script written for it keeps working:
//
//   dart run bin/convertall.dart 1 in cm
//   dart run bin/convertall.dart -q -f -d 4 1 in cm
//   dart run bin/convertall.dart -q -- -40 C F
//   dart run bin/convertall.dart -i            (interactive mode)
//   dart run bin/convertall.dart -t            (validate the catalogue)
//   dart run bin/convertall.dart --json 100 km/hr m/s
//   dart run bin/convertall.dart --verbose 1 in cm
//   dart run bin/convertall.dart units --type volume
//   dart run bin/convertall.dart mcp           (the MCP server on stdio)
//
// The tool uses only the Dart core libraries and four pure Dart packages
// (args, decimal, eval_ex, rational): it never imports Flutter, so it runs
// with the Dart SDK alone.  Compile it into a standalone program with:
//   dart compile exe bin/convertall.dart -o convertall
//
// See `docs/CLI.md` and `docs/MCP.md` for the documentation.

import 'dart:io' show exit, stdout;

import 'package:convertall/cli/cli_app.dart';

Future<void> main(List<String> arguments) async {
  final status = await runConvertAllCli(arguments);
  // Flush before exiting: `exit` does not wait for pending output.
  await stdout.flush();
  exit(status);
}
