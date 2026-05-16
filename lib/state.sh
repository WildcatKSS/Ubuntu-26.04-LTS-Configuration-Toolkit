#!/usr/bin/env bash
# Ubuntu Server 26.04 LTS Configuration Toolkit - SPDX-License-Identifier: MIT
# Copyright (c) 2026 WildcatKSS
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
# Echoes a human-readable summary of completed modules with execution times.
state_summary() {
    local path
    path="$(state_active_path)"
    if [ ! -s "$path" ]; then
        echo "(no modules completed yet)"
        return 0
    fi

    printf "  %-30s %-20s %s\n" "Module" "Completed At" "Duration"
    printf "  %-30s %-20s %s\n" "------" "------------" "--------"

    local module ts curr_sec dur d
    local first_sec=0 last_sec=0 prev_sec=0
    while IFS=$'\t' read -r module ts; do
        curr_sec=$(date -d "$ts" +%s 2>/dev/null || echo 0)
        dur=""
        if [ "$prev_sec" -gt 0 ] && [ "$curr_sec" -gt 0 ]; then
            d=$((curr_sec - prev_sec))
            [ "$d" -lt 1 ] && d=1
            dur="${d}s"
        fi
        [ "$first_sec" -eq 0 ] && first_sec=$curr_sec
        last_sec=$curr_sec
        prev_sec=$curr_sec
        printf "  %-30s %-20s %s\n" "$module" "$ts" "$dur"
    done < "$path"

    if [ "$first_sec" -gt 0 ] && [ "$last_sec" -gt "$first_sec" ]; then
        printf "\n  Total execution time: %d seconds\n" $((last_sec - first_sec))
    fi
}
