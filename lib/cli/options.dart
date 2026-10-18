// options.dart, the command line grammar of ConvertAll.
// ConvertAll, a versatile unit conversion program.
// Copyright (c) 2026, Douglas W. Bell.
// Free software, GPL v2 or later.
//
// The notation is the one of the ConvertAll Python implementation
// (`source/cmdline.py`: `-d/--decimals`, `-f/--fixed-decimals`,
// `-s/--sci-notation`, `-e/--eng-notation`, `-i/--interactive`,
// `-q/--quiet`, `-t/--test`, `--test-all`, `-v/--version`, `-h/--help`), so a
// script written for `convertall.py` works with `convertall` unchanged:
//
//    convertall 1 in cm
//    convertall -q -f -d 4 1 in cm
//    convertall -q -- -40 C F
//    convertall -t
//
// The positional form is read the way the Python tool reads it, `float()`
// deciding whether the first argument is the value ([isValueArgument]); a
// calculation (`1/8`) is accepted as well, which the specification adds.
//
// The additions of the specification (`doc/CLI_RUST_CAHIER_DES_CHARGES.md`)
// keep the same shape: a long option, a value with `=` or a space, and no
// short form when there is no obvious one: `--json`, `--log-level`,
// `--units-file`, `--python-compat`.  `-v` stays the *version*, as in Python;
// the verbosity is `--verbose`, long only, so the two never collide.

import 'package:args/args.dart';

import '../core/exact_math.dart';
import '../core/number_notation.dart';

/// The exit statuses of the command line tool.
///
/// `0`, `1`, `2` and `130` are the ones of the ConvertAll Python
/// implementation; `3` is the addition of the specification for a catalogue
/// that cannot be read or that fails its validation.
abstract final class CliStatus {
  /// Success (the result is on stdout).
  static const ok = 0;

  /// Conversion or data error: unknown unit, incompatible units, bad value.
  static const failed = 1;

  /// Usage error: unknown option, missing argument, value out of range.
  static const usage = 2;

  /// The unit catalogue is missing, unreadable, or refused by `--test`.
  static const catalog = 3;

  /// The user interrupted the program (`Ctrl-C`).
  static const interrupted = 130;
}

/// The commands of the tool.  The first one is the default: `convertall 1 in
/// cm` is `convertall convert 1 in cm`.
const cliCommands = <String>[
  'convert',
  'units',
  'types',
  'info',
  'compatible',
  'check',
  'doctor',
  'repl',
  'mcp',
  'version',
  'help',
];

/// The options that take a value, used to find the first real argument of a
/// command line (`convertall -d 3 1 in cm` must be read as a conversion).
const optionsWithValues = <String>[
  '-d',
  '--decimals',
  '-n',
  '--notation',
  '-l',
  '--language',
  '--units-file',
  '--log-level',
  '--log-file',
  '--log-format',
  '--type',
  '--limit',
  '--compatible-limit',
];

/// Build the argument parser of the whole tool.
ArgParser buildCliParser() {
  // The conversion options live on the root parser too, so that the historical
  // forms (`convertall -q 1 in cm`) work without naming a command.
  final parser = _addDiagnosticOptions(
    _addConversionOptions(_addCommonOptions(_newParser())),
  );
  parser.addCommand('convert', _addConversionOptions(_addCommonOptions(_newParser())));
  parser.addCommand('units', _searchOptions());
  parser.addCommand('types', _typesOptions());
  parser.addCommand('info', _infoOptions());
  parser.addCommand('compatible', _compatibleOptions());
  parser.addCommand('check', _checkOptions());
  parser.addCommand('doctor', _addCommonOptions(_newParser()));
  parser.addCommand('repl', _addCommonOptions(_newParser()));
  parser.addCommand('mcp', _addCommonOptions(_newParser()));
  parser.addCommand('version', _addCommonOptions(_newParser()));
  parser.addCommand(
    'help',
    ArgParser(allowTrailingOptions: true)
      ..addFlag('help', abbr: 'h', negatable: false),
  );
  return parser;
}

ArgParser _newParser() => ArgParser(allowTrailingOptions: true);

