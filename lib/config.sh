#!/usr/bin/env bash
# Ubuntu Server 26.04 LTS Configuration Toolkit - SPDX-License-Identifier: MIT
# Copyright (c) 2025 WildcatKSS
#
# lib/config.sh — Configuration loading and validation

# config_load <path>
# Sources a config file with `set -a` so all variables become exported.
config_load() {
    local path="$1"
    if [ ! -f "$path" ]; then
        log_error "Config file not found: $path"
        return 1
    fi
    set -a
    # shellcheck disable=SC1090
    source "$path"
    set +a
    log_info "Loaded config from $path"
}

_config_is_valid_ipv4() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    local IFS=.
    # shellcheck disable=SC2206
    local parts=( $ip )
    for part in "${parts[@]}"; do
        [ "$part" -ge 0 ] && [ "$part" -le 255 ] || return 1
    done
    return 0
}

_config_is_valid_email() {
    [[ "$1" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

_config_is_valid_hostname() {
    [[ "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]{0,253}[a-zA-Z0-9])?$ ]]
}

# config_validate
# Validates required variables loaded from defaults.conf.
config_validate() {
    local errors=0

    for var in HOSTNAME EMAIL_TO NETWORK_INTERFACE; do
        if [ -z "${!var:-}" ]; then
            log_error "Required config variable not set: $var"
            errors=$((errors + 1))
        fi
    done

    if [ -n "${HOSTNAME:-}" ] && ! _config_is_valid_hostname "$HOSTNAME"; then
        log_error "Invalid HOSTNAME: $HOSTNAME"
        errors=$((errors + 1))
    fi

    if [ -n "${EMAIL_TO:-}" ] && ! _config_is_valid_email "$EMAIL_TO"; then
        log_error "Invalid EMAIL_TO: $EMAIL_TO"
        errors=$((errors + 1))
    fi

    if [ "${USE_DHCP:-true}" = "false" ]; then
        for var in IP_ADDRESS GATEWAY PREFIX_LENGTH DNS_SERVERS; do
            if [ -z "${!var:-}" ]; then
                log_error "USE_DHCP=false but $var is not set"
                errors=$((errors + 1))
            fi
        done
        if [ -n "${IP_ADDRESS:-}" ] && ! _config_is_valid_ipv4 "$IP_ADDRESS"; then
            log_error "Invalid IP_ADDRESS: $IP_ADDRESS"
            errors=$((errors + 1))
        fi
        if [ -n "${GATEWAY:-}" ] && ! _config_is_valid_ipv4 "$GATEWAY"; then
            log_error "Invalid GATEWAY: $GATEWAY"
            errors=$((errors + 1))
        fi
    fi

    if [ "$errors" -gt 0 ]; then
        log_error "Config validation failed with $errors error(s)"
        return 1
    fi
    log_info "Config validation passed"
    return 0
}
