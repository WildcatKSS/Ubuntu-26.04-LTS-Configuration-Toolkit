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
  - log.sh    : log_info / log_warn / log_error, log_check_diskspace, log_migrate
  - config.sh : config_load, config_validate (with email/IP/hostname validators)
  - system.sh : system_check_root, system_confirm, system_user_exists,
                system_service_enable_start, system_service_mask, system_file_install
  - pkg.sh    : pkg_install, pkg_purge, pkg_update (idempotent apt wrappers)
  - state.sh  : state_init, state_mark_complete, state_is_complete,
                state_summary
```

---

## Adding a custom module

1. Create `scripts/50-myfeature.sh` with the standard metadata header:

   ```bash
   #!/usr/bin/env bash
   # MODULE: 50-myfeature
   # DESC: Short, one-line description
   # DEPENDS: 06-packages
   # IDEMPOTENT: yes
   # DESTRUCTIVE: no

   set -euo pipefail
   TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
   source "$TOOLKIT_ROOT/lib/common.sh"

   PLAN_MODE="${TOOLKIT_PLAN_MODE:-0}"
   ...
   ```

2. **Always** check state before changing state. Examples:
   - `pkg_install` already skips already-installed packages — use it
   - `system_file_install` only writes when the source/destination differ
   - For custom checks: `grep -q FOO /etc/file || sed -i '...' /etc/file`

3. Honour `TOOLKIT_PLAN_MODE=1`: when set, your module should print what it
   *would* change but not perform writes.

4. Distinguish critical vs non-critical errors:
   - Critical (data loss, broken system): `log_error "..."; exit 1`
   - Non-critical (transient service issue): `log_warn "..."` and continue

5. Add a BATS test in `tests/` if your module exposes helper functions.

6. Make the script executable: `chmod +x scripts/50-myfeature.sh`.

---

## Function naming convention

To avoid collisions with user modules, library functions use namespace
prefixes:

| Prefix | Module | Purpose |
|---|---|---|
| `log_*` | `lib/log.sh` | Logging |
| `config_*` | `lib/config.sh` | Configuration |
| `system_*` | `lib/system.sh` | OS utilities |
| `pkg_*` | `lib/pkg.sh` | Package management |
| `state_*` | `lib/state.sh` | State tracking |

Custom modules should use a unique prefix — typically the module name:

```bash
# scripts/50-mycompany.sh
mycompany_install_license() { ... }
```

---

## Idempotency contract

Every module MUST be safe to run multiple times. The BATS test
`tests/test_idempotency.bats` enforces:

- The metadata header is present and well-formed.
- `IDEMPOTENT: yes` is declared.
- `bash -n` passes for every script.
- `main.sh --list` and `--help` work.
- Every `# DEPENDS:` target resolves to an existing module.

End-to-end idempotency (run-twice-no-change) is verified manually on a VM —
see the README troubleshooting section for the procedure.

---

## State persistence

State lives at `/var/log/toolkit-setup/.state` for the entire run and
survives reboots. Call `state_mark_complete` / `state_is_complete` to
read/write it; never hardcode the path.

---

## Code style

- **Always** `set -euo pipefail` at the top of executable scripts.
- **Always** quote variable expansions: `"$VAR"`, `"${ARRAY[@]}"`.
- Run `shellcheck -x -e SC1091,SC2034` on your script before committing.
- Use `log_info`/`log_warn`/`log_error` instead of `echo`.
- Use `pkg_install` / `system_file_install` rather than raw `apt-get` / `cp`.

---

## Commit message format

Prefix the commit subject with the affected module in square brackets:

```
[07-hardening] add new sysctl rule for kernel.unprivileged_bpf_disabled
[lib/state] fix race when promoting state file
[ci] bump shellcheck severity to warning
```

Keep the subject under 70 characters and explain the *why* in the body.

---

## Hooks

Two optional hook locations are auto-discovered:

```
scripts/hooks/pre-<module-name>.sh
scripts/hooks/post-<module-name>.sh
```

Hooks share the same metadata header convention but are non-critical: a hook
that exits non-zero logs an ERROR and execution continues.

---

## Testing locally

```bash
sudo apt-get install -y shellcheck bats
bash -n scripts/*.sh lib/*.sh main.sh
shellcheck -x -e SC1091,SC2034 scripts/*.sh lib/*.sh main.sh
bats tests/
```

CI runs the same checks on every push (`.github/workflows/ci.yml`).
