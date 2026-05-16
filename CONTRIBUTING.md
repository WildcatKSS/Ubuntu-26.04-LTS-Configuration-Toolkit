# Contributing

Thanks for considering a contribution! This guide covers the conventions used
across the toolkit so that custom modules slot in cleanly without breaking
existing behaviour.

---

## Architecture in 30 seconds

```
main.sh
  │
  ├── auto-discovers scripts/*.sh (alphabetical order)
  ├── parses each module's metadata header
  ├── validates the dependency DAG (no cycles, no missing targets)
  ├── runs each module after acquiring /tmp/.toolkit-lock
  └── records progress in /var/log/toolkit-setup/.state

lib/common.sh sources:
  - log.sh    : log_info / log_warn / log_error, log_check_diskspace, run_quiet
  - config.sh : config_load, config_validate
  - system.sh : system_check_root, system_confirm, system_user_exists,
                system_service_enable_start, system_service_mask,
                system_file_install, system_file_backup, system_render_install
  - pkg.sh    : pkg_install, pkg_purge, pkg_update (idempotent apt wrappers)
  - state.sh  : state_init, state_mark_complete, state_is_complete, state_summary
  - plan.sh   : plan_action (skip mutations when TOOLKIT_PLAN_MODE=1)
```

---

## Adding a custom module

Create `scripts/50-myfeature.sh` with the standard metadata header:

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 WildcatKSS
# Ubuntu Server 26.04 LTS Configuration Toolkit
#
# MODULE:      50-myfeature
# DESC:        Short, one-line description
# DEPENDS:     05-packages
# IDEMPOTENT:  yes
# DESTRUCTIVE: no

set -euo pipefail
TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$TOOLKIT_ROOT/lib/common.sh"
```

Make the script executable: `chmod +x scripts/50-myfeature.sh`.

---

## Code style

- **Always** `set -euo pipefail` at the top.
- **Always** quote variable expansions: `"$VAR"`, `"${ARRAY[@]}"`.
- Use `log_info` / `log_warn` / `log_error` instead of `echo` for status output.
- Use `pkg_install` / `system_file_install` / `system_render_install` rather
  than raw `apt-get` / `cp` / `envsubst`.
- Wrap mutations in `if plan_action "describe what would change"; then …; fi`
  so `--plan` reports them without executing.
- **Do not** use `run_quiet` inside `$(…)` or as the producer in a pipe —
  it redirects stdout, so the caller gets empty input and idempotency guards
  silently misfire. Use `cmd 2>/dev/null` instead.

---

## Function naming

Library functions use namespace prefixes (`log_`, `config_`, `system_`, `pkg_`,
`state_`). Custom modules should use a unique prefix, typically derived from
the module name:

```bash
# scripts/50-mycompany.sh
mycompany_install_license() { ... }
```

---

## Idempotency contract

Every module MUST be safe to run multiple times. `tests/test_idempotency.bats`
enforces structural rules: metadata header is present, `IDEMPOTENT: yes`,
`bash -n` passes, `# DEPENDS:` targets resolve, `main.sh --list` and `--help`
work. End-to-end run-twice-no-change is verified manually on a VM.

**Always check state before changing state.** The helpers already do this:
- `pkg_install` skips already-installed packages
- `system_file_install` / `system_render_install` only write when content
  differs
- For custom checks: `grep -q FOO /etc/file || sed -i '...' /etc/file`

**Distinguish critical vs non-critical errors:**
- Critical (data loss, broken system): `log_error "..."; exit 1`
- Non-critical (transient service issue): `log_warn "..."` and continue

---

## Hooks

Two optional hook locations are auto-discovered:

```
scripts/hooks/pre-<module-name>.sh
scripts/hooks/post-<module-name>.sh
```

Hooks are non-critical: a hook that exits non-zero logs an ERROR and execution
continues.

---

## Testing locally

```bash
sudo apt-get install -y shellcheck bats
bash -n scripts/*.sh lib/*.sh main.sh
shellcheck -x -e SC1091,SC2034 scripts/*.sh lib/*.sh main.sh
bats tests/
```

Add a BATS test in `tests/` if your module exposes helper functions.

---

## Commit message format

Prefix the subject with the affected module in square brackets, keep it under
70 chars, and explain *why* in the body:

```
[06-hardening] add sysctl rule for kernel.unprivileged_bpf_disabled
[lib/state] fix race when promoting state file
```

---

## Versioning and changelog

This project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Every PR that changes code under `scripts/`, `lib/`, `main.sh`, or `templates/`
MUST bump `VERSION` and add a section to `CHANGELOG.md`.

- **PATCH** (1.0.X): bug fixes, docs
- **MINOR** (1.X.0): new features, modules, flags — backwards compatible
- **MAJOR** (X.0.0): breaking changes

Enable the pre-commit hook to validate this locally:

```bash
ln -sf ../../scripts/hooks/pre-commit .git/hooks/pre-commit
```

GitHub Actions also enforces VERSION bumps on PRs with code changes.

### Releasing (maintainers)

1. Move the unreleased changelog content into a `## X.Y.Z – YYYY-MM-DD` section.
2. Tag: `git tag -a vX.Y.Z -m "Release vX.Y.Z"` and `git push origin vX.Y.Z`.
