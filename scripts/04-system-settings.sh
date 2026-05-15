#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 WildcatKSS
# Ubuntu Server 26.04 LTS Configuration Toolkit
#
# MODULE:      04-system-settings
# SUMMARY:     Timezone, locale, NTP via chrony
# DEPENDS:     01-base-config
# IDEMPOTENT:  yes
# DESTRUCTIVE: no
# ADDED:       1.0.0

set -euo pipefail
TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/common.sh
source "$TOOLKIT_ROOT/lib/common.sh"

PLAN_MODE="${TOOLKIT_PLAN_MODE:-0}"

# 1. Timezone
if [ "$PLAN_MODE" = "1" ]; then
    log_info "PLAN: would set timezone to $TIMEZONE"
else
    current_tz="$(timedatectl show --value -p Timezone 2>/dev/null || echo unknown)"
    if [ "$current_tz" = "$TIMEZONE" ]; then
        log_info "Timezone already set: $TIMEZONE"
    else
        timedatectl set-timezone "$TIMEZONE"
        log_info "Timezone set: $TIMEZONE"
    fi
fi

# 2. Locale
if [ "$PLAN_MODE" = "1" ]; then
    log_info "PLAN: would generate locale $LOCALE and set as default"
else
    if locale -a 2>/dev/null | grep -qi "^${LOCALE//-/}$\|^${LOCALE}$"; then
        log_info "Locale already generated: $LOCALE"
    else
        if [ -f /etc/locale.gen ]; then
            sed -i "s/^# *${LOCALE}/${LOCALE}/" /etc/locale.gen || true
            grep -q "^${LOCALE}" /etc/locale.gen || echo "${LOCALE} UTF-8" >> /etc/locale.gen
        fi
        locale-gen "$LOCALE" >/dev/null
        log_info "Locale generated: $LOCALE"
    fi
    update-locale "LANG=$LOCALE" >/dev/null
fi

# 3. NTP via chrony
if [ "$PLAN_MODE" = "1" ]; then
    log_info "PLAN: would mask systemd-timesyncd, install chrony, configure NTP servers"
else
    system_service_mask systemd-timesyncd
    pkg_install chrony

    chrony_conf="/etc/chrony/chrony.conf"
    [ -f "$chrony_conf" ] || chrony_conf="/etc/chrony.conf"

    tmp="$(mktemp)"
    {
        echo "# Managed by ubuntu-26-toolkit"
        for srv in "${NTP_SERVERS[@]}"; do
            echo "server $srv iburst"
        done
        for fb in $FALLBACK_NTP; do
            echo "pool $fb iburst"
        done
        cat <<'EOF'
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
keyfile /etc/chrony/chrony.keys
logdir /var/log/chrony
EOF
    } > "$tmp"

    if [ -f "$chrony_conf" ] && cmp -s "$tmp" "$chrony_conf"; then
        log_info "chrony.conf unchanged"
        rm -f "$tmp"
    else
        if [ -f "$chrony_conf" ] && [ ! -f "${chrony_conf}.toolkit.bak" ]; then
            cp "$chrony_conf" "${chrony_conf}.toolkit.bak"
        fi
        install -m 0644 "$tmp" "$chrony_conf"
        rm -f "$tmp"
        systemctl restart chrony 2>/dev/null || systemctl restart chronyd 2>/dev/null \
            || log_warn "chrony restart failed"
    fi
    system_service_enable_start chrony || system_service_enable_start chronyd || true

    if command -v chronyc >/dev/null 2>&1; then
        chronyc tracking 2>/dev/null | sed 's/^/  /' || true
    fi
fi

log_info "System settings complete"
