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