ArgParser _typesOptions() {
  final parser = _addCommonOptions(_newParser());
  parser.addFlag(
    'count',
    negatable: false,
    help: 'Only print the number of quantities.',
  );
  return parser;
}

ArgParser _infoOptions() {
  final parser = _addCommonOptions(_newParser());
  parser.addOption(
    'compatible-limit',
    help: 'Number of compatible units to list (0 to 500, default 15).',
  );
  return parser;
}

ArgParser _compatibleOptions() {
  final parser = _addCommonOptions(_newParser());
  parser.addOption(
    'limit',
    help: 'Maximum number of units (1 to 500, default 50).',
  );
  return parser;
}

ArgParser _checkOptions() {
  final parser = _addCommonOptions(_newParser());
  parser.addFlag(
    'all',
    negatable: false,
    help: 'Validate every catalogue next to the selected one.',
  );
  return parser;
}

ArgParser _addCommonOptions(ArgParser parser) {
  parser
    ..addFlag(
      'json',
      negatable: false,
      help: 'Print the result as JSON on stdout (errors too).',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Display the help of the command and exit.',
    )
    ..addFlag(
      'version',
      abbr: 'v',
      negatable: false,
      help: 'Show the application version and exit.',
    )
    ..addOption(
      'language',
      abbr: 'l',
      help: 'Language of the unit names: en (default), fr, or auto.',
    )
    ..addOption(
      'units-file',
      help: 'Path of the unit data file (default: searched around the tool).',
    );
  _addLoggingOptions(parser);
  return parser;
}

ArgParser _addConversionOptions(ArgParser parser) {
  parser
    ..addOption(
      'decimals',
      abbr: 'd',
      help: 'Number of decimals to show (0 to $maxDecimals, default 8).',
    )
    ..addFlag(
      'fixed-decimals',
      abbr: 'f',
      negatable: false,
      help: 'Show the set number of decimals, even if zeros.',
    )
    ..addFlag(
      'sci-notation',
      abbr: 's',
      negatable: false,
      help: 'Show results in scientific notation.',
    )
    ..addFlag(
      'eng-notation',
      abbr: 'e',
      negatable: false,
      help: 'Show results in engineering notation.',
    )
    ..addFlag(
      'quiet',
      abbr: 'q',
      negatable: false,
      help: 'Convert without further prompts, and log only errors.',
    )
    ..addFlag(
      'interactive',
      abbr: 'i',
      negatable: false,
      help: 'Interactive command line mode (non-GUI).',
    )
    ..addFlag(
      'details',
      abbr: 'x',
      negatable: false,
      help: 'Also show the base units, the multiplier and the quantity.',
    )
    ..addOption(
      'notation',
      abbr: 'n',
      help: 'Notation of the result: ${notationNames.join(', ')}.',
    )
    ..addFlag(
      'python-compat',
      negatable: false,
      help: 'Compute the factors as doubles, like the Python implementation.',
    );
  return parser;
}

ArgParser _addDiagnosticOptions(ArgParser parser) {
  parser
    ..addFlag(
      'test',
      abbr: 't',
      negatable: false,
      help: 'Validate the selected unit catalogue and exit.',
    )
    ..addFlag(
      'test-all',
      negatable: false,
      help: 'Validate every installed unit catalogue and exit.',
    )
    ..addFlag(
      'runtime-info',
      negatable: false,
      help: 'Show the version, the catalogue and the environment as JSON.',
    );
  return parser;
}

void _addLoggingOptions(ArgParser parser) {
  parser
    ..addFlag(
      'verbose',
      negatable: false,
      help: 'Trace what the tool does (same as --log-level=debug).',
    )
    ..addOption(
      'log-level',
      help:
          'Lowest severity written: trace, debug, info, warning, error, '
          'critical (default warning).',
    )
    ..addOption(
      'log-file',
      help: 'Also append the log records to this file.',
    )
    ..addOption(
      'log-format',
      allowed: ['text', 'json'],
      defaultsTo: 'text',
      help: 'Format of the log records.',
    );
}

