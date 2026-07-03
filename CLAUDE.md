# CLAUDE.md - Project context for xymon-systemdmon

## What this project is

systemd unit monitoring for the Xymon monitoring system, consisting of:

1. A **client-side collector**: a small script placed in
   `$XYMONCLIENTHOME/local/` on monitored hosts. The Xymon client
   executes all executable files in that directory and appends their
   output to the client message as a separate `[local:<name>]` section.
   No status column is generated on the client side.
2. A **server-side channel worker** (`xymond_systemd`): attached to the
   xymond `client` channel via `xymond_channel --channel=client` (entry
   in `tasks.cfg`). It receives every incoming client message, parses
   the `[local:systemd]` section, evaluates it against a central rule
   file and sends `status` messages for a new column (working name:
   `svcs`).

## Key architecture decisions (do not change without discussion)

- **Follow the native Xymon model** (as with the `procs` column):
  the client reports the state of ALL systemd units unfiltered
  (`systemctl list-units --type=service --all --plain --no-legend`,
  plus failed units). Which units are checked and with which severity
  is decided EXCLUSIVELY on the server.
- **All configuration lives on the Xymon server** in a single rule
  file (working name: `server/etc/systemdmon.cfg`) using the
  analysis.cfg style: `HOST=` / `CLASS=` / `PAGE=` scoping lines
  followed by rules, e.g. `SVC sshd.service active red`. PCRE patterns
  with `%` prefix, analogous to `PROC` rules.
- **No client-side configuration.** Data volume of a full unit listing
  is small (a few KB); server-side filtering keeps all logic in one
  place. Documented fallbacks, should filtering ever become necessary:
  custom free-form directives in `client-local.cfg` (its format is
  explicitly defined by the tools consuming it) or config download via
  the `config FILENAME` protocol command (fetches files from
  `$XYMONHOME/etc/` on the server).
- **No patching of Xymon itself.** Everything is add-on only:
  `xymond_channel` is the documented generic mechanism for server-side
  workers; the `local/` directory is the documented client extension
  point for raw data sections (see client README-local: output is NOT
  processed by default on the server, which is exactly why the worker
  exists). Extension scripts that generate a status column directly
  would belong in `client/ext/` instead - deliberately NOT used here.
- Status messages sent by the worker use colors green/yellow/red/clear
  only (never blue/purple), with a LIFETIME slightly above the client
  poll interval.

## Repository layout

```
client/
  local/
    systemd              collector -> $XYMONCLIENTHOME/local/systemd
server/
  libexec/
    xymond_systemd       channel worker -> $XYMONHOME/libexec/
  etc/
    systemdmon.cfg       rule file example -> $XYMONHOME/etc/
    tasks-snippet.cfg    [systemdmon] block for tasks.cfg or tasks.d/
README.md
LICENSE                  GPL-2.0 (matches the Xymon ecosystem)
CHANGELOG.md
TODO.md
CLAUDE.md                this file
```

The layout deliberately mirrors Xymon installation paths so that
integration means copying/symlinking files into place. Target
platforms: Rocky Linux (EPEL/Terabithia RPMs) and Debian/Ubuntu
packages. Note: Debian/Ubuntu include `/etc/xymon/tasks.d/` from
tasks.cfg; whether the Rocky/Terabithia packages do the same is still
unverified (see TODO).

## Conventions

- Shell scripts follow the personal script conventions skill:
  header documentation with SemVer, program flow plan, `--help`,
  silent/verbose modes, parameters via environment variable overrides,
  logging via `logger` (syslog/journal).
- ASCII only in all code and scripts, no Unicode symbol characters.
- Code and technical documentation in English.
- Git: all Claude changes go into a branch named `claude`; before
  changing anything, update it from `main`. `.gitignore` contains
  `.claude/` and was committed first.
- Well-researched answers only: claims about Xymon behavior must be
  backed by documentation (man pages: client-local.cfg(5),
  analysis.cfg(5), xymond(8), xymond_channel(8), xymon(1), tasks.cfg(5),
  client README-local). Flag assumptions explicitly.

## Reference: relevant Xymon facts (verified against docs)

- Client message sections from `local/` scripts appear as
  `[local:<scriptname>]`; server does no default processing.
- `client-local.cfg` matching order on xymond: hostname first, then
  class, then OS; `--merge-clientlocal` merges all matching sections.
- `config FILENAME` protocol command retrieves files from
  `$XYMONHOME/etc/` on the server (semi-automatic client config).
- Server modules attach via shared-memory channels; the `client`
  channel carries full client messages. Workers are started from
  `tasks.cfg` by xymonlaunch.
- Current stable Xymon: 4.3.30 (2019), TCP port 1984, GPL v2.
