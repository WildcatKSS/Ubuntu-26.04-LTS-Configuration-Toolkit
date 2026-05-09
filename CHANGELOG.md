# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `docs/incidents/2026-05-canonical-ddos.md` — operator runbook for the May
  2026 DDoS attack on Canonical infrastructure. Describes how the outage
  surfaces in `00-preflight` and three workarounds (regional mirror swap,
  http→https on the existing mirror, wait-and-retry). Linked from the README
  troubleshooting table.

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
