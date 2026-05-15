#!/usr/bin/env bash
# Ubuntu Server 26.04 LTS Configuration Toolkit
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 WildcatKSS
#
# This program is licensed under the MIT License.
# For the full license text, see LICENSE in the root directory.
#
# main.sh — Auto-discovers scripts/*.sh, validates dependency DAG, and executes
# modules in alphabetical order. See README.md for full documentation.
#
# Usage:
#   ./main.sh [--list] [--plan] [--dry-run] [--test] [--resume] [--force]
#             [--ignore-errors]

set -euo pipefail

# ---------------------------------------------------------------------------
# Locate toolkit root and load helper library
# ---------------------------------------------------------------------------
TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TOOLKIT_ROOT

# shellcheck source=lib/common.sh
source "$TOOLKIT_ROOT/lib/common.sh"

# shellcheck source=lib/version.sh
source "$TOOLKIT_ROOT/lib/version.sh"

# Path conventions
TOOLKIT_PERSISTENT_DIR="${TOOLKIT_PERSISTENT_DIR:-/var/log/toolkit-setup}"
TOOLKIT_LOG_FILE="${TOOLKIT_LOG_FILE:-$TOOLKIT_PERSISTENT_DIR/toolkit-setup.log}"
TOOLKIT_LOCK="/tmp/.toolkit-lock"
export TOOLKIT_PERSISTENT_DIR TOOLKIT_LOG_FILE

# Best-effort: create the log dir so logs land in the file from the start.
# Silent failure is fine — log.sh skips file writes when the dir is missing.
mkdir -p "$TOOLKIT_PERSISTENT_DIR" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------
FLAG_LIST=0
FLAG_PLAN=0
FLAG_DRY_RUN=0
FLAG_TEST=0
FLAG_RESUME=0
FLAG_FORCE=0
FLAG_IGNORE_ERRORS=0

usage() {
    cat <<'EOF'
Usage: ./main.sh [flags]

Inspection / preview:
  --list                Print discovered modules with metadata and exit.
  --plan                Read-only audit: modules report what they would change.
  --dry-run             Run scripts with bash -n (syntax check, no execution).
  --test                Run syntax checks, linting, and BATS tests. Can combine
                        with --plan or --dry-run.

Execution control:
  --resume              Skip modules already recorded as complete.
  --force               Re-run all modules, even completed ones.
  --ignore-errors       Continue when a non-critical module exits non-zero.

  -h, --help            Show this help and exit.
  -v, --version         Show version and exit.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --list)           FLAG_LIST=1 ;;
        --plan)           FLAG_PLAN=1 ;;
        --dry-run)        FLAG_DRY_RUN=1 ;;
        --test)           FLAG_TEST=1 ;;
        --resume)         FLAG_RESUME=1 ;;
        --force)          FLAG_FORCE=1 ;;
        --ignore-errors)  FLAG_IGNORE_ERRORS=1 ;;
        -h|--help)        usage; exit 0 ;;
        -v|--version)     toolkit_version_info; exit 0 ;;
        *) log_error "Unknown flag: $1"; usage; exit 2 ;;
    esac
    shift
done

# Flag conflict resolution (documented in plan)
if [ "$FLAG_FORCE" -eq 1 ] && [ "$FLAG_RESUME" -eq 1 ]; then
    log_warn "--force and --resume both set; --force wins"
    FLAG_RESUME=0
fi

# Selected modules (filled by questionnaire)
declare -a SELECTED_MODULES=()

# ---------------------------------------------------------------------------
# Module discovery and metadata
# ---------------------------------------------------------------------------
declare -a MODULE_PATHS=()
declare -A MODULE_NAME      # path -> short module name (no .sh suffix, no dir)
declare -A MODULE_DESC
declare -A MODULE_DEPENDS
declare -A MODULE_IDEMPOTENT
declare -A MODULE_DESTRUCTIVE

