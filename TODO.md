# TODO - xymon-systemdmon

## Repository skeleton

- [ ] Create directory layout (client/local, server/libexec, server/etc)
- [ ] Add LICENSE (GPL-2.0)
- [ ] Add CHANGELOG.md (keepachangelog style, SemVer)
- [ ] Write README.md: architecture overview (client collector ->
      [local:systemd] section -> xymond client channel -> worker ->
      svcs status column), installation for client and server,
      configuration reference

## Client collector (client/local/systemd)

- [ ] Collect unit state: systemctl list-units --type=service --all
      --plain --no-legend
- [ ] Collect failed units explicitly (systemctl list-units --failed)
- [ ] Decide on output format of the section (stable, parseable,
      version marker in first line for future format changes)
- [ ] Evaluate including timers and sockets (--type=timer,socket) as
      optional, off by default
- [ ] Verify behavior as unprivileged xymon user (no D-Bus session,
      read-only systemctl queries only)
- [ ] Apply script conventions (header, --help, ENV overrides, logger)

## Server worker (server/libexec/xymond_systemd)

- [ ] Choose implementation language (shell vs Python; worker is
      long-running on the client channel - probably Python)
- [ ] Parse xymond_channel client-channel framing and extract
      [local:systemd] section per host
- [ ] Rule engine: SVC rules with HOST=/CLASS=/PAGE= scoping,
      %PCRE patterns, expected state, color, min/max counts,
      TEXT= display name (analysis.cfg PROC semantics as template)
- [ ] Default behavior for failed units without explicit rule
      (yellow? configurable)
- [ ] Send status messages: column svcs, colors green/yellow/red/clear
      only, LIFETIME slightly above client poll interval
- [ ] SIGHUP handling: reload rule file without restart
- [ ] Config file: server/etc/systemdmon.cfg with commented examples

## Integration

- [ ] tasks.cfg snippet ([systemdmon] block, NEEDS xymond, LOGFILE)
- [ ] Verify whether Rocky/Terabithia RPM packaging includes a
      tasks.d/ directory from tasks.cfg (Debian/Ubuntu does); document
      both integration paths in README
- [ ] install.sh: detect client vs server installation, place files,
      ENV variable overrides for target paths, --help, dry-run mode
- [ ] Document alerts.cfg examples for the svcs column
- [ ] Optional: RRD tracking of unit counts (TRACK-like), graphs.cfg
      example

## Testing

- [ ] Test client collector on Rocky Linux (cluster nodes) and Ubuntu
- [ ] Test worker against Xymon 4.3.30 server
- [ ] Test scoping precedence (HOST over CLASS over default)
- [ ] Ghost/edge cases: host without [local:systemd] section must not
      produce a column at all
