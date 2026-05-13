#!/usr/bin/env bash
# Ubuntu Server 26.04 LTS Configuration Toolkit - SPDX-License-Identifier: MIT
# Copyright (c) 2025 WildcatKSS
#
# lib/state.sh — Persistent module state tracking
#
# State file lives at $TOOLKIT_PERSISTENT_DIR/.state (default
# /var/log/toolkit-setup/.state) for the entire run.

: "${TOOLKIT_PERSISTENT_DIR:=/var/log/toolkit-setup}"

# state_active_path
# Echoes the path of the state file.
state_active_path() {
    echo "$TOOLKIT_PERSISTENT_DIR/.state"
}

# state_init
# Ensures the state file exists.
state_init() {
    mkdir -p "$TOOLKIT_PERSISTENT_DIR"
    touch "$TOOLKIT_PERSISTENT_DIR/.state"
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
