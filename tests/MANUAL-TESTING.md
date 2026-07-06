# Manual testing checklist (real systems)

The offline tests (`tests/run-tests.sh`) cover the worker logic.
The following steps verify the pieces that need real systems:
Rocky Linux and Ubuntu clients, and a Xymon 4.3.30 server.

## 1. Client collector on a real host (Rocky and Ubuntu)

As the xymon user (important - verifies unprivileged operation):

```
sudo -u xymon /usr/lib/xymon/client/local/systemd | head -30
```

- [ ] First line is `systemdmon v1`.
- [ ] `## systemstate` shows `running` (or `degraded` if the host
      really is degraded).
- [ ] `## units` lists service/timer/socket/mount/automount/swap/path
      units, one per line, no truncated unit names (`--full`).
- [ ] `## failed` is empty on a healthy host.
- [ ] No output line starts with `[`.
- [ ] Runtime is well under a second (`time ...`).
- [ ] Break a unit (`systemctl start` a service whose ExecStart fails,
      or `systemctl kill --signal=SIGKILL` a Type=oneshot timer
      service) and confirm it appears under `## failed` even when its
      type is not in `SYSTEMDMON_TYPES`.

## 2. Section arrives in the client message

After installing the collector and waiting one client cycle
(default 5 minutes), on the Xymon server:

```
xymon $XYMSRV "clientlog HOSTNAME" | grep -A5 '\[local:systemd\]'
```

- [ ] The `[local:systemd]` section is present and intact.
- [ ] Message size increase is a few KB at most
      (`xymon ... "clientlog HOSTNAME" | wc -c` before/after).

## 3. Worker under xymonlaunch

Install worker + config + tasks snippet, then:

- [ ] `xymonlaunch` shows the `[systemdmon]` task as running
      (check `$XYMONSERVERLOGS/systemdmon.log` for the startup line).
- [ ] A `systemd` column appears for hosts running the collector.
- [ ] Hosts WITHOUT the collector get NO `systemd` column (ghost
      check) - also verify no ghost hosts appear in ghostlist.cgi.
- [ ] Column goes purple only if the client stops reporting for
      longer than the lifetime (expected behavior).

## 4. Rules end-to-end

- [ ] Add `SVC <some-unit>.service active red` for a stopped unit:
      column turns red within one client cycle.
- [ ] Stop an unruled unit so it fails: column turns yellow
      (DEFAULTFAILED).
- [ ] Add an `IGNORE` for it: column recovers.
- [ ] Edit systemdmon.cfg (no restart): the reload line appears in
      systemdmon.log (mtime check) - same after `kill -HUP <pid>`.
- [ ] Scoping precedence on a real host: define the same unit in a
      global, a CLASS= and a HOST= section with different colors and
      confirm the HOST rule wins.
- [ ] `logrotate` night run: worker keeps logging into the fresh
      systemdmon.log (handles `@@logrotate`).

## 5. Packaging paths (documentation follow-up)

- [ ] Verify the Rocky/Terabithia RPM layout: XYMONHOME, and whether
      their tasks.cfg kept the stock
      `directory $XYMONHOME/etc/tasks.d` line (check
      `grep -ri 'directory\|include' .../tasks.cfg`); update the RPM
      spec defaults accordingly.
- [ ] Confirm XYMONCLIENTHOME/XYMONHOME auto-detection paths in
      install.sh on both platforms; extend the probe lists if needed.

## 6. FreeBSD Xymon server

Build the staging tarball on Linux
(`packaging/build-packages.sh --freebsd`), copy it over, then on the
FreeBSD host:

```
tar xzf xymon-systemdmon-<version>-freebsd-staging.tar.gz
cd freebsd && ./make-package.sh
pkg add ./xymon-systemdmon-<version>.pkg
```

- [ ] make-package.sh runs clean (pkg create succeeds, correct
      noarch ABI like FreeBSD:14:*).
- [ ] `pkg info -l xymon-systemdmon` lists worker, samples, examples.
- [ ] post-install copied both .sample files to their real names;
      an existing edited systemdmon.cfg survives `pkg upgrade`/
      reinstall untouched.
- [ ] `pkg install perl5` present; `perl -c
      /usr/local/www/xymon/server/libexec/xymond_systemd` passes.
- [ ] xymonlaunch starts the [systemdmon] task (port tasks.cfg
      includes tasks.d; check systemdmon.log).
- [ ] Offline tests pass on FreeBSD too:
      `SYSTEMDMON_WORKER=... tests/run-tests.sh` (script needs bash:
      `pkg install bash`).
- [ ] Linux clients report and the systemd column appears; ghost
      case still holds.
- [ ] `pkg delete xymon-systemdmon` keeps an edited systemdmon.cfg
      but removes an unmodified one (pre-deinstall cmp logic).