discover_modules() {
    local path
    while IFS= read -r path; do
        MODULE_PATHS+=("$path")
        local short
        short="$(basename "$path" .sh)"
        MODULE_NAME[$path]="$short"
        # Parse metadata header (first 20 lines)
        local desc="" deps="" idem="unknown" destr="unknown"
        local line
        while IFS= read -r line; do
            case "$line" in
                "# DESC:"*)        desc="${line#"# DESC:"}"; desc="${desc# }" ;;
                "# DEPENDS:"*)     deps="${line#"# DEPENDS:"}"; deps="${deps# }" ;;
                "# IDEMPOTENT:"*)  idem="${line#"# IDEMPOTENT:"}"; idem="${idem# }" ;;
                "# DESTRUCTIVE:"*) destr="${line#"# DESTRUCTIVE:"}"; destr="${destr# }" ;;
            esac
        done < <(head -n 20 "$path")
        MODULE_DESC[$short]="$desc"
        MODULE_DEPENDS[$short]="$deps"
        MODULE_IDEMPOTENT[$short]="$idem"
        MODULE_DESTRUCTIVE[$short]="$destr"
    done < <(find "$TOOLKIT_ROOT/scripts" -maxdepth 1 -type f -name '[0-9][0-9]-*.sh' | sort)
}

# Validate DAG: detect missing dependency targets and cycles.
validate_dag() {
    local short deps dep ok=0
    local -A all_short=()
    for short in "${MODULE_NAME[@]}"; do
        all_short[$short]=1
    done

    # Missing-target check
    for short in "${!MODULE_DEPENDS[@]}"; do
        deps="${MODULE_DEPENDS[$short]}"
        [ -z "$deps" ] && continue
        IFS=',' read -ra arr <<< "$deps"
        for dep in "${arr[@]}"; do
            dep="${dep// /}"
            if [ -z "${all_short[$dep]:-}" ]; then
                log_error "Module $short depends on missing module: $dep"
                ok=1
            fi
        done
    done

    # Cycle detection via Kahn's algorithm
    local -A indeg=()
    local -A adj=()
    for short in "${!MODULE_DEPENDS[@]}"; do
        indeg[$short]="${indeg[$short]:-0}"
        deps="${MODULE_DEPENDS[$short]}"
        [ -z "$deps" ] && continue
        IFS=',' read -ra arr <<< "$deps"
        for dep in "${arr[@]}"; do
            dep="${dep// /}"
            adj[$dep]+="$short "
            indeg[$short]=$(( ${indeg[$short]:-0} + 1 ))
        done
    done

    local -a queue=()
    local s
    for s in "${!all_short[@]}"; do
        [ "${indeg[$s]:-0}" -eq 0 ] && queue+=("$s")
    done

    local processed=0
    while [ "${#queue[@]}" -gt 0 ]; do
        local current="${queue[0]}"
        queue=("${queue[@]:1}")
        processed=$((processed + 1))
        local children="${adj[$current]:-}"
        for child in $children; do
            indeg[$child]=$(( indeg[$child] - 1 ))
            [ "${indeg[$child]}" -eq 0 ] && queue+=("$child")
        done
    done

    if [ "$processed" -ne "${#all_short[@]}" ]; then
        log_error "Dependency cycle detected among modules"
        ok=1
    fi

    return "$ok"
}

print_listing() {
    local path short
    echo
    echo "Discovered modules:"
    echo "===================="
    for path in "${MODULE_PATHS[@]}"; do
        short="${MODULE_NAME[$path]}"
        printf '\n%s\n' "$short"
        printf '  DESC:        %s\n' "${MODULE_DESC[$short]:-(none)}"
        printf '  DEPENDS:     %s\n' "${MODULE_DEPENDS[$short]:-(none)}"
        printf '  IDEMPOTENT:  %s\n' "${MODULE_IDEMPOTENT[$short]:-unknown}"
        printf '  DESTRUCTIVE: %s\n' "${MODULE_DESTRUCTIVE[$short]:-unknown}"
    done
    echo
}

# ---------------------------------------------------------------------------
# Testing
# ---------------------------------------------------------------------------
install_test_deps() {
    local failed=0

    if ! command -v shellcheck >/dev/null 2>&1; then
        log_info "Installing ShellCheck..."
        if apt-get install -y shellcheck >/dev/null 2>&1; then
            log_info "  ✓ ShellCheck installed"
        else
            log_warn "  ⊘ Failed to install ShellCheck (may require root)"
            failed=1
        fi
    fi

    if ! command -v bats >/dev/null 2>&1; then
        log_info "Installing BATS..."
        if apt-get install -y bats >/dev/null 2>&1; then
            log_info "  ✓ BATS installed"
        else
            log_warn "  ⊘ Failed to install BATS (may require root)"
            failed=1
        fi
    fi

    if ! command -v envsubst >/dev/null 2>&1; then
        log_info "Installing gettext-base..."
        if apt-get install -y gettext-base >/dev/null 2>&1; then
            log_info "  ✓ gettext-base installed"
        else
            log_warn "  ⊘ Failed to install gettext-base (may require root)"
            failed=1
        fi
    fi

    return "$failed"
}

