#!/bin/bash
#===============================================================================
# build-packages.sh - build .deb and .rpm packages for xymon-systemdmon
#
# Version:      0.1.0 (SemVer)
# License:      GPL-2.0
# Project:      xymon-systemdmon
#
# Description:
#   Builds the binary package
#     xymon-systemdmon  (client collector AND server worker + config)
#   as .deb (via dpkg-deb) and/or .rpm (via rpmbuild, using
#   packaging/xymon-systemdmon.spec). Output goes to dist/.
#
#   Client and server files ship in ONE package, modeled on the
#   Debian "hobbit-plugins" package: unused server files on a client
#   host are harmless, and one package keeps deployment simple.
#
#   The package is noarch/all. Installation paths follow the Debian
#   xymon packaging layout by default
#   (/usr/lib/xymon/{client,server}, /etc/xymon); override via the
#   environment variables below for other layouts (the Terabithia
#   RPM layout is not yet verified, see TODO.md).
#
# Program flow:
#   1. Parse options (--deb, --rpm, --all, --help, --version).
#   2. Stage the file trees in a temporary directory.
#   3. Build the requested package formats into dist/.
#   4. Print the resulting package contents for verification.
#
# Parameters (environment variable overrides):
#   PKG_VERSION        package version        (default: 0.1.0)
#   PKG_RELEASE        package release        (default: 1)
#   XYMON_HOME         server home in packages (default: /usr/lib/xymon/server)
#   XYMON_CLIENTHOME   client home in packages (default: /usr/lib/xymon/client)
#   PKG_MAINTAINER     maintainer string
#                      (default: "roemer2201 <r.oliver@web.de>")
#   SYSTEMDMON_VERBOSE 1 = also log via logger (default: 0)
#
# Requirements: dpkg-deb for --deb, rpmbuild for --rpm.
#===============================================================================

set -u

VERSION="0.1.0"

PKG_VERSION="${PKG_VERSION:-0.1.0}"
PKG_RELEASE="${PKG_RELEASE:-1}"
XYMON_HOME="${XYMON_HOME:-/usr/lib/xymon/server}"
XYMON_CLIENTHOME="${XYMON_CLIENTHOME:-/usr/lib/xymon/client}"
PKG_MAINTAINER="${PKG_MAINTAINER:-roemer2201 <r.oliver@web.de>}"
SYSTEMDMON_VERBOSE="${SYSTEMDMON_VERBOSE:-0}"

SRCDIR="$(cd "$(dirname "$0")/.." && pwd)"
DISTDIR="$SRCDIR/dist"

DO_DEB=0
DO_RPM=0

usage() {
    cat <<EOF
Usage: build-packages.sh [--deb] [--rpm] [--all] [--help] [--version]

Builds the xymon-systemdmon package (client collector and server
worker in one package) into dist/.

  --deb       build .deb packages (needs dpkg-deb)
  --rpm       build .rpm packages (needs rpmbuild)
  --all       both (default if no option is given)
  --help      this text
  --version   print version

Environment overrides: PKG_VERSION, PKG_RELEASE, XYMON_HOME,
XYMON_CLIENTHOME, PKG_MAINTAINER
EOF
}

log() {
    echo "$@"
    if [ "$SYSTEMDMON_VERBOSE" = "1" ]; then
        logger -t systemdmon-build -- "$@" 2>/dev/null
    fi
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --deb)     DO_DEB=1 ;;
        --rpm)     DO_RPM=1 ;;
        --all)     DO_DEB=1; DO_RPM=1 ;;
        --help|-h) usage; exit 0 ;;
        --version) echo "build-packages.sh (xymon-systemdmon) $VERSION"; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done
if [ "$DO_DEB" = "0" ] && [ "$DO_RPM" = "0" ]; then
    DO_DEB=1
    DO_RPM=1
fi

WORKDIR="$(mktemp -d)" || die "mktemp failed"
trap 'rm -rf "$WORKDIR"' EXIT
mkdir -p "$DISTDIR"

#--- deb ------------------------------------------------------------------------

write_copyright() {
    # minimal machine-readable copyright file
    cat > "$1" <<EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: xymon-systemdmon
Source: https://github.com/roemer2201/xymon-systemdmon

Files: *
Copyright: 2026 roemer2201
License: GPL-2
 This package is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License version 2 as
 published by the Free Software Foundation.
 .
 On Debian systems, the complete text of the GNU General Public
 License version 2 can be found in "/usr/share/common-licenses/GPL-2".
EOF
}

