# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-07-04

### Added

- Client collector `client/local/systemd` (bash): reports all systemd
  units of the types service, timer, socket, mount, automount, swap and
  path in a versioned, parseable format (`systemdmon v1`), plus the
  complete failed-unit list without type filter and the overall
  `systemctl is-system-running` state. No client-side filtering.
- Server channel worker `server/libexec/xymond_systemd` (Perl 5, core
  modules only): attaches to the xymond `client` channel via
  `xymond_channel`, parses the `[local:systemd]` section, evaluates it
  against a central rule file and sends `status` messages for the
  `systemd` column (colors green/yellow/red/clear only).
- Rule file `server/etc/systemdmon.cfg` with commented examples:
  `HOST=`/`CLASS=`/`PAGE=` scoping, `SVC` rules with `%` PCRE patterns,
  expected state, color, `MIN=`/`MAX=` counts, `TEXT=` display names,
  `DEFAULTFAILED` and `IGNORE` directives.
- `server/etc/tasks-snippet.cfg`: `[systemdmon]` block for tasks.cfg
  or tasks.d/.
- `install.sh`: client/server detection, dry-run mode, target paths
  overridable via environment variables.
- Offline test mode (`xymond_systemd --test`) plus test fixtures and
  `tests/run-tests.sh`; manual test guide in `tests/MANUAL-TESTING.md`.
- Documentation: README with architecture overview, installation and
  configuration reference; GPL-2.0 license.
