#!/usr/bin/env bash
# MODULE: 03-network-hardening
# DESC: Disable cloud-init, remove NetworkManager, enable systemd-networkd, UFW (SSH-only), disable IPv6, fail2ban
# DEPENDS: 02-ip-config
# IDEMPOTENT: yes
# DESTRUCTIVE: no

set -euo pipefail
TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/common.sh
source "$TOOLKIT_ROOT/lib/common.sh"

PLAN_MODE="${TOOLKIT_PLAN_MODE:-0}"

# 1. Disable cloud-init
if [ "$PLAN_MODE" = "1" ]; then
    log_info "PLAN: would disable cloud-init"
else
    if [ ! -f /etc/cloud/cloud-init.disabled ]; then
        mkdir -p /etc/cloud
        touch /etc/cloud/cloud-init.disabled
        log_info "Created /etc/cloud/cloud-init.disabled"
    fi
    for svc in cloud-init cloud-config cloud-final cloud-init-local; do
        if systemctl list-unit-files "${svc}.service" >/dev/null 2>&1 \
            && ! systemctl is-enabled "${svc}.service" 2>/dev/null | grep -q masked; then
            systemctl mask "${svc}.service" 2>/dev/null || true
        fi
    done
fi

# 2. Remove NetworkManager
if [ "$PLAN_MODE" = "1" ]; then
    log_info "PLAN: would purge network-manager if installed"
else
    pkg_purge network-manager network-manager-gnome
fi

# 3. Enable systemd-networkd
if [ "$PLAN_MODE" = "1" ]; then
    log_info "PLAN: would ensure systemd-networkd is enabled and active"
else
    system_service_enable_start systemd-networkd || true
fi

# 4. UFW
if [ "$PLAN_MODE" = "1" ]; then
    log_info "PLAN: would configure UFW (default deny in / allow out, allow SSH)"
else
    pkg_install ufw
    if ufw status 2>/dev/null | grep -q 'Status: active'; then
        log_info "UFW already active — verifying SSH rule"
    else
        ufw --force reset >/dev/null
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow 22/tcp comment 'SSH'
        ufw --force enable
        log_info "UFW enabled with SSH rule"
    fi
    if ! ufw status | grep -q '22/tcp'; then
        ufw allow 22/tcp comment 'SSH'
    fi
fi

# 5. Disable IPv6 (sysctl + grub)
if [ "$PLAN_MODE" = "1" ]; then
    log_info "PLAN: would persistently disable IPv6"
else
    cat >/etc/sysctl.d/99-ipv6.conf <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
    sysctl -p /etc/sysctl.d/99-ipv6.conf >/dev/null
    log_info "IPv6 disabled via sysctl"

    if [ -f /etc/default/grub ]; then
        if grep -q 'ipv6.disable=1' /etc/default/grub; then
            log_info "grub already has ipv6.disable=1"
        else
            sed -i 's/^GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 ipv6.disable=1"/' /etc/default/grub
            sed -i 's/  *ipv6.disable=1"/ ipv6.disable=1"/' /etc/default/grub
            if command -v update-grub >/dev/null 2>&1; then
                update-grub 2>/dev/null || log_warn "update-grub failed (non-fatal)"
            fi
            log_info "Added ipv6.disable=1 to grub (effective after reboot)"
        fi
    fi
fi

# 6. Fail2ban
if [ "$PLAN_MODE" = "1" ]; then
    log_info "PLAN: would install fail2ban and copy jail.local"
else
    pkg_install fail2ban
    template="$TOOLKIT_ROOT/templates/fail2ban-jail.local"
    target="/etc/fail2ban/jail.local"
    if system_file_install "$template" "$target" 0644; then
        systemctl restart fail2ban || log_warn "fail2ban restart failed"
    fi
    system_service_enable_start fail2ban || true
fi

log_info "Network hardening complete"