build_deb() {
    command -v dpkg-deb >/dev/null 2>&1 || die "dpkg-deb not found"
    local pkg="xymon-systemdmon"
    local root="$WORKDIR/deb"

    install -D -m 755 "$SRCDIR/client/local/systemd" \
        "$root$XYMON_CLIENTHOME/local/systemd"
    install -D -m 755 "$SRCDIR/server/libexec/xymond_systemd" \
        "$root$XYMON_HOME/libexec/xymond_systemd"
    install -D -m 644 "$SRCDIR/server/etc/systemdmon.cfg" \
        "$root/etc/xymon/systemdmon.cfg"
    install -D -m 644 "$SRCDIR/server/etc/tasks-snippet.cfg" \
        "$root/etc/xymon/tasks.d/systemdmon.cfg"
    install -d -m 755 "$root/usr/share/doc/$pkg"
    write_copyright "$root/usr/share/doc/$pkg/copyright"
    install -m 644 "$SRCDIR/README.md" "$root/usr/share/doc/$pkg/README.md"
    install -d -m 755 "$root/DEBIAN"
    # Depends note: perl-base is Essential on Debian and contains all
    # modules the server worker uses (Getopt::Long, POSIX,
    # File::Basename), so listing it costs clients nothing. Depend on
    # xymon-client (like hobbit-plugins does), not on the xymon
    # server package: the collector is useful on every host, the
    # worker files are simply inert where no server runs.
    cat > "$root/DEBIAN/control" <<EOF
Package: $pkg
Version: $PKG_VERSION-$PKG_RELEASE
Section: net
Priority: optional
Architecture: all
Depends: bash, perl-base, xymon-client
Maintainer: $PKG_MAINTAINER
Homepage: https://github.com/roemer2201/xymon-systemdmon
Description: systemd unit monitoring for Xymon
 Client collector and server channel worker in one package (like
 hobbit-plugins; unused server files on client hosts are harmless).
 .
 The collector reports all systemd units (service, timer, socket,
 mount, automount, swap, path), the failed-unit list and the overall
 system state as a [local:systemd] client message section. On the
 Xymon server the xymond_systemd channel worker evaluates the
 central rule file /etc/xymon/systemdmon.cfg against these sections
 and generates the "systemd" status column. The xymonlaunch task
 snippet is installed as /etc/xymon/tasks.d/systemdmon.cfg (included
 automatically by the Debian xymon package's tasks.cfg).
EOF
    cat > "$root/DEBIAN/conffiles" <<EOF
/etc/xymon/systemdmon.cfg
/etc/xymon/tasks.d/systemdmon.cfg
EOF
    dpkg-deb --build --root-owner-group "$root" \
        "$DISTDIR/${pkg}_${PKG_VERSION}-${PKG_RELEASE}_all.deb" >/dev/null \
        || die "dpkg-deb failed for $pkg"
    log "built: dist/${pkg}_${PKG_VERSION}-${PKG_RELEASE}_all.deb"
}

#--- rpm ------------------------------------------------------------------------

build_rpm() {
    command -v rpmbuild >/dev/null 2>&1 || die "rpmbuild not found"
    local topdir="$WORKDIR/rpmbuild"
    mkdir -p "$topdir"
    rpmbuild -bb "$SRCDIR/packaging/xymon-systemdmon.spec" \
        --define "_topdir $topdir" \
        --define "srcdir $SRCDIR" \
        --define "pkgver $PKG_VERSION" \
        --define "pkgrel $PKG_RELEASE" \
        --define "xymon_home $XYMON_HOME" \
        --define "xymon_clienthome $XYMON_CLIENTHOME" \
        --quiet || die "rpmbuild failed"
    local f
    for f in "$topdir"/RPMS/noarch/*.rpm; do
        [ -f "$f" ] || die "rpmbuild produced no packages"
        cp "$f" "$DISTDIR/"
        log "built: dist/$(basename "$f")"
    done
}

#--- main -----------------------------------------------------------------------

[ "$DO_DEB" = "1" ] && build_deb
[ "$DO_RPM" = "1" ] && build_rpm

log ""
log "package contents:"
for f in "$DISTDIR"/*_"${PKG_VERSION}-${PKG_RELEASE}"_all.deb; do
    [ -f "$f" ] || continue
    log "--- $(basename "$f")"
    dpkg-deb --contents "$f" | awk '{print "    " $1 " " $6}'
done
if command -v rpm >/dev/null 2>&1; then
    for f in "$DISTDIR"/*-"${PKG_VERSION}-${PKG_RELEASE}".noarch.rpm; do
        [ -f "$f" ] || continue
        log "--- $(basename "$f")"
        rpm -qlp "$f" 2>/dev/null | sed 's/^/    /'
    done
fi
exit 0
