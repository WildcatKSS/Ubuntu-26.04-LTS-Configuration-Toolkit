# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Retargeted toolkit at **Ubuntu Server 26.04 LTS**. The preflight OS check
  now requires `VERSION_ID="26.04"`; runs on 24.04 will be refused. CI
  workflow runs on `ubuntu-26.04`.

### Removed
- **Partitioning step**: `scripts/02-partitions.sh` (LVM `vg0` creation) is
  gone. The toolkit now assumes the disk layout is set by the installer and
  only configures software/system concerns. Removes `DISK_DEVICE`,
  `SKIP_PARTITIONS`, and `SWAP_ENCRYPT` configuration; removes encrypted-swap
  logic from `06-packages.sh`.
- `state_promote` helper and the temp -> persistent state-file migration.
  State is now written directly to `/var/log/toolkit-setup/.state` for the
  whole run. Operators upgrading from a previous run should re-run with
  `--force`; old `/tmp/toolkit-setup/.state` data is not migrated.

### Fixed
- Preflight no longer fails on networks that block ICMP or that have a
  transient DNS issue for `archive.ubuntu.com`. The connectivity check now
  probes apt's actually configured mirrors (parsed from `/etc/apt`) over
  HTTP, falling back to canonical Ubuntu hosts. Any successful HTTP response
  passes the check.

### Added
- Initial release of the Ubuntu 24.04 LTS Configuration Toolkit.
  - 11 modules covering preflight, base config, LVM partitions, IP/Netplan,
    network hardening (UFW, fail2ban, IPv6 off), chrony NTP, packages with
    optional encrypted swap, kernel/AppArmor/auditd hardening,
    sysstat/rsyslog/logrotate monitoring, postfix relay with daily report
    and disk/service alerts, and final cleanup.
  - `lib/` helpers split by domain (log, config, system, pkg, state).
  - Templates for netplan, sysctl, fail2ban, auditd, rsyslog, logrotate,
    postfix, daily-report, disk-alert.
  - `main.sh` flags: `--list`, `--plan`, `--dry-run`, `--resume`, `--retry`,
    `--only`, `--skip`, `--force`, `--ignore-errors`, `--help`.
  - Interactive + unattended modes via `ADMIN_USER`, `ADMIN_PASSWORD`,
    `SWAP_ENCRYPT`, `SKIP_PARTITIONS`, `TOOLKIT_NONINTERACTIVE` env vars.
  - BATS unit + structural tests and a GitHub Actions CI workflow.
  - README, CONTRIBUTING, and CLAUDE documentation.
