# xymon-systemdmon

systemd unit monitoring for the [Xymon](https://xymon.sourceforge.io/)
monitoring system: a client-side collector plus a server-side channel
worker that together provide a `systemd` status column for services,
timers, sockets, mounts and more - with all rules kept centrally on
the Xymon server.

Licensed under GPL-2.0, matching the Xymon ecosystem. Developed
against Xymon 4.3.30.

## Architecture

The add-on follows the native Xymon model (compare the `procs`
column): the client reports raw data, the server decides what to
check and how severe a deviation is.

```
monitored host                          Xymon server
+---------------------------+           +----------------------------------+
| $XYMONCLIENTHOME/local/   |           |  xymond                          |
|   systemd  (collector)    |           |    | "client" channel            |
|     |                     |  client   |    v                             |
|     v                     |  message  |  xymond_channel --channel=client |
| [local:systemd] section --+---------->|    |                             |
| in the client message     |           |    v                             |
+---------------------------+           |  xymond_systemd (worker)         |
                                        |    | rules: etc/systemdmon.cfg   |
                                        |    v                             |
                                        |  "status" message ->             |
                                        |  column "systemd" per host       |
                                        +----------------------------------+
```

1. **Collector** (`client/local/systemd`, bash): placed in
   `$XYMONCLIENTHOME/local/`. The Xymon client runs every executable
   in that directory and appends its output to the client message as
   a `[local:systemd]` section. The collector reports ALL units of
   the types service, timer, socket, mount, automount, swap and path
   (unfiltered), the complete failed-unit list without a type filter
   (so a failed service run of a timer job stays visible), and the
   overall `systemctl is-system-running` state. No client-side
   configuration, no client-side status column.
2. **Worker** (`server/libexec/xymond_systemd`, Perl 5 core modules
   only): attached to the xymond `client` channel through
   `xymond_channel` (started by xymonlaunch via tasks.cfg). It parses
   the `[local:systemd]` section of every incoming client message,
   evaluates the central rule file `systemdmon.cfg` and sends a
   `status` message for the `systemd` column. Hosts without the
   section are skipped entirely - they get no column.

Status colors are limited to green/yellow/red/clear; the status
lifetime defaults to 10 minutes (choose slightly above your client
poll interval, `--lifetime`).

## Installation

Requirements: an existing Xymon 4.3.x installation; bash on the
clients; Perl 5 (core modules only) on the Xymon server. On
Debian/Ubuntu Perl is always present (`perl-base` is essential); on
Rocky/RHEL minimal installs you may need `dnf install perl-interpreter`
on the server host.

The repository layout mirrors the Xymon installation paths, so
installation means copying two files. The included `install.sh`
automates this (`--dry-run` shows what would happen; paths can be
overridden with `XYMONCLIENTHOME` / `XYMONHOME` / `SYSTEMDMON_TASKSD`):

```
./install.sh --dry-run     # inspect
./install.sh               # auto-detects client and/or server
```

### Client (each monitored host)

```
install -m 755 client/local/systemd $XYMONCLIENTHOME/local/systemd
```

That is all. The file name `systemd` determines the section name
`[local:systemd]` - do not rename it. The collector needs no
privileges beyond read-only `systemctl` queries and works as the
unprivileged xymon user. On hosts without systemd it outputs nothing.

Optional environment overrides (e.g. in `clientlaunch.cfg`'s ENVFILE):

| Variable | Default | Meaning |
|---|---|---|
| `SYSTEMDMON_TYPES` | `service,timer,socket,mount,automount,swap,path` | unit types reported in `## units` |
| `SYSTEMDMON_SYSTEMSTATE` | `1` | include the `## systemstate` line |
| `SYSTEMDMON_VERBOSE` | `0` | log progress via `logger` |

### Server (Xymon server)

```
install -m 755 server/libexec/xymond_systemd $XYMONHOME/libexec/
install -m 644 server/etc/systemdmon.cfg     $XYMONHOME/etc/      # then edit
```

Register the worker with xymonlaunch:

- **Debian/Ubuntu packages** include `/etc/xymon/tasks.d/` from
  tasks.cfg - drop `server/etc/tasks-snippet.cfg` there as
  `systemdmon.cfg`.
- **Other installations** (including Rocky/Terabithia RPMs - whether
  they ship a tasks.d include is not yet verified): append the
  `[systemdmon]` block from `server/etc/tasks-snippet.cfg` to
  `$XYMONHOME/etc/tasks.cfg`.

xymonlaunch notices tasks.cfg changes automatically; the worker log
goes to `$XYMONSERVERLOGS/systemdmon.log`.

## Configuration (`systemdmon.cfg`)

All rules live in one file on the server, in the style of
analysis.cfg with `PROC`-like semantics. Reload happens automatically
when the file changes (mtime) or on SIGHUP - no restart needed.
See the extensively commented `server/etc/systemdmon.cfg` for the
full reference and examples. In short:

```
# global rules (apply to all hosts running the collector)
DEFAULTFAILED yellow            # failed units without an explicit rule
SYSTEMSTATE yellow              # is-system-running != "running"
SVC sshd.service active red
IGNORE %^user@\d+\.service$

CLASS=linux                     # scope: client class (defaults to OS)
SVC cron.service active yellow

PAGE=production                 # scope: hosts.cfg page (page or page/subpage)
SVC node_exporter.service active yellow

HOST=web1.example.com,%^web\d+  # scope: hostnames, exact or %PCRE
SVC nginx.service active red
SVC php-fpm.service active red TEXT="PHP FastCGI"
SVC %^getty@tty\d+\.service$ active yellow MIN=1 MAX=1 TEXT="gettys"
SVC telnet.socket inactive red  # a unit that must NOT run
```

Rules match the **full unit name including the suffix**
(`sshd.service`, `backup.timer`, `data.mount`); there is no
type-specific syntax. `%` introduces a PCRE pattern. Expected states
are ACTIVE states (`active`, `inactive`, `failed`, ...), optionally
with a SUB state as `active/running`. `MIN=`/`MAX=` turn a rule into
a count check. Precedence per unit: HOST beats CLASS beats PAGE
beats global; within one level the first matching rule in the file
wins, and a more specific rule overrides less specific ones for the
units it matches.

### Worker options

`xymond_systemd --help` shows all options; the important ones:

| Option / Env | Default | Meaning |
|---|---|---|
| `--config` / `SYSTEMDMON_CFG` | `$XYMONHOME/etc/systemdmon.cfg` | rule file |
| `--column` / `SYSTEMDMON_COLUMN` | `systemd` | column name |
| `--lifetime` / `SYSTEMDMON_LIFETIME` | `10` | status lifetime (xymon syntax) |
| `SYSTEMDMON_HOSTSCFG` | `$HOSTSCFG` | hosts.cfg for the PAGE= map |
| `--test FILE...` | - | offline mode for testing (see below) |
| `--dump-rules` | - | print the parsed rule file and exit |

## Alerting (`alerts.cfg`)

The `systemd` column behaves like any other status column. Examples:

```
# page on red systemd status in production, mail on yellow
PAGE=production SERVICE=systemd COLOR=red
	SCRIPT /usr/local/bin/pagerscript ops-oncall FORMAT=SMS

HOST=* SERVICE=systemd COLOR=red,yellow
	MAIL admins@example.com REPEAT=120 RECOVERED
```

## Testing

Offline tests (no Xymon server needed):

```
tests/run-tests.sh
```

They feed a canned client-channel stream through
`xymond_systemd --test` and assert colors, scoping precedence, count
checks, DEFAULTFAILED/IGNORE handling and the ghost case (a host
without the section produces no column). `tests/MANUAL-TESTING.md`
contains the checklist for tests on real systems (Rocky/Ubuntu
clients, Xymon 4.3.30 server).

You can also inspect what the worker would send for a real client
message: save one (e.g. via `xymon $XYMSRV "clientlog HOSTNAME"` with
framing added, or use the fixture format in `tests/fixtures/`) and run
`xymond_systemd --test --config=... FILE`.

## Repository layout

```
client/local/systemd           collector -> $XYMONCLIENTHOME/local/
server/libexec/xymond_systemd  channel worker -> $XYMONHOME/libexec/
server/etc/systemdmon.cfg      rule file example -> $XYMONHOME/etc/
server/etc/tasks-snippet.cfg   [systemdmon] block for tasks.cfg/tasks.d
tests/                         offline tests + manual test guide
install.sh                     installer (client/server detection)
```

## Design notes

- Everything is add-on only - no patching of Xymon itself.
  `xymond_channel` is the documented mechanism for server-side
  workers, `local/` the documented client extension point.
- The collector output is a versioned contract (`systemdmon v1`
  marker line, `##`-prefixed subsections). No payload line ever
  starts with `[`, which xymond would interpret as a new message
  section.
- The client-channel framing handled by the worker was verified
  against the Xymon 4.3.30 sources (xymond.c, xymond_worker.c,
  xymond_sample.c), including the `@@shutdown`, `@@logrotate`,
  `@@idle` and `@@reload` control messages.
