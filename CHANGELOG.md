# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Semantic Versioning**: Toolkit now implements full semantic versioning (MAJOR.MINOR.PATCH) as per https://semver.org/.
  - `VERSION` file in repository root tracks current release version.
  - `lib/version.sh` provides version helpers: `toolkit_get_version()`, `toolkit_version_info()`, `toolkit_validate_version_format()`.
  - `./main.sh --version` (or `-v`) displays current version.
  - Version information logged at toolkit startup.
  - `CHANGELOG.md` documents all releases with semver categories (Added, Changed, Deprecated, Removed, Fixed, Security).

### Documentation
- **Version management guide** in `CHANGELOG.md` with release process and version retrieval examples.

---

## [2.0.0] – Ubuntu 26.04 LTS Migration – 2025-05-13

### Changed
- **Target OS**: Toolkit now targets **Ubuntu Server 26.04 LTS** exclusively.
  The preflight OS check requires `VERSION_ID="26.04"`; runs on 24.04 or earlier are refused.
- Module numbering and documentation updated to reflect the simplified 00–08, 99 range
  (after removal of the partitioning step).
- Template comments updated from `ubuntu-24-toolkit` to `ubuntu-26-toolkit`.

### Removed
- **Partitioning module**: `scripts/02-partitions.sh` (LVM `vg0` creation) is no longer included.
  The toolkit now assumes disk layout is set by the installer; only software/system configuration is applied.
  Removed config variables: `DISK_DEVICE`, `SKIP_PARTITIONS`, `SWAP_ENCRYPT`.
  Removed encrypted-swap logic from `06-packages.sh`.
- `state_promote` helper and the temp → persistent state-file migration.
  State is now written directly to `/var/log/toolkit-setup/.state` for the entire run.
  Operators upgrading from a prior version should run with `--force`; old `/tmp/toolkit-setup/.state` data is not migrated.
- **GitHub Actions CI**: `.github/workflows/ci.yml` and the `.github/` directory were removed.
  Tests remain runnable locally via `bats tests/`, `bash -n`, and `shellcheck`.
- Unused `log_migrate` helper from `lib/log.sh` (remnant of the removed `state_promote` migration).
- Empty no-op loop in `main.sh::validate_dag`.

### Fixed
- `scripts/99-cleanup.sh` dependency corrected from `DEPENDS: 09-mail-alerting` to `08-mail-alerting`
  (the 09-* module does not exist after partitioning removal).
- Preflight connectivity check now probes apt's configured mirrors (from `/etc/apt`) over HTTP,
  falling back to canonical Ubuntu hosts. No longer fails on ICMP-blocking networks or transient DNS issues.

### Added
- MIT License file and copyright statement.
- Documentation for Ubuntu 26.04 LTS setup workflow.
- Support for testing via `--test` flag to validate toolkit integrity.

---

## [1.0.0] – Ubuntu 24.04 LTS Configuration Toolkit

### Added
- Initial release of the Ubuntu 24.04 LTS Configuration Toolkit.
- 11 modules covering:
  - Preflight checks (OS, internet, disk space, apt locks)
  - Base configuration (apt upgrade, sudo user, unattended-upgrades)
  - LVM partitions (optional encrypted swap)
  - Network (IP/Netplan config with auto-restore)
  - Hardening (UFW, fail2ban, IPv6 off, cloud-init off, NetworkManager off)
  - NTP (chrony replacing systemd-timesyncd)
  - System packages (vim, htop, curl, git, etc.)
  - Kernel/AppArmor/auditd hardening
  - Monitoring (sysstat, rsyslog rules, logrotate)
  - Mail alerting (Postfix relay, daily reports, disk/service alerts)
  - Cleanup (apt autoremove, service verification)
- `lib/` helpers split by domain: log, config, system, pkg, state.
- Templates for netplan, sysctl, fail2ban, auditd, rsyslog, logrotate, postfix, daily-report, disk-alert.
- CLI flags: `--list`, `--plan`, `--dry-run`, `--resume`, `--retry`, `--only`, `--skip`, `--force`, `--ignore-errors`, `--help`.
- Interactive and unattended modes via `ADMIN_USER`, `ADMIN_PASSWORD`, `TOOLKIT_NONINTERACTIVE` env vars.
- BATS unit and structural tests with GitHub Actions CI.
- README, CONTRIBUTING, and CLAUDE documentation.
