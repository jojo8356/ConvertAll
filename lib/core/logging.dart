// logging.dart, the logging system of the command line tool and the MCP
// server.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// The Python implementation (`source/cmdline.py` of ConvertAll-py) has no
// logging at all: it prints to `stdout` and `stderr` and has no way to explain
// what it is doing.  This file gives the Dart tool the logging layer the
// specification asks for (`--verbose`, `CVT_VERBOSE=1`), modelled on the
// modules that do this well: **Python's `logging`** for the level names and
// the numeric severities (`DEBUG` 10, `INFO` 20, `WARNING` 30, `ERROR` 40,
// `CRITICAL` 50, the same values as syslog through `logging.handlers`), and
// **systemd/syslog** for the idea that a message belongs to a *facility*
// (here: a named logger such as `cli`, `catalog`, `mcp.server`).
//
// Rules that the callers must follow (they are the reason this exists):
//
// * logs go to **stderr** (or to a file), never to stdout: stdout carries the
//   results, and the MCP server writes nothing but JSON-RPC messages there;
// * `--quiet` silences everything below `error`, `--verbose` opens everything
//   down to `debug`, `--log-level` states the level explicitly and wins;
// * a *user* error (a unit that does not exist, two incompatible units) is a
//   normal answer, not a log: it is reported on stdout/stderr by the command
//   itself and logged at `warning` at most, so that a script running
//   `--quiet` keeps it;
// * a *degraded* situation (a case-insensitive fallback, a missing
//   translation, a table extrapolated) is a `warning`: the answer is still
//   given, but something was not exactly as asked;
// * a *failure of the tool itself* (unreadable unit data, unexpected
//   exception) is an `error`, and a failure that makes the program stop is a
//   `critical`.

import 'dart:convert' show jsonEncode;
import 'dart:io' show File, FileMode, IOSink, Platform, stderr;

/// The severity of a record, with the numeric values of Python's `logging`.
enum LogLevel {
  /// Finer than `debug`: every message exchanged, every candidate path.
  trace(5, 'TRACE'),

  /// What the program is doing, step by step.
  debug(10, 'DEBUG'),

  /// Lifecycle facts: version, catalogue loaded, server ready, batch done.
  info(20, 'INFO'),

  /// Something was not available as asked, but the answer was produced.
  warning(30, 'WARNING'),

  /// The operation failed (bad data, refused conversion of a whole batch).
  error(40, 'ERROR'),

  /// The program stops.
  critical(50, 'CRITICAL');

  const LogLevel(this.severity, this.label);

  /// The numeric severity, comparable (`level.severity >= other.severity`).
  final int severity;

  /// The name shown in a record, `INFO`, `WARNING`, ...
  final String label;

  /// The level named [name] (case insensitive, `warn` accepted for
  /// `warning`), or `null` when the name is unknown.
  static LogLevel? fromName(String name) {
    switch (name.trim().toLowerCase()) {
      case 'trace':
      case 'all':
        return LogLevel.trace;
      case 'debug':
        return LogLevel.debug;
      case 'info':
        return LogLevel.info;
      case 'warn':
      case 'warning':
        return LogLevel.warning;
      case 'error':
      case 'err':
        return LogLevel.error;
      case 'critical':
      case 'fatal':
      case 'crit':
        return LogLevel.critical;
      case 'none':
      case 'off':
      case 'silent':
        return LogLevel.critical;
      default:
        return null;
    }
  }

  /// The level named [name], or `null` when the name is unknown.
  static LogLevel? tryParse(String name) => fromName(name);
}

/// One log line: the level, the logger name, the message, and the optional
/// exception that goes with it.
class LogRecord {
  LogRecord({
    required this.level,
    required this.loggerName,
    required this.message,
    this.error,
    this.stackTrace,
    DateTime? time,
  }) : time = time ?? DateTime.now();

  final LogLevel level;

  /// The facility, e.g. `cli`, `catalog`, `mcp.server`.
  final String loggerName;

  final String message;
  final Object? error;
  final StackTrace? stackTrace;
  final DateTime time;

  /// `2026-10-14 09:31:07.123 WARNING catalog: the file was not found`.
  String toText({bool withTime = false, bool withLevel = true}) {
    final buffer = StringBuffer();
    if (withTime) buffer.write('${_timestamp(time)} ');
    if (withLevel) buffer.write('${level.label.padRight(8)} ');
    buffer.write('$loggerName: $message');
    final cause = error;
    if (cause != null) buffer.write(' ($cause)');
    return buffer.toString();
  }

