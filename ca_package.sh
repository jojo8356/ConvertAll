#!/bin/sh

# ca_package.sh, a Debian/AppImage packaging tool for ConvertAll.
# ConvertAll, a versatile unit conversion program.
# Copyright (c) 2026, Douglas W. Bell.
# Free software, GPL v2 or later.
#
# Builds a size-optimized Linux release bundle and packages it as a Debian
# package (.deb) and/or an AppImage for Debian GNU/Linux 12 (bookworm) x86_64.
# The 'deb' and 'appimage' commands need no root privileges: they only write
# under ./dist, ./build and ./tools, and the produced .deb installs the
# program under /opt/convertall with a symlink in /usr/bin.
#
# Typical usage:
#     $ sudo ./ca_package.sh deps
#     $ ./ca_package.sh all
#
# See PACKAGING.md for the full explanation and for the release procedure.

set -eu

PROG=${0##*/}
ROOT=$(cd -- "$(dirname -- "$0")" && pwd)
PACKAGING="$ROOT/linux/packaging"
BUNDLE="$ROOT/build/linux/x64/release/bundle"
OUT="$ROOT/dist"
APPIMAGETOOL=${APPIMAGETOOL:-}
PKG_REV=${PKG_REV:-1}
MAINTAINER=${MAINTAINER:-"Doug Bell <doug101@bellz.org>"}
APPIMAGETOOL_TAG=1.9.1
APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download"
WORK=
SKIP_BUILD=0
KEEP=0
OBFUSCATE=0

usage () {
    cat <<EOF
Usage: $PROG <command> [options]

Commands:
    deps        install the build and packaging tools (needs sudo/root)
    bundle      only build and optimize the release bundle
    deb         build the Debian package (.deb)
    appimage    build the AppImage
    all         build the bundle, then the .deb and the AppImage

Options:
    --bundle DIR        use this release bundle instead of building one
    --out DIR           write packages here (default: ./dist)
    --appimagetool P    use this appimagetool instead of searching for it
    --skip-build        do not run 'flutter build', reuse the existing bundle
    --obfuscate         build with --obfuscate (smaller Dart code, but stack
                        traces need the symbols kept in build/symbols)
    --keep              keep the temporary package trees
    -h, --help          show this help

Environment:
    FLUTTER             path to the flutter command to use
    APPIMAGETOOL        path to appimagetool (also set by --appimagetool)
    PKG_REV             Debian package revision (default: 1)
    MAINTAINER          value of the Debian Maintainer field
EOF
}

die () {
    echo
    echo "$PROG: $1" 1>&2
    echo
    exit 1
}

note () {
    echo
    echo "=== $1 ==="
}

cleanup () {
    if [ -n "$WORK" ] && [ "$KEEP" -eq 0 ] && [ -d "$WORK" ]; then
        rm -rf "$WORK"
    fi
}

new_workdir () {
    if [ -z "$WORK" ]; then
        WORK=$(mktemp -d "${TMPDIR:-/tmp}/convertall-package.XXXXXX") \
            || die "Could not create a temporary work directory"
        trap cleanup EXIT
        trap 'cleanup; exit 130' INT TERM
    fi
}

read_version () {
    version_line=$(sed -n 's/^version:[[:space:]]*//p' "$ROOT/pubspec.yaml" \
        | head -n 1)
    [ -n "$version_line" ] \
        || die "Could not read the 'version:' line of pubspec.yaml"
    APP_VERSION=${version_line%%+*}
    BUILD_NUMBER=1
    case "$version_line" in
        *+*) BUILD_NUMBER=${version_line#*+} ;;
    esac
    [ -n "$APP_VERSION" ] || die "Malformed version '$version_line'"
    case "$APP_VERSION" in
        *[!0-9.]*) die "Version '$APP_VERSION' is not numeric" ;;
    esac
}

check_arch () {
    [ "$(uname -m)" = x86_64 ] \
        || die "These packages are built for x86_64 (this machine is
$(uname -m))."
}

find_flutter () {
    if [ -n "${FLUTTER:-}" ]; then
        [ -x "${FLUTTER}" ] || die "FLUTTER=$FLUTTER is not executable"
        echo "${FLUTTER}"
    elif command -v flutter >/dev/null 2>&1; then
        command -v flutter
    elif [ -x "$ROOT/flutter/bin/flutter" ]; then
        echo "$ROOT/flutter/bin/flutter"
    else
        die "Flutter was not found.  Run './ca_make.sh build' once (it
downloads Flutter into ./flutter), put flutter in your PATH or set FLUTTER."
    fi
}

