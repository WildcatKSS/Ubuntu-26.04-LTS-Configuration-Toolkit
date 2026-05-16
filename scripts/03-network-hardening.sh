#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 WildcatKSS
# Ubuntu Server 26.04 LTS Configuration Toolkit
#
# MODULE:      03-network-hardening
# DESC:     Disable cloud-init, UFW (SSH-only), IPv6, fail2ban
# DEPENDS:     02-ip-config
# IDEMPOTENT:  yes
# DESTRUCTIVE: no

set -euo pipefail
TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/common.sh
source "$TOOLKIT_ROOT/lib/common.sh"

PLAN_MODE="${TOOLKIT_PLAN_MODE:-0}"

# 1. Disable cloud-init
if plan_action "disable cloud-init"; then
    if [ ! -f /etc/cloud/cloud-init.disabled ]; then
        mkdir -p /etc/cloud
        touch /etc/cloud/cloud-init.disabled
        log_info "Created /etc/cloud/cloud-init.disabled"
    fi
    for svc in cloud-init cloud-config cloud-final cloud-init-local; do
        run_quiet systemctl list-unit-files "${svc}.service" || continue
        state="$(systemctl is-enabled "${svc}.service" 2>/dev/null || true)"
        [ "$state" = "masked" ] && continue
        run_quiet systemctl mask "${svc}.service" || true
    done
fi

# 2. Remove NetworkManager
if plan_action "purge network-manager if installed"; then
    pkg_purge network-manager network-manager-gnome
fi

# 3. Enable systemd-networkd
if plan_action "ensure systemd-networkd is enabled and active"; then
    system_service_enable_start systemd-networkd || true
fi

# 4. UFW
if plan_action "configure UFW (default deny in / allow out, allow SSH)"; then
    pkg_install ufw
    ufw_status="$(ufw status 2>/dev/null || true)"
    if [[ "$ufw_status" == *"Status: active"* ]]; then
        log_info "UFW already active — verifying SSH rule"
    else
        run_quiet ufw --force reset
        run_quiet ufw default deny incoming
        run_quiet ufw default allow outgoing
        run_quiet ufw allow 22/tcp comment 'SSH'
        run_quiet ufw --force enable
        log_info "UFW enabled with SSH rule"
        ufw_status="$(ufw status 2>/dev/null || true)"
    fi
    if [[ "$ufw_status" != *"22/tcp"* ]]; then
        run_quiet ufw allow 22/tcp comment 'SSH'
    fi
fi

# 5. Disable IPv6 (sysctl + grub)
if plan_action "persistently disable IPv6"; then
    cat >/etc/sysctl.d/99-ipv6.conf <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
    run_quiet sysctl -p /etc/sysctl.d/99-ipv6.conf
    log_info "IPv6 disabled via sysctl"

    if [ -f /etc/default/grub ]; then
        if grep -q 'ipv6.disable=1' /etc/default/grub; then
            log_info "grub already has ipv6.disable=1"
        else
            sed -i 's/^GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 ipv6.disable=1"/' /etc/default/grub
            if command -v update-grub >/dev/null 2>&1; then
                run_quiet update-grub || log_warn "update-grub failed (non-fatal)"
            fi
            log_info "Added ipv6.disable=1 to grub (effective after reboot)"
        fi
    fi
fi

# 6. Fail2ban
if plan_action "install fail2ban and copy jail.local"; then
    pkg_install fail2ban
    template="$TOOLKIT_ROOT/templates/fail2ban-jail.local"
    target="/etc/fail2ban/jail.local"
    if system_file_install "$template" "$target" 0644; then
        systemctl restart fail2ban || log_warn "fail2ban restart failed"
    fi
    system_service_enable_start fail2ban || true
fi

log_info "Network hardening complete"
