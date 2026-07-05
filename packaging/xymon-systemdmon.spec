# RPM spec for xymon-systemdmon (client and server subpackages).
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

%description
systemd unit monitoring for Xymon: a client-side collector reporting
all systemd units as a [local:systemd] client message section, and a
server-side channel worker evaluating central rules into a "systemd"
status column. Install xymon-systemdmon-client on monitored hosts and
xymon-systemdmon-server on the Xymon server.

%package client
Summary:        systemd unit collector for Xymon clients
Requires:       bash

%description client
Client-side collector for xymon-systemdmon. Installed into the Xymon
client's local/ extension directory (%{xymon_clienthome}/local); the
Xymon client picks it up automatically and appends a [local:systemd]
section to its client messages. All filtering and alerting rules live
on the Xymon server (xymon-systemdmon-server).

%package server
Summary:        systemd monitoring channel worker for the Xymon server
Requires:       perl

%description server
Server-side channel worker for xymon-systemdmon. Attaches to the
xymond client channel via xymond_channel, evaluates the rule file
/etc/xymon/systemdmon.cfg and sends status messages for the "systemd"
column. Register the worker with xymonlaunch using the snippet in
/etc/xymon/tasks.d/systemdmon.cfg (append it to tasks.cfg manually if
your installation does not include a tasks.d directory).

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
    %{buildroot}%{_docdir}/%{name}-client/LICENSE
install -D -m 644 %{srcdir}/README.md \
    %{buildroot}%{_docdir}/%{name}-client/README.md
install -D -m 644 %{srcdir}/LICENSE \
    %{buildroot}%{_docdir}/%{name}-server/LICENSE
install -D -m 644 %{srcdir}/README.md \
    %{buildroot}%{_docdir}/%{name}-server/README.md

%files client
%{xymon_clienthome}/local/systemd
%{_docdir}/%{name}-client/

%files server
%{xymon_home}/libexec/xymond_systemd
%config(noreplace) %{_sysconfdir}/xymon/systemdmon.cfg
%dir %{_sysconfdir}/xymon/tasks.d
%config(noreplace) %{_sysconfdir}/xymon/tasks.d/systemdmon.cfg
%{_docdir}/%{name}-server/

%changelog
* Sat Jul 04 2026 roemer2201 <r.oliver@web.de> - 0.1.0-1
- Initial packaging (client collector, server channel worker)
