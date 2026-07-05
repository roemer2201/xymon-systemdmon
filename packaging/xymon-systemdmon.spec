# RPM spec for xymon-systemdmon (single package, client + server files,
# modeled on the Debian "hobbit-plugins" approach: unused server files
# on a client host are harmless).
#
# Built from the repository working tree, no source tarball needed:
#
#   rpmbuild -bb packaging/xymon-systemdmon.spec \
#       --define "srcdir /path/to/xymon-systemdmon" \
#       --define "pkgver 0.1.0"
#
# (or simply use packaging/build-packages.sh --rpm)
#
# Xymon installation paths differ between packagings and source
# installs. The defaults below match the Debian-style layout; the
# Terabithia RPM layout is NOT yet verified (see TODO.md). Override
# at build time if needed:
#
#   --define "xymon_home /usr/share/xymon"
#   --define "xymon_clienthome /usr/share/xymon-client"
#
# No hard Requires on a xymon/xymon-client package: Xymon is often
# installed from source or from differently named third-party
# packages; a wrong dependency name would make the package
# uninstallable there.

%{!?pkgver:           %define pkgver 0.1.0}
%{!?pkgrel:           %define pkgrel 1}
%{!?srcdir:           %{error:build with --define "srcdir /path/to/repo"}}
%{!?xymon_home:       %define xymon_home /usr/lib/xymon/server}
%{!?xymon_clienthome: %define xymon_clienthome /usr/lib/xymon/client}

Name:           xymon-systemdmon
Version:        %{pkgver}
Release:        %{pkgrel}
Summary:        systemd unit monitoring for the Xymon monitoring system
License:        GPL-2.0-only
URL:            https://github.com/roemer2201/xymon-systemdmon
BuildArch:      noarch
Requires:       bash
# Disable automatic perl(...) requires: they stem from the server
# worker only, and would force a perl install onto every monitored
# client host. The Xymon SERVER host needs Perl 5 (core modules
# only) for xymond_systemd - documented in the README.
AutoReq:        no

%description
systemd unit monitoring for Xymon in a single package (like the
Debian hobbit-plugins package, client and server files ship
together; unused files are harmless):

- client collector (%{xymon_clienthome}/local/systemd): reports all
  systemd units as a [local:systemd] client message section; the
  Xymon client picks it up automatically once installed.
- server channel worker (%{xymon_home}/libexec/xymond_systemd):
  attaches to the xymond client channel via xymond_channel,
  evaluates the rule file /etc/xymon/systemdmon.cfg and sends status
  messages for the "systemd" column. Register the worker with
  xymonlaunch using the snippet in /etc/xymon/tasks.d/systemdmon.cfg
  (append it to tasks.cfg manually if your installation does not
  include a tasks.d directory). The worker needs Perl 5 (core
  modules only), which is only relevant on the Xymon server host.

%install
install -D -m 755 %{srcdir}/client/local/systemd \
    %{buildroot}%{xymon_clienthome}/local/systemd
install -D -m 755 %{srcdir}/server/libexec/xymond_systemd \
    %{buildroot}%{xymon_home}/libexec/xymond_systemd
install -D -m 644 %{srcdir}/server/etc/systemdmon.cfg \
    %{buildroot}%{_sysconfdir}/xymon/systemdmon.cfg
install -D -m 644 %{srcdir}/server/etc/tasks-snippet.cfg \
    %{buildroot}%{_sysconfdir}/xymon/tasks.d/systemdmon.cfg
install -D -m 644 %{srcdir}/LICENSE \
    %{buildroot}%{_docdir}/%{name}/LICENSE
install -D -m 644 %{srcdir}/README.md \
    %{buildroot}%{_docdir}/%{name}/README.md

%files
%{xymon_clienthome}/local/systemd
%{xymon_home}/libexec/xymond_systemd
%config(noreplace) %{_sysconfdir}/xymon/systemdmon.cfg
%dir %{_sysconfdir}/xymon/tasks.d
%config(noreplace) %{_sysconfdir}/xymon/tasks.d/systemdmon.cfg
%{_docdir}/%{name}/

%changelog
* Sat Jul 04 2026 roemer2201 <r.oliver@web.de> - 0.1.0-1
- Initial packaging (single package: client collector and server
  channel worker)
