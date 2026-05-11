#!/usr/bin/env bash
# MODULE: 07-hardening
# DESC: Kernel sysctl hardening, AppArmor verification, auditd setup
# DEPENDS: 06-packages
# IDEMPOTENT: yes
# DESTRUCTIVE: no

set -euo pipefail
TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/common.sh
source "$TOOLKIT_ROOT/lib/common.sh"

PLAN_MODE="${TOOLKIT_PLAN_MODE:-0}"

# 1. Kernel sysctl hardening
template="$TOOLKIT_ROOT/templates/sysctl-hardening.conf"
target="/etc/sysctl.d/99-hardening.conf"

if [ "$PLAN_MODE" = "1" ]; then
    log_info "PLAN: would install $template -> $target and run sysctl --system"
else
    if system_file_install "$template" "$target" 0644; then
        sysctl --system >/dev/null
        log_info "Applied kernel hardening sysctls"
    fi
fi

# 2. AppArmor verification
if [ "$PLAN_MODE" = "1" ]; then
    log_info "PLAN: would verify AppArmor is enabled and report profile counts"
else
    pkg_install apparmor apparmor-utils
    if aa-status --enabled >/dev/null 2>&1; then
        enforced="$(aa-status 2>/dev/null | awk '/profiles are in enforce mode/{print $1; exit}')"
        complain="$(aa-status 2>/dev/null | awk '/profiles are in complain mode/{print $1; exit}')"
        log_info "AppArmor enabled: ${enforced:-?} enforce, ${complain:-?} complain"
    else
        log_error "AppArmor is not enabled — Ubuntu Server 26.04 should ship with it active"
        exit 1
    fi
    system_service_enable_start apparmor || true
fi

# 3. auditd
if [ "$PLAN_MODE" = "1" ]; then
    log_info "PLAN: would install auditd and load custom rules"
else
    pkg_install auditd audispd-plugins
    rules_template="$TOOLKIT_ROOT/templates/auditd.rules"
    rules_target="/etc/audit/rules.d/99-toolkit.rules"
    if system_file_install "$rules_template" "$rules_target" 0640; then
        if command -v augenrules >/dev/null 2>&1; then
            augenrules --load >/dev/null 2>&1 || log_warn "augenrules --load failed (rules may be -e 2 from earlier load)"
        fi
    fi
    system_service_enable_start auditd || true
fi

log_info "Hardening complete"
