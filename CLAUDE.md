# CLAUDE.md — context for AI-assisted development

This file orients Claude (or any AI agent) when working in this repository.

## What this repo is

A modular bash toolkit that configures a fresh Ubuntu Server 26.04 LTS system end-to-end:
network, hardening, monitoring, mail. One master script
(`main.sh`) auto-discovers numbered modules under `scripts/` and runs them in
alphabetical order, validating dependencies along the way.

## Top-level layout

```
main.sh                    — entry point; flag parsing, DAG validation, lock
config/defaults.conf       — user config (gitignored; example shipped)
scripts/00-..99-*.sh       — modules with metadata header
scripts/hooks/             — optional pre-/post- hooks per module
templates/                 — config files copied/rendered by modules
lib/                       — sourced helpers (log, config, system, pkg, state)
tests/                     — BATS unit + structural tests
LICENSE                    — MIT License
```

## Conventions you MUST follow

- **Module header** (first 20 lines, parsed by main.sh):
  ```bash
  # MODULE: 04-network-hardening
  # DESC: short description
  # DEPENDS: 03-ip-config            (comma-separated short names; empty for none)
  # IDEMPOTENT: yes                  (must be yes — enforced by tests)
  # DESTRUCTIVE: no                  (yes only for irreversible disk/system operations)
  ```
- **Sourcing pattern** at the top of every module:
  ```bash
  set -euo pipefail
  TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
  source "$TOOLKIT_ROOT/lib/common.sh"
  ```
- **Plan mode**: wrap every mutation in
  `if plan_action "describe what would change"; then …; fi`. The helper
  returns 1 (skip) when `TOOLKIT_PLAN_MODE=1` and 0 (run) otherwise, so the
  same source path handles both real runs and `--plan` audits.
- **Idempotency**: always check current state before mutating. Patterns to use:
  - `pkg_install` (skips installed packages)
  - `system_file_install` (only writes if cmp differs)
  - `grep -q PATTERN /etc/file || ...`
  - `[ -f marker ] || do-thing && touch marker`
- **Logging**: `log_info`, `log_warn`, `log_error` — never bare `echo` for status.
- **`run_quiet` contract**: silences a command's stdout AND stderr; use it
  only for fire-and-forget calls where you care about the exit code (e.g.
  `if run_quiet aa-status --enabled`). NEVER inside `$(…)` or as a pipe
  producer — the consumer gets empty input and idempotency guards silently
  misfire. Use `cmd 2>/dev/null` for those cases.
- **Function namespacing**: prefix custom functions with the module short name
  (e.g. `mycompany_*`) to avoid colliding with `log_*`, `pkg_*`, `system_*`,
  `state_*`, `config_*`.

## State file

State lives at `/var/log/toolkit-setup/.state` for the entire run. Never write
a hardcoded path — call the helpers (`state_mark_complete`, `state_is_complete`).

## Critical constraints

- **Never** push to `main`/`master` directly. Development work is done on feature branches
  (e.g. `claude/feature-name-XXXXX`); all changes merge to `main` via pull requests.
- **Never** commit `config/defaults.conf` — it is gitignored to keep
  credentials out of git.
- **Never** add a module that is destructive without setting
  `# DESTRUCTIVE: yes` and gating the action behind `system_confirm`.
- **Never** modify network configuration without writing a backup to
  `/etc/netplan.backup` first; restore on failure.
- **Never** skip pre-commit hooks (`--no-verify`); fix the underlying issue.

## Useful invariants

- Modules are alphabetically ordered; numbering 00–99 leaves room for user
  inserts (e.g. `15-postgres.sh`, `45-our-vpn.sh`).
- `main.sh --list` is the canonical "what will run?" command.
- `main.sh --plan` runs every module with `TOOLKIT_PLAN_MODE=1` for a
  read-only audit. Any mutation in plan mode is a bug.
- `main.sh --dry-run` only does `bash -n`; it does not source `lib/common.sh`
  inside modules, so it cannot detect runtime issues.
- The lock at `/tmp/.toolkit-lock` is released by the EXIT trap; if a run
  was killed with `kill -9`, remove the directory manually.

## Common helper API quick reference

```bash
log_info "..."                       # info-level log to stderr + log file
log_warn "..."                       # warn-level
log_error "..."                      # error-level + recovery hint to stderr

config_load /path/to/conf            # source-with-export
config_validate                      # checks required vars + formats

system_check_root                    # exits 1 if not root
system_confirm "Proceed?" yes        # interactive prompt; honours TOOLKIT_NONINTERACTIVE
system_user_exists alice
system_service_enable_start nginx    # idempotent enable+start, warn on fail
system_service_mask systemd-timesyncd
system_file_install src dst [mode]   # cmp-based copy (idempotent)
system_file_backup file              # one-time <file>.toolkit.bak
system_render_install tmpl dst [mode] # envsubst → cmp → install (idempotent)

plan_action "would do X"             # returns 1 (skip) under TOOLKIT_PLAN_MODE=1

pkg_update                           # apt-get update (cached 60min)
pkg_install vim htop curl            # only installs missing
pkg_purge network-manager            # only purges if installed

state_init
state_mark_complete "07-hardening"
state_is_complete  "07-hardening"
state_summary
```

## Tests

`tests/test_common.bats` runs unit tests on `lib/*` and works without root.
`tests/test_idempotency.bats` does structural checks (metadata, syntax, DAG).
End-to-end idempotency requires a VM and is a manual procedure (see README).

Run tests locally with:
```bash
bash -n scripts/*.sh lib/*.sh main.sh
shellcheck -x -e SC1091,SC2034 scripts/*.sh lib/*.sh main.sh
bats tests/
```
