#!/bin/bash
#===============================================================================
# install.sh - installer for xymon-systemdmon
#
# Version:      0.1.0 (SemVer)
# License:      GPL-2.0
# Project:      xymon-systemdmon
#
# Description:
#   Installs the client collector and/or the server-side channel
#   worker into an existing Xymon installation by copying the files
#   from this repository into the Xymon directory tree.
#
#   Client part:  client/local/systemd  -> $XYMONCLIENTHOME/local/
#   Server part:  server/libexec/xymond_systemd -> $XYMONHOME/libexec/
#                 server/etc/systemdmon.cfg     -> $XYMONHOME/etc/
#                                                  (never overwritten)
#                 server/etc/tasks-snippet.cfg  -> tasks.d/systemdmon.cfg
#                                                  if a tasks.d directory
#                                                  exists, otherwise manual
#                                                  instructions are printed
#
# Program flow:
#   1. Parse options (--client/--server/--auto, --dry-run, --help).
#   2. Detect or take from environment the Xymon client/server homes.
#   3. Copy files (or print what would be done in dry-run mode).
#   4. Print follow-up instructions (tasks.cfg, reload).
#
# Parameters (environment variable overrides):
#   XYMONCLIENTHOME   Xymon client home (contains local/). If unset,
#                     common packaging paths are probed.
#   XYMONHOME         Xymon server home (contains libexec/, etc/).
#                     If unset, common packaging paths are probed.
#   SYSTEMDMON_TASKSD tasks.d directory for the snippet. If unset,
#                     common packaging paths are probed.
#   SYSTEMDMON_VERBOSE 1 = also log via logger (default: 0)
#===============================================================================

set -u

VERSION="0.1.0"
SRCDIR="$(cd "$(dirname "$0")" && pwd)"

MODE="auto"
DRYRUN=0
SYSTEMDMON_VERBOSE="${SYSTEMDMON_VERBOSE:-0}"

usage() {
    cat <<EOF
Usage: install.sh [--client|--server|--auto] [--dry-run] [--help] [--version]

Installs xymon-systemdmon into an existing Xymon installation.

  --client    install only the client collector
  --server    install only the server worker + config
  --auto      detect what this host is (default): server if a xymond
              binary is found, client if a Xymon client home is found;
              both parts are installed if both are detected
  --dry-run   only print what would be done
  --help      this text
  --version   print version

Environment overrides: XYMONCLIENTHOME, XYMONHOME, SYSTEMDMON_TASKSD
EOF
}

log() {
    echo "$@"
    if [ "$SYSTEMDMON_VERBOSE" = "1" ]; then
        logger -t systemdmon-install -- "$@" 2>/dev/null
    fi
}

run() {
    if [ "$DRYRUN" = "1" ]; then
        echo "DRY-RUN: $*"
    else
        "$@"
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        --client)  MODE="client" ;;
        --server)  MODE="server" ;;
        --auto)    MODE="auto" ;;
        --dry-run) DRYRUN=1 ;;
        --help|-h) usage; exit 0 ;;
        --version) echo "install.sh (xymon-systemdmon) $VERSION"; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

# --- detection ----------------------------------------------------------------

find_clienthome() {
    if [ -n "${XYMONCLIENTHOME:-}" ]; then
        echo "$XYMONCLIENTHOME"
        return 0
    fi
    # Common packaging paths (Debian/Ubuntu, source install, RPM);
    # adjust via XYMONCLIENTHOME if yours differs.
    local d
    for d in /usr/lib/xymon/client /opt/xymon/client /usr/local/xymon/client \
             /home/xymon/client /usr/share/xymon-client; do
        if [ -d "$d/local" ] || [ -f "$d/etc/clientlaunch.cfg" ]; then
            echo "$d"
            return 0
        fi
    done
    return 1
}

find_serverhome() {
    if [ -n "${XYMONHOME:-}" ]; then
        echo "$XYMONHOME"
        return 0
    fi
    local d
    for d in /usr/lib/xymon/server /opt/xymon/server /usr/local/xymon/server \
             /home/xymon/server /usr/share/xymon; do
        if [ -x "$d/bin/xymond" ] || [ -d "$d/libexec" ]; then
            echo "$d"
            return 0
        fi
    done
    return 1
}

find_tasksd() {
    if [ -n "${SYSTEMDMON_TASKSD:-}" ]; then
        echo "$SYSTEMDMON_TASKSD"
        return 0
    fi
    local d
    for d in /etc/xymon/tasks.d "$1/etc/tasks.d"; do
        if [ -d "$d" ]; then
            echo "$d"
            return 0
        fi
    done
    return 1
}

# --- installation -------------------------------------------------------------

install_client() {
    local home
    if ! home="$(find_clienthome)"; then
        log "ERROR: no Xymon client home found - set XYMONCLIENTHOME" >&2
        return 1
    fi
    log "client: installing collector into $home/local/"
    run install -d -m 755 "$home/local"
    run install -m 755 "$SRCDIR/client/local/systemd" "$home/local/systemd"
    log "client: done. The next client run reports a [local:systemd] section."
    return 0
}

install_server() {
    local home tasksd
    if ! home="$(find_serverhome)"; then
        log "ERROR: no Xymon server home found - set XYMONHOME" >&2
        return 1
    fi
    log "server: installing worker into $home/libexec/"
    run install -d -m 755 "$home/libexec"
    run install -m 755 "$SRCDIR/server/libexec/xymond_systemd" "$home/libexec/xymond_systemd"

    if [ -f "$home/etc/systemdmon.cfg" ]; then
        log "server: $home/etc/systemdmon.cfg exists - NOT overwritten"
    else
        run install -m 644 "$SRCDIR/server/etc/systemdmon.cfg" "$home/etc/systemdmon.cfg"
    fi

    if tasksd="$(find_tasksd "$home")"; then
        if [ -f "$tasksd/systemdmon.cfg" ]; then
            log "server: $tasksd/systemdmon.cfg exists - NOT overwritten"
        else
            run install -m 644 "$SRCDIR/server/etc/tasks-snippet.cfg" "$tasksd/systemdmon.cfg"
            log "server: task snippet installed to $tasksd/systemdmon.cfg"
        fi
        log "server: xymonlaunch picks up the new task automatically."
    else
        log "server: no tasks.d directory found."
        log "server: append the [systemdmon] block from"
        log "server:   $SRCDIR/server/etc/tasks-snippet.cfg"
        log "server: to $home/etc/tasks.cfg manually."
    fi
    log "server: edit $home/etc/systemdmon.cfg to define rules (reload: SIGHUP or save)."
    return 0
}

# --- main ---------------------------------------------------------------------

rc=0
case "$MODE" in
    client)
        install_client || rc=1
        ;;
    server)
        install_server || rc=1
        ;;
    auto)
        did=0
        if find_serverhome >/dev/null; then
            install_server || rc=1
            did=1
        fi
        if find_clienthome >/dev/null; then
            install_client || rc=1
            did=1
        fi
        if [ "$did" = "0" ]; then
            log "ERROR: neither a Xymon server nor a client installation found." >&2
            log "Set XYMONHOME and/or XYMONCLIENTHOME, or use --client/--server." >&2
            rc=1
        fi
        ;;
esac
exit $rc