ArgParser _searchOptions() {
  final parser = _addCommonOptions(_newParser());
  parser
    ..addOption('type', help: 'Restrict to one quantity, e.g. --type volume.')
    ..addOption('limit', help: 'Maximum number of units (1 to 500, default 25).')
    ..addOption(
      'sort',
      allowed: ['name', 'type'],
      defaultsTo: 'name',
      help: 'Sort the units by name or by quantity.',
    );
  return parser;
}

/// The usage text, in the shape of the one printed by the Python
/// implementation (`cmdline.py`): the two invocation forms, the same option
/// lines, and the exit codes it prints.
String cliUsage(ArgParser parser) {
  final buffer = StringBuffer()
    ..writeln('Usage:')
    ..writeln()
    ..writeln('   convertall [options] [value] [from unit] [to unit]')
    ..writeln()
    ..writeln('-or- (non-GUI):')
    ..writeln('   convertall -i [options]')
    ..writeln()
    ..writeln('Units with spaces must be "quoted"')
    ..writeln()
    ..writeln('Options:')
    ..writeln('   -d, --decimals=NUM      number of decimals to show '
        '(0 to $maxDecimals, default 8)')
    ..writeln('   -n, --notation=NAME     notation: '
        '${notationNames.join(', ')}')
    ..writeln('   -f, --fixed-decimals    show the set number of '
        'decimals, even if zeros')
    ..writeln('   -s, --sci-notation      show results in '
        'scientific notation')
    ..writeln('   -e, --eng-notation      show results in '
        'engineering notation')
    ..writeln('   -q, --quiet             convert without further '
        'prompts, and log only errors')
    ..writeln('   -i, --interactive       interactive command line mode '
        '(non-GUI)')
    ..writeln('   -t, --test              validate the selected unit '
        'catalogue')
    ..writeln('       --test-all          validate every installed unit '
        'catalogue')
    ..writeln('   -l, --language=LANG     language of the unit names: '
        'en, fr or auto')
    ..writeln('       --units-file=FILE   path of the unit data file')
    ..writeln('       --json              print the result as JSON')
    ..writeln('       --python-compat     compute the factors as doubles, '
        'like the Python tool')
    ..writeln('   -v, --version           show the application version '
        'and exit')
    ..writeln('   -h, --help              display this message and exit')
    ..writeln()
    ..writeln('Logging (stderr; the results stay on stdout):')
    ..writeln('       --log-level=LEVEL   trace, debug, info, warning, '
        'error, critical (default warning)')
    ..writeln('       --verbose           same as --log-level=debug')
    ..writeln('       --log-file=FILE     also append the log records '
        'to FILE')
    ..writeln('       --log-format=FORMAT text (default) or json')
    ..writeln()
    ..writeln('Commands:')
    ..writeln('   convert VALUE FROM TO   convert a value between two '
        'units (the default command)')
    ..writeln('   units [QUERY]           list or search the units')
    ..writeln('   types                   list the quantities of the '
        'catalogue')
    ..writeln('   info UNIT               describe one unit')
    ..writeln('   compatible UNIT         list the units it can be '
        'converted with')
    ..writeln('   check [--all]           validate the unit catalogue')
    ..writeln('   doctor                  show the version, the catalogue '
        'and the environment')
    ..writeln('   repl                    interactive command line mode')
    ..writeln('   mcp                     serve the Model Context '
        'Protocol on stdin/stdout')
    ..writeln('   version                 show the version')
    ..writeln()
    ..writeln('Examples:')
    ..writeln('   convertall 1 in cm')
    ..writeln('   convertall -q -f -d 4 1 in cm')
    ..writeln('   convertall -q -- -40 C F')
    ..writeln('   convertall --json 100 km/hr m/s')
    ..writeln('   convertall compatible "light year"')
    ..writeln()
    ..writeln('Exit codes: 0=success, 1=conversion/data error, '
        '2=usage error,')
    ..writeln('            3=catalogue error, 130=interrupted.  '
        'Use -- before negative numbers.');
  return buffer.toString();
}

