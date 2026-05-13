# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- `lib/log.sh`: logging functions (`log_info`, `log_warn`, `log_error`) now work correctly when called from top-level scripts with `set -u` active.
  Previously, the BASH_SOURCE array index checks could fail under strict variable mode.
- `lib/log.sh`: `_log_write` now uses explicit array length checks instead of `${BASH_SOURCE[N]:-}`,
  fixing the top-level-script regression test on bash 5.3+ where indirect array indexing under `set -u`
  is stricter than in earlier versions.
- `lib/log.sh`: `_log_write` now iterates over `BASH_SOURCE` with a `for`-loop instead of indexing
  individual elements, eliminating the remaining `set -u` failure mode on bash 5.3+ and producing
  the same caller resolution for shallow (top-level script) and deep (main.sh wrapper) call stacks.
- `tests/test_common.bats`: regression test now invokes `bash "$script"` directly instead of relying
  on a shebang + `chmod +x`, so the test no longer breaks on systems where `BATS_TEST_TMPDIR` lives
  on a `noexec` mount. On failure the test prints `status` and captured `output` so the underlying
  error is visible instead of a bare `[ "$status" -eq 0 ]' failed` line.
- `lib/log.sh`: file appends are now skipped when the log file's parent directory does not exist,
  eliminating the spurious `No such file or directory` redirection error from bash itself.
- `lib/log.sh`: `log_error` only prints the "Run grep ERROR …" recovery hint when the log file
  actually exists, avoiding a misleading pointer to a non-existent path.
- `main.sh`: creates `TOOLKIT_PERSISTENT_DIR` at startup (best-effort) so log writes succeed
  from the first call, before the root-only setup steps run.

### Added
- Pre-commit hook (`.git/hooks/pre-commit`) that enforces changelog updates for all code changes.
  Developers must update `CHANGELOG.md` under `[Unreleased]` before committing code changes.
- Changelog maintenance documentation in `CONTRIBUTING.md` with instructions for updating the changelog.

## [2.0.0] – Ubuntu 26.04 LTS Migration

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