build_bundle () {
    flutter_bin=$(find_flutter)
    echo "Using Flutter:  $flutter_bin"
    note "Building the release bundle"
    # --release: AOT compiled Dart, asserts off, icon font tree-shaken.
    # --split-debug-info: debug info goes to build/symbols instead of the
    # bundle (keep that directory to be able to symbolize crash reports).
    if [ "$OBFUSCATE" -eq 1 ]; then
        ( cd "$ROOT" \
            && "$flutter_bin" build linux --release \
                --build-name "$APP_VERSION" --build-number "$BUILD_NUMBER" \
                --split-debug-info="$ROOT/build/symbols" --obfuscate )
    else
        ( cd "$ROOT" \
            && "$flutter_bin" build linux --release \
                --build-name "$APP_VERSION" --build-number "$BUILD_NUMBER" \
                --split-debug-info="$ROOT/build/symbols" )
    fi
    echo "Build done"
}

check_bundle () {
    [ -x "$BUNDLE/convertall" ] \
        || die "No release bundle in
$BUNDLE
Build one first ('./ca_package.sh bundle') or pass --bundle DIR."
    [ -f "$BUNDLE/data/icudtl.dat" ] \
        || die "The bundle looks incomplete (data/icudtl.dat is missing)"
}

optimize_bundle () {
    command -v strip >/dev/null 2>&1 \
        || die "The 'strip' tool is missing (install binutils)"
    note "Stripping debug symbols from the bundle"
    strip --strip-all "$BUNDLE/convertall" \
        || die "Could not strip the convertall executable"
    for lib_file in "$BUNDLE"/lib/*.so; do
        [ -f "$lib_file" ] || continue
        strip --strip-unneeded "$lib_file" || true
    done
    echo "Strip done"
}

desktop_file () {
    # Desktop Entry prepared for installation: the icon is looked up by name
    # in the hicolor theme, and the spec Version field is set to 1.0.
    sed -e 's|^Icon=.*|Icon=convertall|' \
        -e 's|^Version=.*|Version=1.0|' \
        "$ROOT/convertall.desktop" > "$1"
    chmod 644 "$1"
}

appdata_file () {
    today=$(date -u +%Y-%m-%d)
    sed -e "s|@VERSION@|$APP_VERSION|g" -e "s|@DATE@|$today|g" \
        "$PACKAGING/org.bellz.convertall.appdata.xml.in" > "$1"
    chmod 644 "$1"
}

copyright_file () {
    cat > "$1" <<'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: ConvertAll
Source: https://convertall.bellz.org/

Files: *
Copyright: 2003-2026 Douglas W. Bell
License: GPL-2+
 This program is free software; you can redistribute it and/or modify it
 under the terms of the GNU General Public License as published by the Free
 Software Foundation; either version 2 of the License, or (at your option)
 any later version.
 .
 This program is distributed in the hope that it will be useful, but WITHOUT
 ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 details.
 .
 On Debian systems, the complete text of the GNU General Public License
 version 2 can be found in "/usr/share/common-licenses/GPL-2".
EOF
    chmod 644 "$1"
}

changelog_file () {
    stamp=$(LC_ALL=C date -R)
    gzip -9 -n -c > "$1" <<EOF
convertall ($APP_VERSION-$PKG_REV) unstable; urgency=medium

  * Package generated from ConvertAll $APP_VERSION (build $BUILD_NUMBER).

 -- $MAINTAINER  $stamp
EOF
    chmod 644 "$1"
}

make_deb () {
    command -v dpkg-deb >/dev/null 2>&1 \
        || die "dpkg-deb is missing (install dpkg-dev)"
    new_workdir
    note "Building the Debian package"
    deb_name="convertall_${APP_VERSION}-${PKG_REV}_amd64"
    deb_root="$WORK/$deb_name"
    rm -rf "$deb_root"
    mkdir -p "$deb_root/DEBIAN" "$deb_root/opt/convertall" "$deb_root/usr/bin" \
        "$deb_root/usr/share/applications" "$deb_root/usr/share/icons" \
        "$deb_root/usr/share/metainfo" "$deb_root/usr/share/doc/convertall"
    cp -a "$BUNDLE"/. "$deb_root/opt/convertall/"
    cp -a "$PACKAGING/icons/hicolor" "$deb_root/usr/share/icons/"
    ln -sf /opt/convertall/convertall "$deb_root/usr/bin/convertall"
    desktop_file "$deb_root/usr/share/applications/convertall.desktop"
    appdata_file "$deb_root/usr/share/metainfo/org.bellz.convertall.appdata.xml"
    copyright_file "$deb_root/usr/share/doc/convertall/copyright"
    changelog_file "$deb_root/usr/share/doc/convertall/changelog.gz"
    installed_size=$(du -sk --exclude=DEBIAN "$deb_root" | cut -f 1)
    cat > "$deb_root/DEBIAN/control" <<EOF
Package: convertall
Version: $APP_VERSION-$PKG_REV
Architecture: amd64
Maintainer: $MAINTAINER
Installed-Size: $installed_size
Depends: libc6 (>= 2.31), libglib2.0-0 (>= 2.50), libgtk-3-0 (>= 3.24), libstdc++6 (>= 11)
Recommends: fonts-dejavu-core
Section: science
Priority: optional
Homepage: https://convertall.bellz.org/
Description: unit conversion tool
 ConvertAll converts between any units you can type, including combinations
 such as "ft * lbf / hr" or "m^3 / s", without being limited to the
 categories offered by the unit lists.
 .
 Units can be entered as names, abbreviations or symbols, a type filter
 narrows the unit list, and non-linear conversions (temperatures, gauges,
 decibels, ...) are handled natively.  Extra tools cover number bases and
 fractions, and the interface is also available in a dark theme.
EOF
    cat > "$deb_root/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if command -v update-desktop-database > /dev/null 2>&1; then
    update-desktop-database -q || true
fi
if command -v gtk-update-icon-cache > /dev/null 2>&1; then
    gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
fi
EOF
    cat > "$deb_root/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if command -v update-desktop-database > /dev/null 2>&1; then
    update-desktop-database -q || true
fi
EOF
    chmod 755 "$deb_root/DEBIAN/postinst" "$deb_root/DEBIAN/postrm"
    # -Zxz -z9: xz compression at its maximum level, which gives the smallest
    # .deb.  --root-owner-group stores every file as root:root, so no
    # fakeroot is needed to build the package as a normal user.
    mkdir -p "$OUT"
    dpkg-deb --root-owner-group -Zxz -z9 --build "$deb_root" \
        "$OUT/$deb_name.deb" || die "dpkg-deb failed"
    echo "Created $OUT/$deb_name.deb ($(du -h "$OUT/$deb_name.deb" | cut -f 1))"
}

find_appimagetool () {
    if [ -n "$APPIMAGETOOL" ]; then
        [ -x "$APPIMAGETOOL" ] \
            || die "appimagetool '$APPIMAGETOOL' was not found or is not
executable."
        return 0
    fi
    if command -v appimagetool >/dev/null 2>&1; then
        APPIMAGETOOL=$(command -v appimagetool)
        return 0
    fi
    APPIMAGETOOL="$ROOT/tools/appimagetool-x86_64.AppImage"
    if [ ! -x "$APPIMAGETOOL" ]; then
        command -v curl >/dev/null 2>&1 || die "curl is missing"
        note "Downloading appimagetool $APPIMAGETOOL_TAG"
        mkdir -p "$ROOT/tools"
        curl -fL -o "$APPIMAGETOOL" \
            "$APPIMAGETOOL_URL/$APPIMAGETOOL_TAG/appimagetool-x86_64.AppImage" \
            || die "Could not download appimagetool"
        chmod 755 "$APPIMAGETOOL"
    fi
}

run_appimagetool () {
    # AppImage type-2 files need libfuse, which Debian 12 does not install by
    # default; the runtime can instead extract itself to a temporary
    # directory and run from there.
    if ! ldconfig -p 2>/dev/null | grep -q 'libfuse\.so\.2'; then
        APPIMAGE_EXTRACT_AND_RUN=1
        export APPIMAGE_EXTRACT_AND_RUN
    fi
    "$@"
}

make_appimage () {
    find_appimagetool
    new_workdir
    note "Building the AppImage"
    appdir="$WORK/ConvertAll.AppDir"
    rm -rf "$appdir"
    mkdir -p "$appdir/usr/bin" "$appdir/usr/share/applications" \
        "$appdir/usr/share/icons" "$appdir/usr/share/metainfo"
    cp -a "$BUNDLE"/. "$appdir/usr/bin/"
    cp -a "$PACKAGING/icons/hicolor" "$appdir/usr/share/icons/"
    desktop_file "$appdir/convertall.desktop"
    cp -p "$appdir/convertall.desktop" \
        "$appdir/usr/share/applications/convertall.desktop"
    appdata_file "$appdir/usr/share/metainfo/org.bellz.convertall.appdata.xml"
    cp -p "$PACKAGING/icons/hicolor/256x256/apps/convertall.png" \
        "$appdir/convertall.png"
    cp -p "$PACKAGING/AppRun" "$appdir/AppRun"
    chmod 755 "$appdir/AppRun"
    # Reproducible packaging: date the squashfs image with the last commit.
    if [ -z "${SOURCE_DATE_EPOCH:-}" ] && [ -d "$ROOT/.git" ]; then
        SOURCE_DATE_EPOCH=$(git -C "$ROOT" log -1 --format=%ct 2>/dev/null) \
            || SOURCE_DATE_EPOCH=""
        [ -z "$SOURCE_DATE_EPOCH" ] || export SOURCE_DATE_EPOCH
    fi
    # zstd at its maximum compression level: far smaller than the default
    # AppImage compression and still fast to mount.  appimagetool already
    # selects a 128K block size for zstd, and rejects -Xbcj (an xz-only
    # option).
    mkdir -p "$OUT"
    run_appimagetool env ARCH=x86_64 "$APPIMAGETOOL" --comp zstd \
        --mksquashfs-opt -Xcompression-level --mksquashfs-opt 22 \
        "$appdir" "$OUT/convertall-$APP_VERSION-x86_64.AppImage" \
        || die "appimagetool failed (see the messages above)"
    echo "Created $OUT/convertall-$APP_VERSION-x86_64.AppImage ($(du -h \
"$OUT/convertall-$APP_VERSION-x86_64.AppImage" | cut -f 1))"
}

do_deps () {
    if [ "$(id -u)" != 0 ]; then
        die "'deps' must be run as sudo or root"
    fi
    command -v apt-get >/dev/null 2>&1 \
        || die "Only Debian-based systems are supported by 'deps' (apt-get
was not found).  Install binutils, curl, dpkg-dev and the Flutter Linux
build dependencies manually."
    echo "Detected 'apt-get' (Debian-based system)"
    apt-get -y install binutils curl dpkg-dev file gzip xz-utils zip unzip \
        clang cmake git libgtk-3-dev libglu1-mesa ninja-build pkgconf \
        libstdc++-12-dev liblzma-dev || die "Error installing dependencies"
}

case "${1:-}" in
    deps|bundle|deb|appimage|all) command=$1 ;;
    -h|--help|help)
        usage
        exit 0
        ;;
    *)
        usage 1>&2
        exit 1
        ;;
esac
shift

while [ $# -gt 0 ]; do
    case "$1" in
        --bundle)
            [ $# -ge 2 ] || die "--bundle needs a directory"
            BUNDLE=$2
            shift 2
            ;;
        --out)
            [ $# -ge 2 ] || die "--out needs a directory"
            OUT=$2
            shift 2
            ;;
        --appimagetool)
            [ $# -ge 2 ] || die "--appimagetool needs a path"
            APPIMAGETOOL=$2
            shift 2
            ;;
        --skip-build) SKIP_BUILD=1; shift ;;
        --obfuscate) OBFUSCATE=1; shift ;;
        --keep) KEEP=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown option '$1'" ;;
    esac
done

if [ "$command" = deps ]; then
    do_deps
    echo
    echo "Dependencies installed."
    echo
    exit 0
fi

check_arch
read_version
echo "ConvertAll $APP_VERSION (build $BUILD_NUMBER)"
if [ "$SKIP_BUILD" -eq 0 ]; then
    build_bundle
else
    echo "Reusing the existing release bundle"
fi
check_bundle
optimize_bundle

case "$command" in
    bundle)
        echo
        echo "Release bundle ready in $BUNDLE"
        ;;
    deb) make_deb ;;
    appimage) make_appimage ;;
    all)
        make_deb
        make_appimage
        ;;
esac

if [ "$command" = deb ] || [ "$command" = appimage ] || [ "$command" = all ]; then
    echo
    echo "Packages are in $OUT"
fi
