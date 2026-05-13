#!/usr/bin/env bash
# Ubuntu Server 26.04 LTS Configuration Toolkit - SPDX-License-Identifier: MIT
# Copyright (c) 2025 WildcatKSS
#
# lib/log.sh — Logging utilities
#
# Provides:
#   log_debug / log_info / log_warn / log_error
#   log_check_diskspace
#
# Log level filtering via TOOLKIT_LOG_LEVEL (default: info):
#   debug  — show DEBUG, INFO, WARN, ERROR
#   info   — show INFO, WARN, ERROR  (default)
#   warn   — show WARN, ERROR
#   error  — show ERROR only

# Color codes (only used when output is a tty)
if [ -t 1 ]; then
    readonly _LOG_COLOR_RESET="\033[0m"
    readonly _LOG_COLOR_DEBUG="\033[0;36m"
    readonly _LOG_COLOR_INFO="\033[0;32m"
    readonly _LOG_COLOR_WARN="\033[0;33m"
    readonly _LOG_COLOR_ERROR="\033[0;31m"
else
    readonly _LOG_COLOR_RESET=""
    readonly _LOG_COLOR_DEBUG=""
    readonly _LOG_COLOR_INFO=""
    readonly _LOG_COLOR_WARN=""
    readonly _LOG_COLOR_ERROR=""
fi

# Active log file path (set by main.sh; defaults to stderr only)
: "${TOOLKIT_LOG_FILE:=}"
# Minimum log level: debug | info | warn | error  (default: info)
: "${TOOLKIT_LOG_LEVEL:=info}"

# Returns 0 when <level> should be emitted given TOOLKIT_LOG_LEVEL.
_log_level_enabled() {
    local level="$1"
    case "${TOOLKIT_LOG_LEVEL,,}" in
        debug) return 0 ;;
        info)  [[ "$level" == "INFO"  || "$level" == "WARN" || "$level" == "ERROR" ]] && return 0 ;;
        warn)  [[ "$level" == "WARN"  || "$level" == "ERROR" ]] && return 0 ;;
        error) [[ "$level" == "ERROR" ]] && return 0 ;;
    esac
    return 1
}

_log_write() {
    local level="$1"
    local color="$2"
    local message="$3"
    _log_level_enabled "$level" || return 0
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    # Identify the source file that emitted the log. With nested helper
    # calls (main.sh -> run_module -> log_info -> _log_write) the original
    # script sits at BASH_SOURCE[3]; for direct calls from a module body
    # the stack is one shorter, so fall back to BASH_SOURCE[2]. Both must
    # tolerate `set -u` from the calling shell.
    local caller="${BASH_SOURCE[3]:-${BASH_SOURCE[2]:-}}"
    caller="${caller##*/}"
    [ -z "$caller" ] && caller="main.sh"
    local line="[$timestamp] [$level] [$caller] $message"
    printf '%b%s%b\n' "$color" "$line" "$_LOG_COLOR_RESET" >&2
    if [ -n "$TOOLKIT_LOG_FILE" ]; then
        printf '%s\n' "$line" >> "$TOOLKIT_LOG_FILE" 2>/dev/null || true
    fi
}

log_debug() { _log_write "DEBUG" "$_LOG_COLOR_DEBUG" "$*"; }
log_info()  { _log_write "INFO"  "$_LOG_COLOR_INFO"  "$*"; }
log_warn()  { _log_write "WARN"  "$_LOG_COLOR_WARN"  "$*"; }
log_error() {
    _log_write "ERROR" "$_LOG_COLOR_ERROR" "$*"
    if [ -n "$TOOLKIT_LOG_FILE" ]; then
        printf 'FAILURE: Run grep ERROR %s for details\n' "$TOOLKIT_LOG_FILE" >&2
    fi
}

# log_check_diskspace <path> [min_mb]
# Warns when free space at <path> drops below threshold (default 100 MB)
log_check_diskspace() {
    local path="${1:-/tmp}"
    local min_mb="${2:-100}"
    local free_mb
    free_mb="$(df -m --output=avail "$path" 2>/dev/null | awk 'NR==2 {print $1}')"
    if [ -z "$free_mb" ]; then
        log_warn "Could not determine free space for $path"
        return 0
    fi
    if [ "$free_mb" -lt "$min_mb" ]; then
        log_warn "Low disk space at $path: ${free_mb}MB free (threshold ${min_mb}MB)"
        return 1
    fi
    return 0
}
