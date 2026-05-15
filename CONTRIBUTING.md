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
   # SPDX-License-Identifier: MIT
   # Copyright (c) 2026 WildcatKSS
   # Ubuntu Server 26.04 LTS Configuration Toolkit
   #
   # MODULE:      50-myfeature
   # SUMMARY:     Short, one-line description of the module
   # DEPENDS:     05-packages
   # IDEMPOTENT:  yes
   # DESTRUCTIVE: no
   # ADDED:       1.1.0

   set -euo pipefail
   TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
   source "$TOOLKIT_ROOT/lib/common.sh"

   PLAN_MODE="${TOOLKIT_PLAN_MODE:-0}"
   ...
   ```

2. Make the script executable: `chmod +x scripts/50-myfeature.sh`.

---

## Code style

- **Always** `set -euo pipefail` at the top of executable scripts.
- **Always** quote variable expansions: `"$VAR"`, `"${ARRAY[@]}"`.
- Run `shellcheck -x -e SC1091,SC2034` on your script before committing.
- Use `log_info`/`log_warn`/`log_error` instead of `echo`.
- Use `pkg_install` / `system_file_install` rather than raw `apt-get` / `cp`.

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

**Always check state before changing state.** Examples:
- `pkg_install` already skips already-installed packages — use it
- `system_file_install` only writes when the source/destination differ
- For custom checks: `grep -q FOO /etc/file || sed -i '...' /etc/file`

**Honour `TOOLKIT_PLAN_MODE=1`:** when set, your module should print what it
*would* change but not perform writes.

**Distinguish critical vs non-critical errors:**
- Critical (data loss, broken system): `log_error "..."; exit 1`
- Non-critical (transient service issue): `log_warn "..."` and continue

---

## State persistence

State lives at `/var/log/toolkit-setup/.state` for the entire run and
survives reboots. Call `state_mark_complete` / `state_is_complete` to
read/write it; never hardcode the path.

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

Add a BATS test in `tests/` if your module exposes helper functions.

---

## Changelog maintenance

Every code change should include a corresponding entry in `CHANGELOG.md` under
the `Releases` section. The changelog follows the
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.

**When to update the changelog:**
- Any change to `scripts/`, `lib/`, `main.sh`, or `templates/`
- Bug fixes, new features, breaking changes, deprecations
- *Skip* for: README updates, docs-only changes (use `--no-verify` if needed)

**How to add a changelog entry:**

```markdown
## Releases

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

## Commit message format

Prefix the commit subject with the affected module in square brackets:

```
[06-hardening] add new sysctl rule for kernel.unprivileged_bpf_disabled
[lib/state] fix race when promoting state file
[lib/log] bump default log level
```

Keep the subject under 70 characters and explain the *why* in the body.

---

## Release and versioning

This project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html) as documented in `CHANGELOG.md`.

### For contributors: Version updates on pull requests

**Every pull request that changes code MUST update the VERSION file.**

Version numbering (choose one):
- **PATCH** (1.0.X): Bug fixes, documentation, small improvements
- **MINOR** (1.X.0): New features, new modules, new CLI flags (backwards-compatible)
- **MAJOR** (X.0.0): Breaking changes (module removal, config incompatibility)

**When creating a PR with code changes:**

1. **Determine the version bump**:
   - Current: `1.0.0` (from `cat VERSION`)
   - Adding new feature → `1.1.0` (MINOR bump)
   - Fixing a bug → `1.0.1` (PATCH bump)
   - Breaking change → `2.0.0` (MAJOR bump)

2. **Update VERSION file**:
   ```bash
   echo "1.1.0" > VERSION
   git add VERSION
   ```

3. **Update CHANGELOG.md** (under `Releases`):
   ```markdown
   ## Releases

   ### Added
   - New module 04-example for feature X

   ### Fixed
   - Bug in log_info under set -u

   ### Changed
   - Improved error messages in module Y
   ```

4. **Commit with version-aware message**:
   ```bash
   git commit -m "[04-example] add example module for new feature"
   # The VERSION and CHANGELOG updates go in the same commit
   ```

**Automatic validation:**
- A pre-commit hook (if installed via `scripts/setup-hooks.sh`) will block commits if code changed but VERSION wasn't updated
- GitHub Actions will verify VERSION was bumped on all PRs with code changes

**Setup development hooks** (recommended):
```bash
bash scripts/setup-hooks.sh
```

This installs a pre-commit hook that:
- ✅ Requires VERSION update for code changes
- ✅ Validates semantic versioning format
- ✅ Reminds you to update CHANGELOG.md

---

### For maintainers: Releasing a version

When preparing a release:

1. **Finalize CHANGELOG.md**: Move `Releases` content to a new `X.Y.Z – YYYY-MM-DD` section
   ```markdown
   ## 1.1.0 – 2026-05-20

   ### Added
   - New module 04-example

   ### Fixed
   - Bug fix in logging
   ```

2. **VERSION should already be updated** (from merged PRs)

3. **Create git tag**:
   ```bash
   git tag -a v1.1.0 -m "Release v1.1.0: Add example module"
   ```

4. **Push tag to GitHub**:
   ```bash
   git push origin v1.1.0
   ```
   GitHub will automatically create a Release page from the tag.

**Version retrieval at runtime:**
```bash
./main.sh --version
# Output: Ubuntu Server 26.04 LTS Configuration Toolkit v1.0.0

# or in a script:
source lib/version.sh
VERSION=$(toolkit_get_version)
```
