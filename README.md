# What is ConvertAll?

Why write another unit converter? There are plenty of them out there. Well, I
couldn't find one that worked quite the way I wanted.

With ConvertAll, you can combine the units any way you want. If you want to
convert from inches per decade, that's fine. Or from meter-pounds. Or from
cubic nautical miles. The units don't have to make sense to anyone else.

# More Info

See the [ConvertAll homepage](http://convertall.bellz.org) for more info.

There is also an [online version](http://convertall-web.bellz.org) that can
be used with no software installation.

# Building and packaging

Building and installing on Linux is done with `ca_make.sh` (see the script
usage), while `ca_package.sh` builds a size-optimized release for
Debian GNU/Linux 12 x86_64 and packages it as a `.deb` and an `.AppImage`:

    $ sudo ./ca_package.sh deps
    $ ./ca_package.sh all

The exact commands, the size optimizations and the release procedure are
documented in [PACKAGING.md](PACKAGING.md).  The interface follows a
documented design direction described in [DESIGN.md](DESIGN.md).

# Command line and AI assistants

The conversion engine is also usable without the graphical interface, from the
same `assets/units.json`:

    $ dart run bin/convertall.dart 100 km/hr m/s
    100 km/hr = 27.777778 m/s
    $ dart run bin/convertall.dart -q -f -d 4 1 in cm
    1 in = 2.5400 cm

The options are the ones of the original Python command line tool
(`-d/--decimals`, `-f`, `-s`, `-e`, `-q`, `-i`, `-x`, `-t/--test`,
`--test-all`, `-v/--version`, `-h/--help`, and `--` before a negative number),
and the positional form above is the default command.  The commands are
`convert`, `units`, `types`, `info`, `compatible`, `check`, `doctor`, `repl`,
`mcp` and `version`; `--json` gives machine readable results, `--details`
explains a conversion, `--verbose` traces what the program does.  The
reference is in [docs/CLI.md](docs/CLI.md).

The arithmetic is exact: the factors of the unit data are decimal fractions,
multiplied as rationals, so `1 in = 2.54 cm` really is 2.54 and
`32 F = 0 C` (with `--python-compat` for the historical floating point result
of the Python tool).  Traces follow the levels of Python's `logging` module,
and a refused conversion is a warning on stderr, never on stdout.

`bin/convertall_mcp.dart` (or `convertall mcp`) is a Model Context Protocol
server for an AI assistant.  It exposes five read-only tools — convert a
value, list the quantities, search a unit, describe a unit, and list the units
compatible with another one — over stdin/stdout, and works with any client
that speaks the protocol, recent or older:

    {
      "mcpServers": {
        "convertall": {
          "command": "dart",
          "args": ["run", "/path/to/ConvertAll/bin/convertall_mcp.dart"]
        }
      }
    }

The tools report the exact value too (`value_exact`, `as_fraction`,
`factor_exact`), and `python_compat` reproduces the floating point result of
the Python tool.  Neither program imports Flutter: they run with the Dart SDK
alone, and `dart compile exe bin/convertall_mcp.dart -o convertall-mcp` builds
a standalone binary that needs no SDK at run time.  [docs/MCP.md](docs/MCP.md)
documents the protocol revision implemented (2026-07-28, plus the older
`initialize` handshake), the five tools, the client configuration, the
architecture and the tests.


# Translations

The interface, the help pages and the unit type names are available in
English and French.  The language is set in Settings (Appearance > Language),
where "Follow system" (the default) uses the language of the desktop
session.

The messages live in `lib/l10n/app_en.arb` (the template) and
`lib/l10n/app_fr.arb`; `l10n.yaml` drives the generation of the
`AppLocalizations` class, which `flutter pub get` writes into `lib/l10n/`
(unversioned).  Help pages are in `assets/help/` (English) and
`assets/help/fr/`, the translated unit type names in `assets/units_fr.json`.

Adding a language means adding `lib/l10n/app_xx.arb` (same keys as the
template), `assets/help/xx/` and `assets/units_xx.json`, then listing the new
`Locale` in `supportedLocales` and adding it to the language list of
`lib/gui/settings_edit.dart`.
