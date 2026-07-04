#!/bin/bash
#===============================================================================
# run-tests.sh - offline tests for the xymond_systemd channel worker
#
# Version:      0.1.0 (SemVer)
# License:      GPL-2.0
# Project:      xymon-systemdmon
#
# Description:
#   Feeds a canned client-channel stream (tests/fixtures/) into
#   "xymond_systemd --test" and asserts the resulting status messages.
#   Covers: scoping precedence (HOST over CLASS over PAGE over
#   global), PCRE rules, count checks (MIN/MAX), DEFAULTFAILED,
#   IGNORE, SYSTEMSTATE, ghost case (host without [local:systemd]
#   section must not produce any status).
#
# Program flow:
#   1. Run the worker in --test mode against the fixtures.
#   2. Assert expected/forbidden content in the output.
#   3. Exit 0 if all assertions hold, 1 otherwise.
#
# Parameters (environment variable overrides):
#   SYSTEMDMON_WORKER   path to the worker
#                       (default: ../server/libexec/xymond_systemd)
#   SYSTEMDMON_VERBOSE  1 = print worker stderr log (default: 0)
#===============================================================================

set -u

TESTDIR="$(cd "$(dirname "$0")" && pwd)"
WORKER="${SYSTEMDMON_WORKER:-$TESTDIR/../server/libexec/xymond_systemd}"
FIXTURES="$TESTDIR/fixtures"
VERBOSE="${SYSTEMDMON_VERBOSE:-0}"

FAILED=0
PASSED=0

OUTPUT="$(SYSTEMDMON_HOSTSCFG="$FIXTURES/hosts.cfg" \
    "$WORKER" --test \
    --config="$FIXTURES/systemdmon-test.cfg" \
    "$FIXTURES/client-stream.txt" 2>"$TESTDIR/.stderr.log")"
RC=$?

if [ "$VERBOSE" = "1" ]; then
    cat "$TESTDIR/.stderr.log" >&2
fi

if [ $RC -ne 0 ]; then
    echo "FAIL: worker exited with $RC" >&2
    cat "$TESTDIR/.stderr.log" >&2
    exit 1
fi

assert_contains() {
    # assert_contains <description> <grep-pattern>
    if printf '%s\n' "$OUTPUT" | grep -qE -- "$2"; then
        PASSED=$((PASSED + 1))
        echo "ok:   $1"
    else
        FAILED=$((FAILED + 1))
        echo "FAIL: $1 (pattern not found: $2)" >&2
    fi
}

assert_missing() {
    # assert_missing <description> <grep-pattern>
    if printf '%s\n' "$OUTPUT" | grep -qE -- "$2"; then
        FAILED=$((FAILED + 1))
        echo "FAIL: $1 (forbidden pattern found: $2)" >&2
    else
        PASSED=$((PASSED + 1))
        echo "ok:   $1"
    fi
}

# --- number of statuses: web1, db1, ok1 - but NOT ghost -----------------------
COUNT=$(printf '%s\n' "$OUTPUT" | grep -c '^### BEGIN STATUS')
if [ "$COUNT" = "3" ]; then
    PASSED=$((PASSED + 1)); echo "ok:   exactly 3 status messages"
else
    FAILED=$((FAILED + 1)); echo "FAIL: expected 3 status messages, got $COUNT" >&2
fi
assert_missing "ghost host produces no status" "ghost"

# --- web1: HOST rule beats CLASS rule (cron red, not yellow) ------------------
assert_contains "web1 status is red"                 "host=web1\.example\.com color=red"
assert_contains "web1 status line uses comma syntax" "status\+10 web1,example,com\.systemd red"
assert_contains "web1 cron red via HOST rule"        "&red cron\.service - inactive \(dead\) - expected active"
assert_missing  "web1 cron not yellow (CLASS beaten)" "&yellow cron\.service"
assert_contains "web1 nginx green"                   "&green nginx\.service - active \(running\)"
assert_contains "web1 sshd green (global rule)"      "&green sshd\.service - active \(running\)"
assert_contains "web1 getty count ok"                "&green gettys - 1 unit\(s\) active \(min=1 max=1\)"
assert_missing  "web1 failed user@ unit ignored"     "user@1000\.service - failed"

# --- db1: PAGE rule, DEFAULTFAILED, SYSTEMSTATE, MAX violation ----------------
assert_contains "db1 status is yellow"               "host=db1\.example\.com color=yellow"
assert_contains "db1 node_exporter missing via PAGE" "&yellow node_exporter\.service - no matching unit reported - expected active"
assert_contains "db1 cron green via CLASS rule"      "&green cron\.service - active \(running\)"
assert_contains "db1 unruled failed unit yellow"     "&yellow apt-daily\.service - failed \(no explicit rule, DEFAULTFAILED\)"
assert_contains "db1 degraded system state yellow"   "&yellow system state: degraded"
assert_contains "db1 getty count violation (MAX=1)"  "&yellow gettys - 2 unit\(s\) active \(min=1 max=1\)"

# --- ok1: everything green ----------------------------------------------------
assert_contains "ok1 status is green"                "host=ok1\.example\.com color=green"
assert_contains "ok1 running system state green"     "&green system state: running"

echo ""
echo "passed: $PASSED, failed: $FAILED"
rm -f "$TESTDIR/.stderr.log"
[ $FAILED -eq 0 ] || exit 1
exit 0
