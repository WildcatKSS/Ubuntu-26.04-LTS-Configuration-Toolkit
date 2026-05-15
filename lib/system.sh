#!/usr/bin/env bash
# Ubuntu Server 26.04 LTS Configuration Toolkit - SPDX-License-Identifier: MIT
# Copyright (c) 2026 WildcatKSS
#
# lib/system.sh — System-level utility helpers

# system_check_root
# Aborts the calling script if not running as root.
system_check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        return 1
    fi
}

# system_confirm <question> [default]
# Prompts user for yes/no. Default may be "yes" or "no".
# Returns 0 (yes) or 1 (no). Honours TOOLKIT_NONINTERACTIVE=1 to use default.
system_confirm() {
    local question="$1"
    local default="${2:-no}"
    local prompt
    case "$default" in
        yes) prompt="[Y/n]" ;;
        *)   prompt="[y/N]" ;;
    esac

    if [ "${TOOLKIT_NONINTERACTIVE:-0}" = "1" ]; then
        log_info "Non-interactive mode: using default '$default' for: $question"
        [ "$default" = "yes" ]
        return $?
    fi

    local answer
    while true; do
        printf '%s %s ' "$question" "$prompt" >&2
        if ! read -r answer; then
            answer=""
        fi
        answer="${answer:-$default}"
        case "$answer" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo])     return 1 ;;
            *) printf 'Please answer yes or no.\n' >&2 ;;
        esac
    done
}

# system_user_exists <username>
system_user_exists() {
    id -u "$1" >/dev/null 2>&1
}

# system_service_enable_start <service>
# Enables and starts a service, idempotently.
# Returns 0 on success, 1 if start failed (logged WARN, non-fatal).
system_service_enable_start() {
    local svc="$1"
    if systemctl is-active --quiet "$svc"; then
        log_info "Service already active: $svc"
        return 0
    fi
    if ! systemctl enable --now "$svc" 2>/dev/null; then
        log_warn "Failed to enable/start service: $svc"
        return 1
    fi
    log_info "Enabled and started: $svc"
    return 0
}

# system_service_mask <service>
system_service_mask() {
    local svc="$1"
    if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
        systemctl disable --now "$svc" 2>/dev/null || true
    fi
    if ! systemctl is-enabled "$svc" 2>/dev/null | grep -q masked; then
        systemctl mask "$svc" 2>/dev/null || log_warn "Could not mask service: $svc"
    fi
}

# system_file_install <src> <dst> [mode]
# Copies <src> to <dst> only if content differs (idempotent).
system_file_install() {
    local src="$1"
    local dst="$2"
    local mode="${3:-0644}"
    if [ ! -f "$src" ]; then
        log_error "Template missing: $src"
        return 1
    fi
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        log_info "File unchanged: $dst"
        return 0
    fi
    install -m "$mode" "$src" "$dst"
    log_info "Installed: $dst (mode $mode)"
}