  /// The record as a JSON object, for `--log-format=json`.
  String toJson() => jsonEncode({
    'time': time.toUtc().toIso8601String(),
    'level': level.label,
    'severity': level.severity,
    'logger': loggerName,
    'message': message,
    if (error != null) 'error': '$error',
  });

  static String _timestamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    String three(int value) => value.toString().padLeft(3, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.'
        '${three(time.millisecond)}';
  }
}

/// Where the records are written.
abstract class LogSink {
  /// Write one record.  Never throws: a logging failure must not break a
  /// conversion.
  void add(LogRecord record);

  /// Flush and release what the sink holds.
  Future<void> close() async {}
}

/// Writes the records to a stream (the process `stderr` by default).
class StreamLogSink extends LogSink {
  StreamLogSink(
    this.sink, {
    this.withTime = false,
    this.withLevel = true,
    this.json = false,
  });

  final IOSink sink;
  final bool withTime;
  final bool withLevel;
  final bool json;

  @override
  void add(LogRecord record) {
    try {
      sink.writeln(
        json
            ? record.toJson()
            : record.toText(withTime: withTime, withLevel: withLevel),
      );
    } catch (_) {
      // A closed stderr (a broken pipe) must not raise.
    }
  }

  @override
  Future<void> close() async {
    try {
      await sink.flush();
    } catch (_) {
      // Nothing to do.
    }
  }
}

/// Writes the records to a file, one line per record, in append mode.
///
/// The file is written synchronously: a log line lost in a buffer when the
/// process exits without flushing would be worse than the tiny cost, and the
/// message rate of this tool is a few lines per second at most.
class FileLogSink extends LogSink {
  FileLogSink(this.path, {this.json = false});

  /// The path given by `--log-file`, or by the environment.
  final String path;

  /// True to write one JSON object per line instead of a text line.
  final bool json;

  @override
  void add(LogRecord record) {
    try {
      File(path).writeAsStringSync(
        '${json ? record.toJson() : record.toText(withTime: true)}\n',
        mode: FileMode.append,
      );
    } catch (_) {
      // A log file that cannot be written must not stop the program.
    }
  }
}

/// Keeps the records in memory: used by the tests, and by `doctor --json`.
class MemoryLogSink extends LogSink {
  final records = <LogRecord>[];

  @override
  void add(LogRecord record) => records.add(record);

  /// The records of a level, or of every level at least as severe.
  List<LogRecord> atLeast(LogLevel level) =>
      records.where((record) => record.level.severity >= level.severity).toList();

  /// The text of every record, one per line.
  String get text => records.map((record) => record.toText()).join('\n');

  void clear() => records.clear();
}

/// The logging configuration of the process: one level, one or more sinks.
///
/// This is the equivalent of Python's `logging.basicConfig` /
/// `logging.Logger.manager`, simplified for a single process that logs to
/// `stderr` and, optionally, to a file.
abstract final class Logging {
  /// The records at least this severe are written; the others are dropped
  /// before any formatting happens.
  static LogLevel level = LogLevel.warning;

  static final List<LogSink> _sinks = [];

  /// The environment variable that sets the level, as the specification
  /// proposes (`--verbose` and `CVT_VERBOSE=1`).
  static const levelEnvironmentVariable = 'CONVERTALL_LOG_LEVEL';

  /// The older name of [levelEnvironmentVariable], accepted too.
  static const legacyLevelEnvironmentVariable = 'CVT_LOG_LEVEL';

  /// The sinks currently installed.
  static List<LogSink> get sinks => List.unmodifiable(_sinks);

  /// Replace the configuration: keep the records of [level] and above, and
  /// write them to [sinks].
  static void configure({LogLevel? level, List<LogSink>? sinks}) {
    if (level != null) Logging.level = level;
    if (sinks != null) {
      _sinks
        ..clear()
        ..addAll(sinks);
    }
  }

  /// Add a sink (used for `--log-file`, and by the tests).
  static void addSink(LogSink sink) => _sinks.add(sink);

  /// Remove every sink, e.g. to check that nothing is written.
  static void clearSinks() => _sinks.clear();

  /// True when a record of [level] would be written.
  static bool isEnabled(LogLevel level) =>
      _sinks.isNotEmpty && level.severity >= Logging.level.severity;

