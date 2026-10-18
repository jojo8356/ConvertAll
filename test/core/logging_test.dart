// logging_test.dart, tests of the logging system.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// Run with:  flutter test test/core/logging_test.dart
//
// The severity levels are the numeric values of Python's `logging`
// (DEBUG 10, INFO 20, WARNING 30, ERROR 40, CRITICAL 50), so that a reader who
// knows the standard module finds its way, and the filtering follows the rule
// the specification states: an explicit `--log-level` wins over `--quiet` and
// over `--verbose`.

import 'package:flutter_test/flutter_test.dart';

import 'package:convertall/core/logging.dart';

void main() {
  // Every test restores the default configuration, since the loggers are
  // global (the CLI and the MCP server share them).
  tearDown(() {
    Logging.clearSinks();
    Logging.level = LogLevel.warning;
  });

  group('levels', () {
    test('carry the severity of the logging module', () {
      expect(LogLevel.trace.severity, lessThan(LogLevel.debug.severity));
      expect(LogLevel.debug.severity, 10);
      expect(LogLevel.info.severity, 20);
      expect(LogLevel.warning.severity, 30);
      expect(LogLevel.error.severity, 40);
      expect(LogLevel.critical.severity, 50);
    });

    test('are named, with the usual aliases', () {
      expect(LogLevel.fromName('debug'), LogLevel.debug);
      expect(LogLevel.fromName('WARN'), LogLevel.warning);
      expect(LogLevel.fromName('warning'), LogLevel.warning);
      expect(LogLevel.fromName('fatal'), LogLevel.critical);
      expect(LogLevel.fromName('all'), LogLevel.trace);
      expect(LogLevel.fromName('nonsense'), isNull);
      expect(LogLevel.info.label, 'INFO');
    });
  });

  group('loggers', () {
    test('write to the installed sinks, and only above the level', () {
      final memory = MemoryLogSink();
      Logging.configure(level: LogLevel.info, sinks: [memory]);
      final log = loggerFor('catalog');
      log.debug('invisible');
      log.info('visible');
      log.warning('visible too');
      expect(memory.records.length, 2);
      expect(memory.records.first.loggerName, 'catalog');
      expect(memory.records.first.message, 'visible');
      expect(memory.text, contains('INFO     catalog: visible'));
      expect(memory.text, contains('WARNING  catalog: visible too'));
    });

    test('write nothing when no sink is installed', () {
      final memory = MemoryLogSink();
      Logging.clearSinks();
      final log = loggerFor('cli');
      expect(log.isEnabled(LogLevel.critical), isFalse);
      log.critical('lost');
      expect(memory.records, isEmpty);
    });

    test('keep the exception that goes with a record', () {
      final memory = MemoryLogSink();
      Logging.configure(level: LogLevel.error, sinks: [memory]);
      loggerFor('cli').error(
        'the catalogue could not be read',
        error: const FormatException('bad json'),
      );
      expect(memory.records.single.error, isA<FormatException>());
      expect(memory.text, contains('bad json'));
    });

    test('filter by severity, the way a caller asks', () {
      final memory = MemoryLogSink();
      Logging.configure(level: LogLevel.trace, sinks: [memory]);
      final log = loggerFor('engine');
      log.trace('a');
      log.debug('b');
      log.error('c');
      expect(memory.records.length, 3);
      expect(memory.atLeast(LogLevel.error).single.message, 'c');
      memory.clear();
      expect(memory.records, isEmpty);
    });
  });

  group('records', () {
    test('render as text with the level and the facility', () {
      final record = LogRecord(
        level: LogLevel.warning,
        loggerName: 'mcp.server',
        message: 'the unit "mtr" is not known',
      );
      expect(
        record.toText(),
        'WARNING  mcp.server: the unit "mtr" is not known',
      );
      expect(record.toText(withTime: true), contains('WARNING'));
    });

    test('render as JSON, with the numeric severity', () {
      final record = LogRecord(
        level: LogLevel.error,
        loggerName: 'cli',
        message: 'failed',
        error: 'boom',
      );
      final text = record.toJson();
      expect(text, contains('"level":"ERROR"'));
      expect(text, contains('"severity":40'));
      expect(text, contains('"logger":"cli"'));
      expect(text, contains('"error":"boom"'));
      expect(text, contains('"time":"'));
    });
  });

  group('configuration from the options', () {
    test('defaults to warning', () {
      final memory = MemoryLogSink();
      Logging.clearSinks();
      Logging.addSink(memory);
      final level = Logging.configureFromOptions(quiet: false, verbose: false);
      expect(level, LogLevel.warning);
      expect(Logging.level, LogLevel.warning);
    });

    test('quiet keeps the errors, verbose opens the debug', () {
      expect(
        Logging.configureFromOptions(quiet: true, verbose: false),
        LogLevel.error,
      );
      expect(
        Logging.configureFromOptions(quiet: false, verbose: true),
        LogLevel.debug,
      );
      // `--quiet --verbose` cannot mean both: the trace wins, as the help says.
      expect(
        Logging.configureFromOptions(quiet: true, verbose: true),
        LogLevel.debug,
      );
    });

    test('an explicit level wins over the flags', () {
      expect(
        Logging.configureFromOptions(
          quiet: true,
          verbose: false,
          explicitLevel: 'trace',
        ),
        LogLevel.trace,
      );
      expect(
        Logging.configureFromOptions(
          quiet: false,
          verbose: true,
          explicitLevel: 'error',
        ),
        LogLevel.error,
      );
      // An unknown name falls back to the automatic choice.
      expect(
        Logging.configureFromOptions(
          quiet: false,
          verbose: false,
          explicitLevel: 'chatty',
        ),
        LogLevel.warning,
      );
    });

    test('installs the stderr sink once', () {
      Logging.clearSinks();
      Logging.configureFromOptions(quiet: false, verbose: false);
      expect(Logging.sinks.length, 1);
      Logging.configureFromOptions(quiet: false, verbose: true);
      expect(Logging.sinks.length, 1, reason: 'the sink is not duplicated');
    });
  });
}
