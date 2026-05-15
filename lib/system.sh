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

# system_get_active_services [service_list...]
# Scans for active services and returns space-separated list of running ones.
# Usage: active=$(system_get_active_services ssh postfix dovecot)
# Example result: "ssh postfix"  (dovecot not running)
system_get_active_services() {
    local services=("$@")
    local active_list=()

    for svc in "${services[@]}"; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            active_list+=("$svc")
        fi
    done

    echo "${active_list[@]}"
}

# system_service_is_loaded <service>
# Checks if a service unit file is loaded (exists and can be managed by systemd)
system_service_is_loaded() {
    local svc="$1"
    systemctl show -p LoadState --value "$svc" 2>/dev/null | grep -q "^loaded"
}

# system_service_is_masked <service>
# Checks if a service is masked (disabled from starting)
system_service_is_masked() {
    local svc="$1"
    systemctl is-enabled "$svc" 2>/dev/null | grep -q masked
}

# system_backup_file <path>
# Creates idempotent backup of a file with .toolkit.bak extension
# Only backs up if backup doesn't already exist
system_backup_file() {
    local src="$1"
    if [ -f "$src" ] && [ ! -f "${src}.toolkit.bak" ]; then
        cp "$src" "${src}.toolkit.bak"
        log_info "Backed up: ${src}.toolkit.bak"
    fi
}

# system_restore_file <path>
# Restores a file from its .toolkit.bak backup
system_restore_file() {
    local dst="$1"
    if [ -f "${dst}.toolkit.bak" ]; then
        cp "${dst}.toolkit.bak" "$dst"
        log_info "Restored from backup: $dst"
    fi
}

# system_install_from_template <template> <target> <env_vars> [mode]
# Render template with envsubst, compare, install idempotently
# Args:
#   template: Source template file path
#   target: Destination file path
#   env_vars: Space-separated var names for envsubst (e.g., "VAR1 VAR2"). Use "" for no substitution.
#   mode: File permission mode (default: 0644)
# Returns: 0 if installed/unchanged, 1 on error, 2 if file was already up-to-date (no change)
# Usage:
#   system_install_from_template "$template" "$target" "HOSTNAME DOMAIN" 0644
#   system_install_from_template "$template" "$target" "" 0644  # No substitution
system_install_from_template() {
    local template="$1"
    local target="$2"
    local env_vars="${3:-}"
    local mode="${4:-0644}"
    local tmp
    local vars_with_dollar

    if [ ! -f "$template" ]; then
        log_error "Template missing: $template"
        return 1
    fi

    tmp="$(mktemp)"
    if [ -n "$env_vars" ]; then
        # envsubst requires variable names with $ prefix (e.g., "$VAR1 $VAR2")
        # Prepend $ to each variable name
        vars_with_dollar=""
        local var
        for var in $env_vars; do
            vars_with_dollar="${vars_with_dollar:+$vars_with_dollar }$"$var
        done
        # shellcheck disable=SC2086
        envsubst "$vars_with_dollar" < "$template" > "$tmp"
    else
        cat "$template" > "$tmp"
    fi

    if [ -f "$target" ] && cmp -s "$tmp" "$target"; then
        log_info "File unchanged: $target"
        rm -f "$tmp"
        return 2
    fi

    system_backup_file "$target"
    install -m "$mode" "$tmp" "$target"
    rm -f "$tmp"
    log_info "Installed: $target (mode $mode)"
    return 0
}

# system_write_file <target> <mode> [heredoc_stdin]
# Write stdin to file idempotently (with heredoc support)
# Returns: 0 if installed/changed, 1 on error, 2 if file was already up-to-date (no change)
# Usage: system_write_file /etc/file 0644 <<'EOF'
#        content here
#        EOF
system_write_file() {
    local target="$1"
    local mode="${2:-0644}"
    local tmp

    tmp="$(mktemp)"
    cat > "$tmp"

    if [ -f "$target" ] && cmp -s "$tmp" "$target"; then
        log_info "File unchanged: $target"
        rm -f "$tmp"
        return 2
    fi

    system_backup_file "$target"
    install -m "$mode" "$tmp" "$target"
    rm -f "$tmp"
    log_info "Wrote: $target (mode $mode)"
    return 0
}

# system_verify_ubuntu_26
# Verifies system is Ubuntu Server 26.04 LTS (single grep for efficiency)
system_verify_ubuntu_26() {
    [ -f /etc/os-release ] || return 1
    grep -q 'VERSION_ID="26\.04"' /etc/os-release && grep -q '^ID=ubuntu' /etc/os-release
}
