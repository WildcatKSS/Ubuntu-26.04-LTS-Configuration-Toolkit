#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 WildcatKSS
# Ubuntu Server 26.04 LTS Configuration Toolkit
#
# MODULE:      99-cleanup
# SUMMARY:     apt autoremove/clean, service verification, banner
# DEPENDS:     08-mail-alerting
# IDEMPOTENT:  yes
# DESTRUCTIVE: no
# ADDED:       1.0.0

set -euo pipefail
TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/common.sh
source "$TOOLKIT_ROOT/lib/common.sh"

PLAN_MODE="${TOOLKIT_PLAN_MODE:-0}"

if [ "$PLAN_MODE" = "1" ]; then
    log_info "PLAN: would run apt autoremove + clean and verify service status"
else
    log_info "Running apt autoremove + clean"
    run_quiet apt-get autoremove -y
    run_quiet apt-get clean
    log_info "Cleanup complete"
fi

# Service verification
SERVICES_TO_CHECK=(ssh chrony postfix auditd fail2ban ufw apparmor systemd-networkd)
for svc in "${SERVICES_TO_CHECK[@]}"; do
    if systemctl show -p LoadState --value "$svc" 2>/dev/null | grep -q "^loaded"; then
        if systemctl is-active --quiet "$svc"; then
            log_info "service active: $svc"
        else
            log_warn "service NOT active: $svc"
        fi
    fi
done

if [ -f /var/run/reboot-required ]; then
    log_warn "REBOOT REQUIRED to finalise kernel/system upgrades"
fi

echo
echo "=================================================="
echo "  Ubuntu Server 26.04 toolkit setup complete"
echo "=================================================="
echo "  State file: $(state_active_path)"
echo "  Log file:   ${TOOLKIT_LOG_FILE:-/var/log/toolkit-setup/toolkit-setup.log}"
echo
echo "Completed modules:"
state_summary
echo
