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
  - log.sh    : log_info / log_warn / log_error, log_check_diskspace
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
   # DEPENDS: 05-packages
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

## Changelog maintenance

Every code change should include a corresponding entry in `CHANGELOG.md` under
the `[Unreleased]` section. The changelog follows the
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.

**When to update the changelog:**
- Any change to `scripts/`, `lib/`, `main.sh`, or `templates/`
- Bug fixes, new features, breaking changes, deprecations
- *Skip* for: README updates, docs-only changes (use `--no-verify` if needed)

**How to add a changelog entry:**

```markdown
## [Unreleased]

### Added
- New feature description

### Fixed
- Bug description and fix applied

### Changed
- Modified behavior description

### Removed
- Deprecated feature or helper function
```

A pre-commit hook enforces this rule for code changes. If you commit a
code change without updating the changelog, the hook will block the commit
with instructions. To fix:

```bash
# 1. Update CHANGELOG.md with your changes
# 2. Stage it:
git add CHANGELOG.md
# 3. Amend the commit:
git commit --amend --no-edit
# 4. Try committing again
```

---

## Release and versioning

This project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html) as documented in `CHANGELOG.md`.

**Version numbering:**
- **MAJOR** (X.0.0): Breaking API/config changes (module removal, incompatible syntax)
- **MINOR** (1.X.0): Backwards-compatible features (new modules, new flags)
- **PATCH** (1.0.X): Backwards-compatible bug fixes, documentation updates

**Release process:**
1. Update `CHANGELOG.md`: move `[Unreleased]` changes to a new `[X.Y.Z] – YYYY-MM-DD` section
2. Update `VERSION` file with the new version number (e.g., `2.1.0`)
3. Commit: `git commit -m "[release] v2.1.0"`
4. Create git tag: `git tag -a v2.1.0 -m "Release v2.1.0"`
5. Push: `git push origin main --tags`

**Version retrieval at runtime:**
```bash
./main.sh --version
# or in a script:
source lib/version.sh
VERSION=$(toolkit_get_version)
```

---

## Commit message format

Prefix the commit subject with the affected module in square brackets:

```
[06-hardening] add new sysctl rule for kernel.unprivileged_bpf_disabled
[lib/state] fix race when promoting state file
[lib/log] bump default log level
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
