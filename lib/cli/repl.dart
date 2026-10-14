// repl.dart, the interactive mode of the command line tool.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// The prompts and the answers are the ones of the ConvertAll Python
// implementation (`source/cmdline.py`), which the `-i` option opens:
//
//   Enter from unit -> in
//   Enter to unit -> cm
//   1.0 in = 2.54 cm
//   Enter number, [n]ew, [r]everse or [q]uit -> 2
//   2 in = 5.08 cm
//
// `n` (or `new`) asks for two new units, `r` (or `reverse`) swaps them, `q`
// (or an empty line, or the end of the input) leaves with status 0, and any
// other text is read as the new number.  Nothing is written to a history file:
// the Python tool keeps no state either.

import 'dart:io' show IOSink, stderr, stdin, stdout;

import '../core/conversion_engine.dart';
import '../core/logging.dart';
import '../core/number_notation.dart';
import '../core/unit_exceptions.dart';
import 'options.dart';

/// The logger of the interactive mode.
final _replLog = loggerFor('repl');

/// Run the interactive mode.  Returns the exit status.
///
/// [readLine] reads one line from the user (`stdin.readLineSync` by default);
/// a test passes its own reader, which is how the interaction is verified
/// without a terminal.
int runRepl(
  ConversionEngine engine, {
  NumberNotation? notation,
  int? decimals,
  IOSink? output,
  IOSink? errors,
  String? Function()? readLine,
}) {
  final out = output ?? stdout;
  final err = errors ?? stderr;
  final read = readLine ?? stdin.readLineSync;
  final session = _Session(engine, out, err, read, notation, decimals);

  while (true) {
    final fromText = session.ask('Enter from unit -> ');
    if (fromText == null) return CliStatus.ok;
    if (fromText.isEmpty) return CliStatus.ok;
    final from = session.readUnit(fromText, 'Enter from unit -> ');
    if (from == null) {
      if (session.eof) return CliStatus.ok;
      continue;
    }
    final toText = session.ask('Enter to unit -> ');
    if (toText == null || toText.isEmpty) return CliStatus.ok;
    final to = session.readUnit(toText, 'Enter to unit -> ');
    if (to == null) {
      if (session.eof) return CliStatus.ok;
      continue;
    }
    if (!session.run(from, to)) return CliStatus.ok;
  }
}

/// One interaction: the units chosen, the current number, and the loop of
/// `Enter number, [n]ew, [r]everse or [q]uit -> `.
class _Session {
  _Session(
    this.engine,
    this.output,
    this.errors,
    this.read,
    this.notation,
    this.decimals,
  );

  final ConversionEngine engine;
  final IOSink output;
  final IOSink errors;
  final String? Function() read;
  final NumberNotation? notation;
  final int? decimals;

  /// True when the input ended: the caller leaves with status 0.
  bool eof = false;

  /// Write a prompt and read one line (`null` at the end of the input).
  String? ask(String prompt) {
    output.write(prompt);
    final line = read();
    if (line == null) {
      eof = true;
      _replLog.debug('end of the input, leaving the interactive mode');
      output.writeln();
      return null;
    }
    return line.trim();
  }

  /// Read a unit expression, asking again while it is not usable.
  String? readUnit(String first, String prompt) {
    var text = first;
    while (true) {
      try {
        engine.parseGroupOrThrow(text, label: 'from/to');
        return text;
      } on UnitConversionException catch (error) {
        errors.writeln(error.message);
        if (error.suggestions.isNotEmpty) {
          errors.writeln('  did you mean: ${error.suggestions.join(', ')}?');
        }
        final next = ask(prompt);
        if (next == null || next.isEmpty) return null;
        text = next;
      }
    }
  }

  /// Convert a number with the two units, then read what to do next.  Returns
  /// false when the session must stop.
  bool run(String from, String to) {
    var fromUnit = from;
    var toUnit = to;
    var number = '1.0';
    while (true) {
      try {
        final result = engine.convert(
          value: number,
          from: fromUnit,
          to: toUnit,
          notation: notation,
          decimals: decimals,
        );
        // The historical line: `1.0 in = 2.54 cm`.
        output.writeln(
          '$number $fromUnit = ${result.formatted} $toUnit',
        );
      } on UnitConversionException catch (error) {
        errors.writeln(error.message);
        if (error.suggestions.isNotEmpty) {
          errors.writeln('  did you mean: ${error.suggestions.join(', ')}?');
        }
      }
      final answer = ask('Enter number, [n]ew, [r]everse or [q]uit -> ');
      if (answer == null || answer.isEmpty) return false;
      final choice = answer.toLowerCase()[0];
      if (choice == 'q') return false;
      if (choice == 'r') {
        final swap = fromUnit;
        fromUnit = toUnit;
        toUnit = swap;
        continue;
      }
      if (choice == 'n') {
        final newFrom = ask('Enter from unit -> ');
        if (newFrom == null || newFrom.isEmpty) return false;
        final fromText = readUnit(newFrom, 'Enter from unit -> ');
        if (fromText == null) return false;
        final newTo = ask('Enter to unit -> ');
        if (newTo == null || newTo.isEmpty) return false;
        final toText = readUnit(newTo, 'Enter to unit -> ');
        if (toText == null) return false;
        fromUnit = fromText;
        toUnit = toText;
        number = '1.0';
        output.writeln();
        continue;
      }
      number = answer;
    }
  }
}
