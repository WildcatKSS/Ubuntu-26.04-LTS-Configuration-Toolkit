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
    if [ ! -f "$path" ] || [ ! -s "$path" ]; then
        echo "(no modules completed yet)"
        return 0
    fi

    # Print header
    printf "  %-30s %-20s %s\n" "Module" "Completed At" "Duration"
    printf "  %-30s %-20s %s\n" "------" "------------" "--------"

    # Process state file and calculate durations
    local prev_time=""
    awk -F'\t' '
    BEGIN { prev_time = "" }
    {
        module = $1
        curr_time = $2

        # Calculate duration if we have a previous time
        duration = ""
        if (prev_time != "") {
            cmd = "date -d \"" prev_time "\" +%s 2>/dev/null"
            cmd | getline prev_sec
            close(cmd)
            cmd = "date -d \"" curr_time "\" +%s 2>/dev/null"
            cmd | getline curr_sec
            close(cmd)

            if (prev_sec != "" && curr_sec != "") {
                diff = curr_sec - prev_sec
                if (diff < 1) diff = 1
                duration = diff "s"
            }
        }

        printf "  %-30s %-20s %s\n", module, curr_time, duration
        prev_time = curr_time
    }
    ' "$path"

    # Print total execution time
    echo
    local first_time last_time
    first_time=$(head -1 "$path" | cut -f2)
    last_time=$(tail -1 "$path" | cut -f2)

    if [ -n "$first_time" ] && [ -n "$last_time" ] && command -v date >/dev/null 2>&1; then
        local first_sec last_sec total_sec
        first_sec=$(date -d "$first_time" +%s 2>/dev/null || echo 0)
        last_sec=$(date -d "$last_time" +%s 2>/dev/null || echo 0)
        if [ "$first_sec" -gt 0 ] && [ "$last_sec" -gt 0 ]; then
            total_sec=$((last_sec - first_sec))
            if [ "$total_sec" -lt 1 ]; then
                total_sec=1
            fi
            printf "  Total execution time: %d seconds\n" "$total_sec"
        fi
    fi
}
