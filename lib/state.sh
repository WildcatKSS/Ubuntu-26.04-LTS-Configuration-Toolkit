#!/usr/bin/env bash
# lib/state.sh — Persistent module state tracking
#
# State file location is dynamic:
#   - Before script 02 mounts /var/log: $TOOLKIT_TEMP_DIR/.state
#   - After script 02:                   $TOOLKIT_PERSISTENT_DIR/.state
# state_active_path resolves the active path on each call.

: "${TOOLKIT_TEMP_DIR:=/tmp/toolkit-setup}"
: "${TOOLKIT_PERSISTENT_DIR:=/var/log/toolkit-setup}"

# state_active_path
# Echoes the path of the active state file.
state_active_path() {
    if [ -f "$TOOLKIT_PERSISTENT_DIR/.state" ]; then
        echo "$TOOLKIT_PERSISTENT_DIR/.state"
    else
        echo "$TOOLKIT_TEMP_DIR/.state"
    fi
}

# state_init
# Ensures the temp state file exists.
state_init() {
    mkdir -p "$TOOLKIT_TEMP_DIR"
    touch "$TOOLKIT_TEMP_DIR/.state"
}

# state_mark_complete <module-name>
state_mark_complete() {
    local module="$1"
    local path
    path="$(state_active_path)"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    state_clear "$module"
    printf '%s\t%s\n' "$module" "$timestamp" >> "$path"
}

# state_is_complete <module-name>
# Returns 0 if completed, 1 otherwise.
state_is_complete() {
    local module="$1"
    local path
    path="$(state_active_path)"
    [ -f "$path" ] || return 1
    grep -q "^${module}\b" "$path"
}

# state_clear <module-name>
state_clear() {
    local module="$1"
    local path
    path="$(state_active_path)"
    [ -f "$path" ] || return 0
    grep -v "^${module}\b" "$path" > "${path}.tmp" 2>/dev/null || true
    mv "${path}.tmp" "$path"
}

# state_promote
# Migrates the temp state file to its persistent location after script 02.
# Safe to call multiple times.
state_promote() {
    local src="$TOOLKIT_TEMP_DIR/.state"
    local dst="$TOOLKIT_PERSISTENT_DIR/.state"
    if [ -f "$dst" ]; then
        return 0
    fi
    if [ ! -f "$src" ]; then
        log_warn "Cannot promote state: no temp state file at $src"
        return 1
    fi
    mkdir -p "$TOOLKIT_PERSISTENT_DIR"
    mv "$src" "$dst"
    log_info "State migrated to persistent location: $dst"
}

# state_summary
# Echoes a human-readable summary of completed modules.
state_summary() {
    local path
    path="$(state_active_path)"
    if [ ! -f "$path" ] || [ ! -s "$path" ]; then
        echo "(no modules completed yet)"
        return 0
    fi
    awk -F'\t' '{ printf "  %-30s %s\n", $1, $2 }' "$path"
}
