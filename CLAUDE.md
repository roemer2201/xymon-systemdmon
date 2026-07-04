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
   file and sends `status` messages for a new column named `systemd`.

## Key architecture decisions (do not change without discussion)

- **Follow the native Xymon model** (as with the `procs` column):
  the client reports the state of ALL systemd units unfiltered
  (`systemctl list-units --all --plain --no-legend` for the types
  service, timer, socket, mount, automount, swap, path - deliberately
  excluding target, device, slice, scope as noise without a useful
  failure notion - plus the failed-unit list WITHOUT type filter, so
  failed service runs of timer jobs stay visible, plus the overall
  `systemctl is-system-running` state). Which units are checked and
  with which severity is decided EXCLUSIVELY on the server.
- **Collector output format is a versioned contract**: first line
  `systemdmon v1`, subsections marked with `## <name>` lines
  (systemstate/units/failed). Lines inside the section MUST NEVER
  start with `[` - xymond would treat them as a new message section
  (the `[local:<basename>]` marker itself is emitted by
  client/xymonclient.sh, verified in 4.3.30).
- **Rules match the full unit name including suffix**
  (`sshd.service`, `backup.timer`, `data.mount`); there is no
  type-specific rule syntax.
- **Languages**: client collector and install.sh are pure bash (no
  new dependencies on clients). The server worker is Perl 5 with core
  modules only - decided because the `%` rule patterns require PCRE
  (bash only has ERE) and a long-running channel worker cannot fork a
  grep per pattern match. Perl is the traditional Xymon extension
  language and is only needed on the Xymon server host.
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
tests/
  fixtures/              sample client-channel streams for offline tests
  run-tests.sh           offline test driver (uses xymond_systemd --test)
  MANUAL-TESTING.md      checklist for tests on real systems
install.sh               installer (client/server detection, dry-run)
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
- Git: Claude commits directly to `main` (user decision 2026-07,
  replaces the earlier `claude`-branch convention). `.gitignore`
  contains `.claude/`.
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
- Client-channel framing as delivered to a worker on stdin (verified
  in xymond.c `posttochannel`/`handle_client` and xymond_worker.c of
  4.3.30): each message starts with the header line
  `@@client#SEQ/HOSTNAME|timestamp|sender|hostname|clientos|class|collectorid`,
  followed by the full client message, terminated by a line containing
  only `@@`. Control messages a worker must handle: `@@shutdown`
  (exit), `@@logrotate` (reopen the logfile named in
  $XYMONCHANNEL_LOGFILENAME), `@@idle`, `@@reload` (hosts.cfg changed);
  see xymond_sample.c.
- In `status` messages the hostname is sent with dots replaced by
  commas (`status+LIFETIME host,domain,com.systemd COLOR ...`).
