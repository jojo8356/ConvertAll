// cli_test.dart, end to end tests of the command line tool.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// Run with:  flutter test test/cli/cli_test.dart
//
// The tool is driven in process (`runConvertAllCli`), with the output captured
// in memory, so the tests need no Dart SDK in the environment and no shell.
// The expected strings are the ones the ConvertAll Python implementation
// prints (`source/cmdline.py`): `1 in = 2.54 cm`, `1 in = 2.5400 cm` with
// `-f -d 4`, `-40 C = -40 F` with `--`, and the exit statuses 0, 1 and 2.

import 'dart:convert' show Encoding, json, utf8;
import 'dart:io' show Directory, File, IOSink;

import 'package:flutter_test/flutter_test.dart';

import 'package:convertall/cli/cli_app.dart';
import 'package:convertall/core/logging.dart';

/// An [IOSink] that keeps everything in a string, for a test to read.
class MemorySink implements IOSink {
  final buffer = StringBuffer();

  /// Everything written so far.
  String get text => buffer.toString();

  /// The lines written so far, without their line break.
  List<String> get lines => text
      .split('\n')
      .where((line) => line.isNotEmpty)
      .toList();

  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) => buffer.write(utf8.decode(data));

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      buffer.write('$error');

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final data in stream) {
      add(data);
    }
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> get done => Future<void>.value();

  @override
  Future<void> flush() async {}

  @override
  void write(Object? object) => buffer.write(object);

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      buffer.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => buffer.writeCharCode(charCode);

  @override
  void writeln([Object? object = '']) => buffer.writeln(object);
}

/// The result of one run of the tool.
class CliRun {
  CliRun(this.status, this.out, this.err);

  final int status;
  final String out;
  final String err;

  /// Standard output split into non-empty lines.
  List<String> get lines => out
      .split('\n')
      .where((line) => line.isNotEmpty)
      .toList();
}

/// Run the tool and collect its output.
Future<CliRun> run(
  List<String> arguments, {
  String? Function()? readLine,
}) async {
  final out = MemorySink();
  final err = MemorySink();
  final status = await runConvertAllCli(
    arguments,
    out: out,
    err: err,
    readLine: readLine,
  );
  return CliRun(status, out.text, err.text);
}