/// The short help of one command, printed by `convertall help <command>` and
/// by `convertall <command> --help`.
String commandUsage(String command, ArgParser parser) {
  final summary = <String, String>{
    'convert':
        'Convert VALUE from one unit to another.\n\n'
        '  convertall convert 100 km/hr m/s\n'
        '  convertall convert 70 F C -x\n'
        '  convertall convert 1/8 cup ml',
    'units':
        'Search the unit catalogue.  QUERY matches the beginning of any word of\n'
        'a unit name: "cel" finds Celsius.\n\n'
        '  convertall units cel --type temperature\n'
        '  convertall units --type volume --limit 10',
    'types': 'List the quantities of the catalogue, with the number of units.',
    'info':
        'Describe one unit: quantity, equivalent, base units, multiplier and\n'
        'compatibility.  Use it when a name is ambiguous.\n\n'
        '  convertall info cal',
    'compatible':
        'List the units that can be converted with UNIT, which answers "what can\n'
        'I convert X to?".\n\n'
        '  convertall compatible "light year"',
    'check':
        'Validate the unit catalogue: every unit reduces to base units, every\n'
        'factor is finite and positive, every equation can be evaluated.\n\n'
        '  convertall check\n'
        '  convertall check --all',
    'doctor':
        'Show the application version, the Dart runtime, the catalogue that was\n'
        'loaded (path, SHA-256, number of units) and the language in use.\n\n'
        '  convertall doctor\n'
        '  convertall doctor --json',
    'repl': 'Interactive mode: enter a value, a from unit and a to unit, then a\n'
        'new number, [r]everse, [n]ew or [q]uit.',
    'mcp':
        'Serve the Model Context Protocol on stdin/stdout for a language model\n'
        'client.  Nothing but JSON-RPC messages goes to stdout; the traces go to\n'
        'stderr and follow --log-level.',
    'version': 'Show the application version.',
    'help': 'Show the general help, or the help of one command.',
  };
  final buffer = StringBuffer()
    ..writeln('convertall $command [options] [arguments]')
    ..writeln();
  final text = summary[command];
  if (text != null) {
    buffer
      ..writeln(text)
      ..writeln();
  }
  buffer.writeln(parser.usage);
  _addLoggingHelp(buffer);
  return buffer.toString();
}

void _addLoggingHelp(StringBuffer buffer) {
  buffer
    ..writeln('  --verbose            trace what the tool does')
    ..writeln('  --log-level=LEVEL    trace, debug, info, warning, error, critical')
    ..writeln('  --log-file=FILE      also append the log records to a file')
    ..writeln('  --log-format=FORMAT  text or json');
}

/// True when [text] is the value of the positional form and not a unit.
///
/// The Python tool reads its first argument as the number only when `float()`
/// accepts it, which is what makes `convertall -q in cm` convert `1.0 in` to
/// `cm` (and `convertall -q 1 in cm` convert `1 in`).  `nan` and `infinity`
/// are accepted here so that the tool answers "Number must be finite", as
/// Python does, and a calculation (`1/8`, `3*4+1`) is the addition of the
/// specification.
bool isValueArgument(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;
  if (ExactMath.tryEvaluate(trimmed) != null) return true;
  // Python accepts `1_000`, and both languages accept `nan` and `infinity`.
  final cleaned = trimmed.replaceAll('_', '');
  if (double.tryParse(cleaned) != null) return true;
  var name = cleaned.toLowerCase();
  if (name.startsWith('+') || name.startsWith('-')) name = name.substring(1);
  return name == 'nan' || name == 'inf' || name == 'infinity';
}

/// The argument list of a call: the first bare word selects the command, and a
/// word that is not a command makes the whole line the positional form of the
/// conversion (`convertall 1 in cm`, `convertall -q -- -40 C F`).
///
/// `--` ends the options, so a negative number can follow it; the conversion
/// command is then inserted in front of the list, since the parser refuses
/// bare arguments before a command.
List<String> normalizeArguments(List<String> arguments) {
  var index = 0;
  while (index < arguments.length) {
    final argument = arguments[index];
    if (argument == '--') return ['convert', ...arguments];
    if (argument.startsWith('-')) {
      // `--option=value` is one word; `--option value` is two.
      if (!argument.contains('=') && optionsWithValues.contains(argument)) {
        index += 2;
        continue;
      }
      index += 1;
      continue;
    }
    // The first bare word: a command, or the value of a conversion.
    if (cliCommands.contains(argument)) return arguments;
    return ['convert', ...arguments];
  }
  return arguments;
}
