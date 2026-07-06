#!/bin/sh
#===============================================================================
# make-package.sh - build the xymon-systemdmon FreeBSD package (.pkg)
#
# Version:      0.1.0 (SemVer)
# License:      GPL-2.0
# Project:      xymon-systemdmon
#
# Description:
#   Runs ON A FREEBSD HOST. Expects to sit next to the stage/ tree
#   and the VERSION file produced by packaging/build-packages.sh
#   --freebsd (shipped together in the freebsd staging tarball).
#   Generates +MANIFEST and pkg-plist, then calls pkg create.
#
#   POSIX sh only - FreeBSD has no bash in the base system.
#
#   Config handling mimics the ports @sample keyword without needing
#   a ports tree: the package installs *.sample files; a
#   post-install script copies each to its real name if that does
#   not exist yet, and a pre-deinstall script removes the real file
#   only if it is still identical to the sample. pkg upgrades
#   therefore never clobber edited rules.
#
# Program flow:
#   1. Determine package ABI from pkg config (noarch: FreeBSD:N:*).
#   2. Generate pkg-plist from the stage/ tree.
#   3. Generate +MANIFEST including the sample-handling scripts.
#   4. pkg create -o . and print the result.
#
# Parameters (environment variable overrides):
#   PREFIX       package prefix          (default: /usr/local)
#
# Usage on the FreeBSD Xymon server:
#   tar xzf xymon-systemdmon-<version>-freebsd-staging.tar.gz
#   cd freebsd && ./make-package.sh
#   pkg add ./xymon-systemdmon-<version>.pkg
#===============================================================================

set -u

SCRIPTDIR="$(cd "$(dirname "$0")" && pwd)"
STAGE="$SCRIPTDIR/stage"
PREFIX="${PREFIX:-/usr/local}"

die() {
    echo "ERROR: $*" >&2
    exit 1
}

[ -d "$STAGE" ] || die "stage/ tree not found next to this script"
[ -f "$SCRIPTDIR/VERSION" ] || die "VERSION file not found next to this script"
command -v pkg >/dev/null 2>&1 || die "pkg(8) not found - run this on FreeBSD"

VERSION="$(cat "$SCRIPTDIR/VERSION")"

# noarch ABI: FreeBSD:<major>:*
ABI="$(pkg config ABI)" || die "pkg config ABI failed"
NOARCH_ABI="${ABI%:*}:*"

# locate the staged config samples (paths become absolute at install)
CFG_SAMPLE="$(cd "$STAGE" && find . -path '*/etc/systemdmon.cfg.sample' | head -1 | sed 's|^\.||')"
TASKS_SAMPLE="$(cd "$STAGE" && find . -path '*/tasks.d/systemdmon.cfg.sample' | head -1 | sed 's|^\.||')"
[ -n "$CFG_SAMPLE" ] || die "systemdmon.cfg.sample not found in stage tree"
[ -n "$TASKS_SAMPLE" ] || die "tasks.d/systemdmon.cfg.sample not found in stage tree"
CFG_REAL="${CFG_SAMPLE%.sample}"
TASKS_REAL="${TASKS_SAMPLE%.sample}"

# plist: all staged files with absolute paths
(cd "$STAGE" && find . -type f | sed 's|^\.||' | sort) > "$SCRIPTDIR/pkg-plist"

cat > "$SCRIPTDIR/+MANIFEST" <<EOF
name: xymon-systemdmon
version: "$VERSION"
origin: net-mgmt/xymon-systemdmon
comment: "systemd unit monitoring for Xymon (server worker + client collector)"
www: https://github.com/roemer2201/xymon-systemdmon
maintainer: r.oliver@web.de
prefix: $PREFIX
abi: "$NOARCH_ABI"
licenselogic: single
licenses: [GPLv2]
categories: [net-mgmt]
desc: <<EOD
systemd unit monitoring for the Xymon monitoring system.

On a FreeBSD Xymon server this package provides the xymond_systemd
channel worker, which evaluates the [local:systemd] sections reported
by Linux clients against the central rule file and generates the
"systemd" status column. The worker needs Perl 5 (core modules only):
pkg install perl5

The Linux client collector is included under
$PREFIX/share/examples/xymon-systemdmon/ for distribution to the
monitored Linux hosts (FreeBSD itself has no systemd).
EOD
scripts: {
  post-install: <<EOD
[ -f "$CFG_REAL" ] || cp -p "$CFG_SAMPLE" "$CFG_REAL"
[ -f "$TASKS_REAL" ] || cp -p "$TASKS_SAMPLE" "$TASKS_REAL"
EOD
  pre-deinstall: <<EOD
cmp -s "$CFG_REAL" "$CFG_SAMPLE" && rm -f "$CFG_REAL"
cmp -s "$TASKS_REAL" "$TASKS_SAMPLE" && rm -f "$TASKS_REAL"
exit 0
EOD
}
message: <<EOD
xymon-systemdmon: worker installed for the FreeBSD Xymon server.

1. Install Perl if not present:     pkg install perl5
2. Edit the rule file:              $CFG_REAL
3. The task snippet was placed at:  $TASKS_REAL
   The stock Xymon tasks.cfg includes the tasks.d directory; if you
   trimmed yours, append the [systemdmon] block manually.
4. Install the client collector from
   $PREFIX/share/examples/xymon-systemdmon/ on the monitored
   Linux hosts (see README.md).
EOD
EOF

pkg create -M "$SCRIPTDIR/+MANIFEST" -p "$SCRIPTDIR/pkg-plist" \
    -r "$STAGE" -o "$SCRIPTDIR" || die "pkg create failed"

echo "package built:"
ls -l "$SCRIPTDIR"/xymon-systemdmon-"$VERSION".pkg
echo "install with: pkg add $SCRIPTDIR/xymon-systemdmon-$VERSION.pkg"
exit 0