void main() {
  setUp(() {
    // The loggers are global: start every test from the default configuration.
    Logging.clearSinks();
    Logging.level = LogLevel.warning;
  });
  tearDownAll(() {
    Logging.clearSinks();
    Logging.level = LogLevel.warning;
  });

  group('conversions', () {
    test('prints the historical line', () async {
      final result = await run(['1', 'in', 'cm']);
      expect(result.status, 0, reason: result.err);
      expect(result.out.trim(), '1 in = 2.54 cm');
      expect(result.err, isEmpty);
    });

    test('reads the options of the Python tool', () async {
      final quiet = await run(['-q', '1', 'in', 'cm']);
      expect(quiet.out.trim(), '1 in = 2.54 cm');
      final fixed = await run(['-q', '-f', '-d', '4', '1', 'in', 'cm']);
      expect(fixed.status, 0, reason: fixed.err);
      expect(fixed.out.trim(), '1 in = 2.5400 cm');
      final scientific = await run(['-q', '-s', '-d', '3', '1', 'km', 'm']);
      expect(scientific.out.trim(), '1 km = 1.000E+03 m');
      final engineering = await run(['-q', '-e', '-d', '2', '1', 'km', 'm']);
      expect(engineering.out.trim(), '1 km = 1.00E+03 m');
    });

    test('defaults the value to 1.0', () async {
      final result = await run(['-q', 'in', 'cm']);
      expect(result.out.trim(), '1.0 in = 2.54 cm');
    });

    test('accepts options after the units', () async {
      final result = await run(['1', 'in', 'cm', '-q']);
      expect(result.status, 0, reason: result.err);
      expect(result.out.trim(), '1 in = 2.54 cm');
    });

    test('reads a negative number after --', () async {
      final result = await run(['-q', '--', '-40', 'C', 'F']);
      expect(result.status, 0, reason: result.err);
      expect(result.out.trim(), '-40 C = -40 F');
    });

    test('accepts a name with spaces', () async {
      final result = await run(['-q', '1', 'nautical mile', 'm']);
      expect(result.out.trim(), '1 nautical mile = 1852 m');
    });

    test('reads a calculation as the value', () async {
      final result = await run(['-q', '1/8', 'cup', 'ml']);
      expect(result.out.trim(), '1/8 cup = 29.57353 ml');
    });

    test('shows the details with -x', () async {
      final result = await run([
        '--language',
        'en',
        '-q',
        '-x',
        '1',
        'mile',
        'km',
      ]);
      expect(result.status, 0, reason: result.err);
      expect(result.lines.first, '1 mile = 1.609344 km');
      expect(result.out, contains('Base units: mile = m; km = m'));
      expect(result.out, contains('Multiplier: 1 mile = 1.609344 km'));
      expect(result.out, contains('Quantity: length -> length'));
    });

    test('keeps the exact value of a linear conversion in JSON', () async {
      final result = await run(['--json', '1', 'in', 'cm']);
      expect(result.status, 0, reason: result.err);
      final document = json.decode(result.out.trim()) as Map<String, Object?>;
      expect(document['schema_version'], 1);
      expect(document['ok'], true);
      expect(document['result'], '2.54');
      expect(document['value'], 2.54);
      expect(document['value_exact'], '2.54');
      expect(document['as_fraction'], '127/50');
      expect(document['exact'], true);
      // The multiplier from `in` to `cm` is 2.54 exactly (127/50).
      expect(document['factor'], 2.54);
      expect(document['factor_exact'], '127/50');
      expect(document['from'], 'in');
      expect(document['to'], 'cm');
      expect(document['notation'], 'short');
      expect(document['decimals'], 8);
      final catalog = document['catalog'] as Map<String, Object?>;
      expect(catalog['units'], 626);
      expect((catalog['sha256'] as String).length, 64);
      expect((document['tool'] as Map<String, Object?>)['version'], isNotEmpty);
    });

    test('marks a non-linear result as not exact', () async {
      final result = await run(['--json', '-q', '100', 'C', 'F']);
      final document = json.decode(result.out.trim()) as Map<String, Object?>;
      expect(document['result'], '212');
      expect(document['exact'], false);
      expect(document.containsKey('value_exact'), isFalse);
    });
  });

  group('failures and statuses', () {
    test('unknown unit: status 1, message on stderr', () async {
      final result = await run(['-q', '1', 'nonsense', 'm']);
      expect(result.status, 1);
      expect(result.err, contains('nonsense'));
      expect(result.out, isEmpty);
    });

    test('incompatible units: status 1', () async {
      final result = await run(['-q', '1', 'm', 's']);
      expect(result.status, 1);
      expect(result.err, contains('do not measure the same quantity'));
    });

    test('missing units with -q: status 1', () async {
      expect((await run(['-q'])).status, 1);
      expect((await run(['-q', '1', 'm'])).status, 1);
      final missing = await run(['-q', '1', 'm']);
      expect(missing.err.trim(), 'A valid to unit is required');
    });

    test('missing units without -q: status 2', () async {
      final result = await run(['1', 'm']);
      expect(result.status, 2);
      expect(result.err, contains('example: convertall 1 m cm'));
    });

    test('bad number of decimals: status 2, as in Python', () async {
      for (final answer in ['nonsense', '13', '2.5']) {
        final result = await run(['-q', '-d', answer, '1', 'm', 'cm']);
        expect(result.status, 2, reason: 'for -d $answer');
        expect(
          result.err,
          contains('Decimals must be an integer from 0 to 12.'),
          reason: 'for -d $answer',
        );
      }
      // A negative value looks like an option to the parser: still status 2.
      expect((await run(['-q', '-d', '-1', '1', 'm', 'cm'])).status, 2);
    });

    test('too many arguments: status 2', () async {
      final result = await run(['-q', '1', 'm', 'cm', 'extra']);
      expect(result.status, 2);
      expect(result.err, contains('too many arguments'));
    });

    test('unknown option: status 2 with the usage', () async {
      final result = await run(['--does-not-exist']);
      expect(result.status, 2);
      expect(result.err, contains('does-not-exist'));
      expect(result.err, contains('Usage:'));
    });

    test('non finite value: status 1, as in Python', () async {
      for (final answer in ['nan', 'inf']) {
        final result = await run(['-q', answer, 'm', 'cm']);
        expect(result.status, 1, reason: 'for $answer');
      }
    });

    test('a value outside a table: status 1', () async {
      final result = await run(['-q', '0', 'liter per 100 km', 'mpg']);
      expect(result.status, 1);
      expect(result.err, contains('outside the range'));
    });

    test('JSON failure: status 1 with a machine readable code', () async {
      final result = await run(['--json', '-q', '1', 'metr', 'm']);
      expect(result.status, 1);
      final document = json.decode(result.out.trim()) as Map<String, Object?>;
      expect(document['ok'], false);
      expect(document['error_code'], 'unknown_unit');
      expect(document['exit_status'], 1);
      expect(document['suggestions'], isNotEmpty);
    });

    test('a missing catalogue: status 3, Python message', () async {
      final result = await run(['-q', '--units-file', '/nonexistent.dat', 'm', 'cm']);
      expect(result.status, 3);
      expect(result.err, contains('Error in unit data'));
    });
  });

  group('listing commands', () {
    test('types lists the quantities', () async {
      final result = await run(['types']);
      expect(result.status, 0, reason: result.err);
      expect(result.out, contains('length'));
      expect(result.out, contains('volume'));
      final counted = await run(['types', '--count']);
      expect(counted.out.trim(), '52 quantities');
      final asJson = await run(['--json', 'types']);
      final document = json.decode(asJson.out.trim()) as Map<String, Object?>;
      expect((document['types']! as List<dynamic>).length, 52);
    });

    test('units searches the catalogue', () async {
      final result = await run(['units', 'cel']);
      expect(result.status, 0, reason: result.err);
      expect(result.out, contains('Celsius'));
      expect(result.lines.first, contains('NAME'));
      final typed = await run(['--json', 'units', '--type', 'volume']);
      final document = json.decode(typed.out.trim()) as Map<String, Object?>;
      expect(document['count'], greaterThan(0));
    });

    test('info describes a unit', () async {
      final result = await run(['info', 'cal']);
      expect(result.status, 0, reason: result.err);
      expect(result.out, contains('cal'));
      expect(result.out, contains('energy'));
      expect(result.out, contains('Base units'));
    });

    test('compatible lists what a unit converts with', () async {
      final result = await run(['compatible', 'km/hr']);
      expect(result.status, 0, reason: result.err);
      expect(result.out, contains('knot'));
      expect(result.out, contains('mph'));
    });

    test('an unknown type returns an empty successful list', () async {
      final result = await run(['units', '--type', 'nonsense']);
      expect(result.status, 0);
      expect(result.err, isEmpty);
      expect(result.out.trim(), 'No unit to show.');
    });
  });

  group('catalogue check', () {
    test('-t validates the catalogue like the Python tool', () async {
      final result = await run(['-t']);
      expect(result.status, 0, reason: result.err);
      expect(result.out, contains('units.json: 626 units'));
      expect(result.out, contains('All units pass tests'));
    });

    test('check --all also validates every translation', () async {
      final result = await run(['check', '--all']);
      expect(result.status, 0, reason: result.err);
      expect(result.out, contains('units.json: 626 units'));
      expect(result.out, contains('units_fr.json'));
      expect('All units pass tests'.allMatches(result.out).length, 2);
    });

    test('check --json reports every catalogue', () async {
      final result = await run(['check', '--all', '--json']);
      final document = json.decode(result.out.trim()) as Map<String, Object?>;
      expect(document['ok'], true);
      final catalogs = (document['catalogs']! as List<dynamic>)
          .cast<Map<String, Object?>>();
      expect(catalogs.length, 2);
      expect(catalogs.every((entry) => entry['valid'] == true), isTrue);
      expect(catalogs.first['units'], 626);
    });
  });

  group('doctor and version', () {
    test('--version answers without reading the catalogue', () async {
      final result = await run(['--version']);
      expect(result.status, 0);
      expect(result.out.trim(), startsWith('ConvertAll '));
      expect(result.out, contains('(Dart)'));
      expect(result.err, isEmpty);
    });

    test('doctor reports the catalogue and the runtime', () async {
      final result = await run(['doctor', '--json']);
      expect(result.status, 0, reason: result.err);
      final document = json.decode(result.out.trim()) as Map<String, Object?>;
      expect(document['application'], 'ConvertAll');
      expect(document['runtime'], 'Dart');
      expect(document['units'], 626);
      expect(document['unit_types'], 52);
      final catalog = document['catalog'] as Map<String, Object?>;
      expect(catalog['file'], endsWith('units.json'));
      expect((catalog['sha256'] as String).length, 64);
      expect(document['mcp_protocol_versions'], isNotEmpty);
    });

    test('--runtime-info is the same answer, as in the Python tool', () async {
      final result = await run(['--runtime-info']);
      expect(result.status, 0, reason: result.err);
      final document = json.decode(result.out.trim()) as Map<String, Object?>;
      expect(document['version'], isNotEmpty);
      expect(document['units'], 626);
    });

    test('version prints the version and the catalogue', () async {
      final result = await run(['version']);
      expect(result.status, 0);
      expect(result.out, contains('626 units'));
      expect(result.out, contains('MCP protocol revisions'));
    });
  });

  group('logging', () {
    test('writes nothing by default', () async {
      final result = await run(['1', 'in', 'cm']);
      expect(result.err, isEmpty);
    });

    test('--verbose traces the catalogue, the request and the result', () async {
      final result = await run(['--verbose', '1', 'in', 'cm']);
      expect(result.status, 0, reason: result.err);
      expect(result.out.trim(), '1 in = 2.54 cm');
      expect(result.err, contains('DEBUG'));
      expect(result.err, contains('catalog:'));
      expect(result.err, contains('reading the unit data from'));
      expect(result.err, contains('loaded from'));
      expect(result.err, contains('engine:'));
      expect(result.err, contains('result 127/50 (exact)'));
      expect(result.err, contains('finished in'));
    });

    test('--log-level=trace adds the options and the tool refusals', () async {
      final result = await run(
        ['--log-level', 'trace', '-q', '1', 'nonsense', 'm'],
      );
      expect(result.status, 1);
      expect(result.err, contains('TRACE'));
      expect(result.err, contains('option decimals'));
      expect(result.err, contains('tool convert_value refused'));
    });

    test('--quiet keeps only the errors', () async {
      final result = await run(['--quiet', '--verbose', '1', 'in', 'cm']);
      // `--verbose` wins over `--quiet`, as the help states.
      expect(result.err, contains('DEBUG'));
      final explicit = await run(['--quiet', '--log-level', 'error', '1', 'in', 'cm']);
      expect(explicit.err, isEmpty);
    });

    test('an unknown level is reported and ignored', () async {
      final result = await run(['--log-level', 'chatty', '1', 'in', 'cm']);
      expect(result.status, 0);
      expect(result.err, contains('unknown log level "chatty"'));
    });

    test('--log-format=json writes JSON records', () async {
      final result = await run(['--log-format', 'json', '--verbose', '1', 'in', 'cm']);
      final record = json.decode(result.err.split('\n').first.trim());
      expect(record['level'], 'DEBUG');
      expect(record['logger'], isNotEmpty);
      expect(record['severity'], 10);
    });

    test('--log-file appends the records', () async {
      final directory = Directory.systemTemp.createTempSync('convertall-cli');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/cli.log');
      final result = await run([
        '--log-file',
        file.path,
        '--verbose',
        '1',
        'in',
        'cm',
      ]);
      expect(result.status, 0, reason: result.err);
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), contains('INFO     cli: answer: 1 in = 2.54 cm'));
    });
  });

  group('interactive mode', () {
    test('reads units, a number, a reversal and leaves on q', () async {
      final input = <String>['in', 'cm', '2', 'r', 'q'];
      var index = 0;
      final result = await run(
        ['-i'],
        readLine: () => index < input.length ? input[index++] : null,
      );
      expect(result.status, 0, reason: result.err);
      expect(result.out, contains('Enter from unit -> '));
      expect(result.out, contains('Enter to unit -> '));
      expect(result.out, contains('1.0 in = 2.54 cm'));
      expect(result.out, contains('2 in = 5.08 cm'));
      expect(result.out, contains('2 cm = 0.78740157 in'));
      expect(result.out, contains('Enter number, [n]ew, [r]everse or [q]uit -> '));
    });

    test('an empty line leaves with status 0', () async {
      var index = 0;
      final input = <String>[''];
      final result = await run(
        ['-i'],
        readLine: () => index < input.length ? input[index++] : null,
      );
      expect(result.status, 0);
    });

    test('an unknown unit is reported and asked again', () async {
      final input = <String>['nonsense', 'in', 'cm', 'q'];
      var index = 0;
      final result = await run(
        ['-i'],
        readLine: () => index < input.length ? input[index++] : null,
      );
      expect(result.status, 0);
      expect(result.err, contains('nonsense'));
      expect(result.out, contains('1.0 in = 2.54 cm'));
    });

    test('the end of the input leaves with status 0', () async {
      final result = await run(['-i'], readLine: () => null);
      expect(result.status, 0);
    });
  });

  group('help', () {
    test('documents the options of the Python tool', () async {
      for (final flag in ['-h', '--help']) {
        final result = await run([flag]);
        expect(result.status, 0);
        for (final word in [
          'Usage',
          '--version',
          '--test',
          '--test-all',
          '--quiet',
          '--decimals',
          '--log-level',
        ]) {
          expect(result.out, contains(word), reason: 'for $flag');
        }
      }
    });

    test('gives the usage of one command', () async {
      final result = await run(['help', 'convert']);
      expect(result.status, 0);
      expect(result.out, contains('convertall convert'));
      expect(result.out, contains('--log-level'));
    });

    test('solves the help of a command given after it', () async {
      final result = await run(['convert', '--help']);
      expect(result.status, 0);
      expect(result.out, contains('Convert VALUE'));
    });
  });
}
