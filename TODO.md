# TODO - xymon-systemdmon

## Repository skeleton

- [x] Create directory layout (client/local, server/libexec, server/etc)
- [x] Add LICENSE (GPL-2.0)
- [x] Add CHANGELOG.md (keepachangelog style, SemVer)
- [x] Write README.md: architecture overview (client collector ->
      [local:systemd] section -> xymond client channel -> worker ->
      systemd status column), installation for client and server,
      configuration reference

## Client collector (client/local/systemd)

- [x] Collect unit state: systemctl list-units --all --plain
      --full --no-legend for the types
      service,timer,socket,mount,automount,swap,path
- [x] Collect failed units explicitly, WITHOUT type filter (keeps
      failed service runs of timer jobs visible)
- [x] Output format: versioned contract (first line "systemdmon v1",
      "##"-prefixed subsections systemstate/units/failed; no line may
      start with "[")
- [x] Timers/sockets/mounts included by default; type list adjustable
      via SYSTEMDMON_TYPES (decision 2026-07: server-side filtering
      makes client-side type toggles unnecessary)
- [x] Include overall "systemctl is-system-running" state
      (SYSTEMDMON_SYSTEMSTATE=0 to disable)
- [x] Apply script conventions (header, --help, ENV overrides, logger)
- [ ] Verify behavior as unprivileged xymon user on a REAL host
      (read-only systemctl only, no D-Bus session) - see
      tests/MANUAL-TESTING.md section 1

## Server worker (server/libexec/xymond_systemd)

- [x] Implementation language decided: Perl 5, core modules only
      (PCRE needed for % rules, long-running channel worker; bash
      would need a grep -P fork per match). Collector and install.sh
      stay bash.
- [x] Parse xymond_channel client-channel framing (verified against
      4.3.30 sources) and extract [local:systemd] per host; handle
      @@shutdown/@@logrotate/@@idle/@@reload control messages
- [x] Rule engine: SVC rules with HOST=/CLASS=/PAGE= scoping,
      %PCRE patterns, expected state (ACTIVE or ACTIVE/SUB), color,
      MIN=/MAX= counts, TEXT= display name; precedence HOST > CLASS >
      PAGE > global with override semantics per unit
- [x] Default behavior for failed units without explicit rule:
      yellow, configurable via DEFAULTFAILED (red|yellow|clear|ignore),
      exemptions via IGNORE
- [x] SYSTEMSTATE directive for degraded system state (default yellow)
- [x] Send status messages: column "systemd", colors
      green/yellow/red/clear only, configurable LIFETIME (default 10m)
- [x] SIGHUP handling: reload rule file without restart (plus
      automatic reload on mtime change)
- [x] Config file: server/etc/systemdmon.cfg with commented examples
- [ ] PAGE= map: hosts.cfg parser is best-effort (page/subpage/
      subparent, include followed; "directory" not). Revisit if real
      hosts.cfg layouts need more.

## Integration

- [x] tasks.cfg snippet ([systemdmon] block, NEEDS xymond, LOGFILE)
- [x] install.sh: detect client vs server installation, place files,
      ENV variable overrides for target paths, --help, dry-run mode
- [x] Document alerts.cfg examples for the systemd column (README)
- [x] Packaging: build a single xymon-systemdmon package (client and
      server files together, hobbit-plugins style; user decision
      2026-07) as .deb and .rpm (packaging/build-packages.sh,
      packaging/xymon-systemdmon.spec; config files marked
      conffiles / %config(noreplace))
- [ ] Verify whether Rocky/Terabithia RPM packaging includes a
      tasks.d/ directory from tasks.cfg (Debian/Ubuntu does); update
      README and tasks-snippet.cfg comments with the result, and set
      the RPM default paths (xymon_home/xymon_clienthome in the spec)
      to the verified Terabithia layout
- [ ] Optional: RRD tracking of unit counts (TRACK-like), graphs.cfg
      example (deliberately deferred, not part of 0.1.0)

## Testing

- [x] Offline tests: fixtures + tests/run-tests.sh cover scoping
      precedence (HOST over CLASS over PAGE over global), PCRE rules,
      MIN/MAX count checks, DEFAULTFAILED/IGNORE, SYSTEMSTATE, comma
      hostname syntax, and the ghost case (host without
      [local:systemd] section produces no column)
- [ ] Test client collector on Rocky Linux (cluster nodes) and Ubuntu
      (tests/MANUAL-TESTING.md)
- [ ] Test worker against Xymon 4.3.30 server (tests/MANUAL-TESTING.md)