run_tests() {
    local failed=0

    log_info "Running test suite..."
    echo

    install_test_deps || true
    echo

    # Syntax checks
    log_info "[1/3] Bash syntax checks..."
    if bash -n scripts/*.sh lib/*.sh main.sh 2>&1; then
        log_info "  ✓ Syntax checks passed"
    else
        log_error "  ✗ Syntax checks failed"
        failed=1
    fi
    echo

    # ShellCheck linting
    log_info "[2/3] ShellCheck linting..."
    if command -v shellcheck >/dev/null 2>&1; then
        if shellcheck -x -e SC1091,SC2034 scripts/*.sh lib/*.sh main.sh 2>&1; then
            log_info "  ✓ ShellCheck passed"
        else
            log_error "  ✗ ShellCheck found issues"
            failed=1
        fi
    else
        log_warn "  ⊘ ShellCheck not available; skipping"
    fi
    echo

    # BATS unit tests
    log_info "[3/3] BATS unit tests..."
    if command -v bats >/dev/null 2>&1; then
        if bats tests/ 2>&1; then
            log_info "  ✓ BATS tests passed"
        else
            log_error "  ✗ BATS tests failed"
            failed=1
        fi
    else
        log_warn "  ⊘ BATS not available; skipping"
    fi
    echo

    if [ "$failed" -eq 1 ]; then
        log_error "Test suite failed"
        return 1
    fi

    log_info "All tests passed"
    return 0
}

# ---------------------------------------------------------------------------
# Module execution
# ---------------------------------------------------------------------------
should_skip() {
    local short="$1"
    local item
    for item in "${SELECTED_MODULES[@]}"; do
        [ "$item" = "$short" ] && return 1
    done
    return 0
}

run_hook() {
    local hook="$1"
    [ -f "$hook" ] || return 0
    log_info "Running hook: $(basename "$hook")"
    if ! bash "$hook"; then
        log_error "Hook failed (non-fatal): $(basename "$hook")"
    fi
}

run_module() {
    local path="$1"
    local short="${MODULE_NAME[$path]}"

    if should_skip "$short"; then
        log_info "Skipping $short (not selected)"
        return 0
    fi

    if [ "$FLAG_FORCE" -eq 0 ] && [ "$FLAG_RESUME" -eq 1 ] && state_is_complete "$short"; then
        log_info "Skipping $short (already complete; use --force to re-run)"
        return 0
    fi

    if [ "$FLAG_DRY_RUN" -eq 1 ]; then
        log_info "Dry-run syntax check: $short"
        if ! bash -n "$path"; then
            log_error "Syntax check failed for $short"
            return 1
        fi
        return 0
    fi

    run_hook "$TOOLKIT_ROOT/scripts/hooks/pre-${short}.sh"

    log_info "===== START $short ====="
    local start_ts
    start_ts="$(date '+%Y-%m-%d %H:%M:%S')"
    local rc=0
    local env_vars=("TOOLKIT_ROOT=$TOOLKIT_ROOT")
    if [ "$FLAG_PLAN" -eq 1 ] || [ "$FLAG_DRY_RUN" -eq 1 ]; then
        env_vars+=("TOOLKIT_PLAN_MODE=1")
    fi

    if env "${env_vars[@]}" bash "$path"; then
        log_info "===== END   $short (started $start_ts; ok) ====="
        state_mark_complete "$short"
    else
        rc=$?
        log_error "===== FAIL  $short (started $start_ts; exit $rc) ====="
        if [ "$FLAG_IGNORE_ERRORS" -eq 0 ]; then
            return "$rc"
        fi
        log_warn "--ignore-errors set; continuing despite failure in $short"
    fi

    run_hook "$TOOLKIT_ROOT/scripts/hooks/post-${short}.sh"

    return 0
}

# ---------------------------------------------------------------------------
# Cleanup trap
# ---------------------------------------------------------------------------
cleanup() {
    local rc=$?
    if [ -d "$TOOLKIT_LOCK" ]; then
        rmdir "$TOOLKIT_LOCK" 2>/dev/null || true
    fi
    if [ "$rc" -ne 0 ]; then
        log_error "Toolkit exited with status $rc"
        echo
        echo "Recovery hints:"
        echo "  - Inspect log: $TOOLKIT_LOG_FILE"
        echo "  - Resume after fix:     ./main.sh --resume"
        echo "  - Re-run all modules:   ./main.sh --force"
    fi
    return 0
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    discover_modules
    if [ "${#MODULE_PATHS[@]}" -eq 0 ]; then
        log_error "No modules found in $TOOLKIT_ROOT/scripts/"
        exit 1
    fi

    if ! validate_dag; then
        exit 2
    fi

    log_info "$(toolkit_version_info)"

    # Run tests only if explicitly requested with --test flag
    if [ "$FLAG_TEST" -eq 1 ]; then
        if ! run_tests; then
            exit 2
        fi
    fi

    if [ "$FLAG_LIST" -eq 1 ]; then
        print_listing
        exit 0
    fi

    # Acquire lock to prevent concurrent runs
    if ! mkdir "$TOOLKIT_LOCK" 2>/dev/null; then
        log_error "Another toolkit run is in progress (lock: $TOOLKIT_LOCK)"
        exit 3
    fi

    # Prepare persistent log dir + state file
    mkdir -p "$TOOLKIT_PERSISTENT_DIR"
    log_check_diskspace "$TOOLKIT_PERSISTENT_DIR" 100 || true

    if [ "$FLAG_DRY_RUN" -eq 0 ] && [ "$FLAG_PLAN" -eq 0 ]; then
        system_check_root || exit 1
    fi

    # Load questionnaire library early for config generation
    # shellcheck source=lib/questionnaire.sh
    source "$TOOLKIT_ROOT/lib/questionnaire.sh"
    if [ "$FLAG_PLAN" -eq 1 ] || [ "$FLAG_DRY_RUN" -eq 1 ]; then
        export TOOLKIT_PLAN_MODE=1
    fi

    # Load and validate config
    local conf="$TOOLKIT_ROOT/config/defaults.conf"
    local _questionnaire_done=0
    if [ ! -f "$conf" ]; then
        # Config doesn't exist
        if [ "$FLAG_DRY_RUN" -eq 1 ] || [ "$FLAG_PLAN" -eq 1 ]; then
            # For plan/dry-run, use sensible defaults and skip interactive questionnaire
            log_info "Config missing; using sensible defaults for plan/dry-run mode"
            config_create_defaults
            _questionnaire_done=1
        else
            # For interactive mode, will prompt after module selection
            log_info "Config file not found; will create after module selection"
            _questionnaire_done=0
        fi
    else
        config_load "$conf" || exit 1
        config_validate || exit 1
    fi

    state_init

    # Ask user to select modules BEFORE running full questionnaire
    # This way, module selection appears first, and questionnaire only asks
    # for config relevant to selected modules
    log_info "Loading module selection..."
    while IFS= read -r module; do
        SELECTED_MODULES+=("$module")
    done < <(questionnaire_ask_modules)

    # Run questionnaire for interactive setup unless already done (plan/dry-run modes)
    if [ "$_questionnaire_done" -eq 0 ]; then
        # Pass selected modules to questionnaire so it can skip irrelevant sections
        local selected_csv
        selected_csv="$(printf '%s,' "${SELECTED_MODULES[@]}" | sed 's/,$//')"
        questionnaire_run "$selected_csv"
        questionnaire_create_config "$TOOLKIT_ROOT"
        config_load "$conf" || exit 1
        config_validate || exit 1
    fi

    # Run modules
    local path
    for path in "${MODULE_PATHS[@]}"; do
        run_module "$path" || exit $?
    done

    echo
    log_info "All modules completed. Summary:"
    state_summary
    if [ -f /var/run/reboot-required ]; then
        log_warn "Reboot required to finalise kernel/system upgrades."
    fi
}

main "$@"
