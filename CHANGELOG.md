# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.1] – 2026-05-13

### Changed
- Tests now run **only** with explicit `--test` flag
  - Tests no longer run automatically with `--plan` or `--dry-run` flags
  - Tests no longer run when main.sh is executed without flags (default behavior)
  - This allows `--plan` and `--dry-run` to complete faster for quick audits

### Fixed
- Bug fixes and corrections

### Deprecated
- Features marked for removal in future versions

### Removed
- Removed features or modules

### Security
- Security-related fixes

---

## [1.0.0] – Ubuntu Server 26.04 LTS Configuration Toolkit – 2026-05-13

### Added
- **Initial stable release** of Ubuntu Server 26.04 LTS Configuration Toolkit
- Modular bash toolkit for end-to-end system configuration:
  - Preflight checks (OS validation, disk space, internet, apt locks)
  - Base configuration (apt upgrade, sudo user, unattended-upgrades)
  - IP/network configuration with Netplan support
  - Timezone and NTP configuration (chrony)
  - Kernel hardening and AppArmor setup
  - Auditd audit logging
  - Mail relay with Postfix
  - System monitoring with collectd
  - Log aggregation with Rsyslog
  - Service cleanup and optimization
- Comprehensive module system with:
  - Automatic dependency resolution (DAG validation)
  - Idempotency guarantees (safe to run multiple times)
  - Plan mode for dry-run audits (`--plan` flag)
  - Syntax validation and linting via ShellCheck
  - BATS unit test suite
  - Full state tracking and recovery
- Rich CLI with flags:
  - `--list` - module discovery
  - `--plan` - read-only audit
  - `--dry-run` - syntax validation
  - `--resume` - recovery from failures
  - `--force` - re-run all modules
  - `--retry=<module>` - retry single module
  - `--only=<module>` - run single module
  - `--skip=<modules>` - skip specific modules
  - `--test` - full test suite
  - `--ignore-errors` - non-critical error recovery
  - `--version` / `-v` - display toolkit version
- Interactive questionnaire for initial setup
- State file tracking for fault recovery (`/var/log/toolkit-setup/.state`)
- Comprehensive logging to `/var/log/toolkit-setup/toolkit-setup.log`
- Git-safe configuration (credentials excluded via .gitignore)
- **Semantic versioning** support with:
  - `VERSION` file tracking current release
  - `lib/version.sh` helper library
  - Version display in CLI and logs
  - Release process documentation

### Documentation
- Complete README with quickstart and module reference
- CLAUDE.md with architectural guidelines
- CONTRIBUTING.md with development conventions and release process
- Extensive inline code documentation
- Helper library quick reference

### Testing
- Syntax validation with `bash -n`
- ShellCheck linting (SC1091, SC2034 exclusions)
- BATS unit tests for common.sh and idempotency
- Structural validation (module headers, DAG cycles, dependencies)
- Local testing instructions in README and CONTRIBUTING

### Project Governance
- MIT License
- Pre-commit hooks for changelog enforcement
- Semantic versioning with documented release process
- Comprehensive error recovery and user guidance
