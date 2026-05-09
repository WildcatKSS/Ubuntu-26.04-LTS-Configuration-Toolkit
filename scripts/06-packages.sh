#!/usr/bin/env bash
# MODULE: 06-packages
# DESC: Encrypted swap conversion (if chosen) and install of standard package set
# DEPENDS: 05-system-settings
# IDEMPOTENT: yes
# DESTRUCTIVE: no

set -euo pipefail
TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/common.sh
source "$TOOLKIT_ROOT/lib/common.sh"

PLAN_MODE="${TOOLKIT_PLAN_MODE:-0}"

# Encrypted swap setup (deferred from script 02)
swap_flag="$TOOLKIT_TEMP_DIR/.swap_encrypted"
if [ -f "$swap_flag" ]; then
    if [ "$PLAN_MODE" = "1" ]; then
        log_info "PLAN: would install cryptsetup and convert lv_swap to encrypted swap"
    elif [ -e /dev/mapper/swap ] && grep -q '/dev/mapper/swap' /etc/fstab; then
        log_info "Encrypted swap already configured"
    elif [ ! -e /dev/vg0/lv_swap ]; then
        log_warn "lv_swap not found — skipping encrypted swap setup"
    else
        log_info "Setting up encrypted swap on /dev/vg0/lv_swap"
        pkg_install cryptsetup
        swapoff /dev/vg0/lv_swap 2>/dev/null || true
        if [ ! -f /root/.swap-key ]; then
            (umask 077 && openssl rand -base64 32 > /root/.swap-key)
            chmod 0600 /root/.swap-key
        fi
        cryptsetup -d /root/.swap-key luksFormat -q /dev/vg0/lv_swap
        cryptsetup -d /root/.swap-key luksOpen /dev/vg0/lv_swap swap
        mkswap /dev/mapper/swap >/dev/null
        if ! grep -q '^swap ' /etc/crypttab 2>/dev/null; then
            echo 'swap /dev/vg0/lv_swap /root/.swap-key swap' >> /etc/crypttab
        fi
        sed -i '\|^/dev/vg0/lv_swap[[:space:]]|d' /etc/fstab
        if ! grep -q '^/dev/mapper/swap ' /etc/fstab; then
            echo '/dev/mapper/swap none swap sw 0 0' >> /etc/fstab
        fi
        swapon /dev/mapper/swap
        log_info "Encrypted swap active on /dev/mapper/swap"
    fi
fi

# Install standard package groups
if [ "$PLAN_MODE" = "1" ]; then
    log_info "PLAN: would install editor, monitoring, and network packages"
else
    pkg_install vim nano
    pkg_install htop iotop sysstat
    pkg_install rsyslog logrotate
    pkg_install iproute2 iputils-ping traceroute curl wget
    pkg_install tree unzip zip tar
    pkg_install gnupg ca-certificates
fi

log_info "Packages installation complete"