  /// Write [record] to every sink.
  static void emit(LogRecord record) {
    if (!isEnabled(record.level)) return;
    for (final sink in _sinks) {
      sink.add(record);
    }
  }

  /// Flush every sink (called before the process exits).
  static Future<void> flush() async {
    for (final sink in _sinks) {
      await sink.close();
    }
  }

  /// Install the default configuration: everything to `stderr`, plus a file
  /// when `--log-file` was given.
  ///
  /// The level is resolved in this order, the first answer winning:
  ///
  /// 1. `--log-level=LEVEL`;
  /// 2. `--verbose` (debug) then `--quiet` (error);
  /// 3. `CONVERTALL_LOG_LEVEL` / `CVT_LOG_LEVEL`;
  /// 4. the default, [LogLevel.warning].
  ///
  /// An explicit option therefore always wins, and a script that exports a
  /// level keeps it as long as it does not pass `--quiet` or `--verbose`.
  /// Returns the level that was kept, so that the caller can log it.
  static LogLevel configureFromOptions({
    required bool quiet,
    required bool verbose,
    String? explicitLevel,
    String? logFile,
    bool json = false,
    IOSink? errorSink,
  }) {
    final explicit = explicitLevel == null
        ? null
        : LogLevel.fromName(explicitLevel);
    level =
        explicit ??
        (verbose ? LogLevel.debug : null) ??
        (quiet ? LogLevel.error : null) ??
        _levelFromEnvironment() ??
        LogLevel.warning;
    if (_sinks.isEmpty) {
      _sinks.add(
        StreamLogSink(
          errorSink ?? stderr,
          withTime: false,
          withLevel: true,
          json: json,
        ),
      );
    }
    if (logFile != null && logFile.isNotEmpty) {
      _sinks.add(FileLogSink(logFile, json: json));
    }
    if (explicitLevel != null && explicit == null) {
      // The sinks are installed, so the warning is visible: an unknown level
      // is not fatal, the automatic choice stays.
      loggerFor('logging').warning(
        'unknown log level "$explicitLevel": '
        '${LogLevel.values.map((item) => item.label.toLowerCase()).join(', ')} '
        'are accepted, keeping ${level.label.toLowerCase()}',
      );
    }
    return level;
  }

  /// The level asked for by the environment, when the name is known.
  static LogLevel? _levelFromEnvironment() {
    final name =
        _environment(levelEnvironmentVariable) ??
        _environment(legacyLevelEnvironmentVariable);
    return name == null ? null : LogLevel.fromName(name);
  }

  /// The value of the environment variable [name], or `null`.
  static String? _environment(String name) {
    final value = Platform.environment[name];
    return value == null || value.trim().isEmpty ? null : value.trim();
  }
}

/// A logger for one facility (`cli`, `catalog`, `mcp.server`, ...), created
/// with [loggerFor].
class Logger {
  Logger(this.name);

  /// The facility name, shown in every record.
  final String name;

  /// The last configuration this logger saw, so that a message building a
  /// string for nothing is avoided.
  bool isEnabled(LogLevel level) => Logging.isEnabled(level);

  void trace(String message, {Object? error, StackTrace? stackTrace}) =>
      _log(LogLevel.trace, message, error, stackTrace);

  void debug(String message, {Object? error, StackTrace? stackTrace}) =>
      _log(LogLevel.debug, message, error, stackTrace);

  void info(String message, {Object? error, StackTrace? stackTrace}) =>
      _log(LogLevel.info, message, error, stackTrace);

  void warning(String message, {Object? error, StackTrace? stackTrace}) =>
      _log(LogLevel.warning, message, error, stackTrace);

  void error(String message, {Object? error, StackTrace? stackTrace}) =>
      _log(LogLevel.error, message, error, stackTrace);

  void critical(String message, {Object? error, StackTrace? stackTrace}) =>
      _log(LogLevel.critical, message, error, stackTrace);

  void _log(
    LogLevel level,
    String message,
    Object? error,
    StackTrace? stackTrace,
  ) {
    if (!isEnabled(level)) return;
    Logging.emit(
      LogRecord(
        level: level,
        loggerName: name,
        message: message,
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }
}

/// The logger of a facility, e.g. `loggerFor('catalog')`.
Logger loggerFor(String name) => Logger(name);
