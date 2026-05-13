#!/usr/bin/env bash
# main.sh — Ubuntu Server 26.04 LTS Configuration Toolkit
#
# Auto-discovers scripts/*.sh, validates dependency DAG, and executes modules
# in alphabetical order. See README.md for full documentation.
#
# Usage:
#   ./main.sh [--list] [--plan] [--dry-run] [--resume] [--force]
#             [--retry=<module>] [--only=<module>] [--skip=<modules>]
#             [--ignore-errors]

set -euo pipefail

# ---------------------------------------------------------------------------
# Locate toolkit root and load helper library
# ---------------------------------------------------------------------------
TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TOOLKIT_ROOT

# shellcheck source=lib/common.sh
source "$TOOLKIT_ROOT/lib/common.sh"

# Path conventions
TOOLKIT_PERSISTENT_DIR="${TOOLKIT_PERSISTENT_DIR:-/var/log/toolkit-setup}"
TOOLKIT_LOG_FILE="${TOOLKIT_LOG_FILE:-$TOOLKIT_PERSISTENT_DIR/toolkit-setup.log}"
TOOLKIT_LOCK="/tmp/.toolkit-lock"
export TOOLKIT_PERSISTENT_DIR TOOLKIT_LOG_FILE

# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------
FLAG_LIST=0
FLAG_PLAN=0
FLAG_DRY_RUN=0
FLAG_RESUME=0
FLAG_FORCE=0
FLAG_IGNORE_ERRORS=0
ONLY_MODULE=""
SKIP_MODULES=""
RETRY_MODULE=""

usage() {
    cat <<'EOF'
Usage: ./main.sh [flags]

Inspection / preview:
  --list                Print discovered modules with metadata and exit.
  --plan                Read-only audit: modules report what they would change.
  --dry-run             Run scripts with bash -n (syntax check, no execution).

Execution control:
  --resume              Skip modules already recorded as complete.
  --force               Re-run all modules, even completed ones.
  --retry=<module>      Re-run a single previously-failed module (resolves deps).
  --only=<module>       Run only this module (and its prerequisites).
  --skip=<m1,m2,...>    Skip these modules (comma-separated short names).
  --ignore-errors       Continue when a non-critical module exits non-zero.

  -h, --help            Show this help and exit.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --list)           FLAG_LIST=1 ;;
        --plan)           FLAG_PLAN=1 ;;
        --dry-run)        FLAG_DRY_RUN=1 ;;
        --resume)         FLAG_RESUME=1 ;;
        --force)          FLAG_FORCE=1 ;;
        --ignore-errors)  FLAG_IGNORE_ERRORS=1 ;;
        --only=*)         ONLY_MODULE="${1#*=}" ;;
        --skip=*)         SKIP_MODULES="${1#*=}" ;;
        --retry=*)        RETRY_MODULE="${1#*=}" ;;
        -h|--help)        usage; exit 0 ;;
        *) log_error "Unknown flag: $1"; usage; exit 2 ;;
    esac
    shift
done

# Flag conflict resolution (documented in plan)
if [ "$FLAG_FORCE" -eq 1 ] && [ "$FLAG_RESUME" -eq 1 ]; then
    log_warn "--force and --resume both set; --force wins"
    FLAG_RESUME=0
fi

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
    done < <(find "$TOOLKIT_ROOT/scripts" -maxdepth 1 -type f -name '*.sh' | sort)
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
# Module execution
# ---------------------------------------------------------------------------
should_skip() {
    local short="$1"
    local item
    if [ -n "$SKIP_MODULES" ]; then
        IFS=',' read -ra arr <<< "$SKIP_MODULES"
        for item in "${arr[@]}"; do
            [ "${item// /}" = "$short" ] && return 0
        done
    fi
    if [ -n "$ONLY_MODULE" ] && [ -n "$RETRY_MODULE" ] && [ "$short" != "$ONLY_MODULE" ] && [ "$short" != "$RETRY_MODULE" ]; then
        return 0
    fi
    return 1
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
        log_info "Skipping $short (--skip / --only filter)"
        return 0
    fi

    if [ "$FLAG_FORCE" -eq 0 ] && [ "$FLAG_RESUME" -eq 1 ] && state_is_complete "$short"; then
        log_info "Skipping $short (already complete; use --force to re-run)"
        return 0
    fi

    if [ -n "$RETRY_MODULE" ] && [ "$short" != "$RETRY_MODULE" ] && state_is_complete "$short"; then
        log_info "Skipping $short (--retry only re-runs $RETRY_MODULE)"
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
    [ "$FLAG_PLAN" -eq 1 ] && env_vars+=("TOOLKIT_PLAN_MODE=1")

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
        echo "  - Re-run failed module: ./main.sh --retry=<module>"
        echo "  - Resume after fix:     ./main.sh --resume"
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
    export PLAN_MODE

    # Load and validate config
    local conf="$TOOLKIT_ROOT/config/defaults.conf"
    if [ ! -f "$conf" ]; then
        # Config doesn't exist; run questionnaire to generate it
        if [ "$FLAG_DRY_RUN" -eq 1 ] || [ "$FLAG_PLAN" -eq 1 ]; then
            log_error "Config missing: $conf (required for dry-run/plan)"
            log_error "Run interactively first: ./main.sh"
            exit 1
        fi
        log_info "Config file not found; running questionnaire to create it"
        questionnaire_run
        questionnaire_create_config "$TOOLKIT_ROOT"
    fi

    config_load "$conf" || exit 1
    config_validate || exit 1

    state_init

    # Run questionnaire for remaining prompts (admin user, etc.)
    # unless in plan mode or non-interactive
    questionnaire_run

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
