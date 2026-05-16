#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 WildcatKSS
# Ubuntu Server 26.04 LTS Configuration Toolkit
#
# MODULE:      06-hardening
# DESC:     Kernel sysctl hardening, AppArmor verification, auditd setup
# DEPENDS:     05-packages
# IDEMPOTENT:  yes
# DESTRUCTIVE: no

set -euo pipefail
TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/common.sh
source "$TOOLKIT_ROOT/lib/common.sh"

# 1. Kernel sysctl hardening
template="$TOOLKIT_ROOT/templates/sysctl-hardening.conf"
target="/etc/sysctl.d/99-hardening.conf"

if plan_action "install $template -> $target and run sysctl --system"; then
    if system_file_install "$template" "$target" 0644; then
        run_quiet sysctl --system
        log_info "Applied kernel hardening sysctls"
    fi
fi

# 2. AppArmor verification
if plan_action "verify AppArmor is enabled and report profile counts"; then
    pkg_install apparmor apparmor-utils
    if run_quiet aa-status --enabled; then
        aa_output="$(aa-status 2>/dev/null)"
        enforced="$(awk '/profiles are in enforce mode/{print $1; exit}' <<<"$aa_output")"
        complain="$(awk '/profiles are in complain mode/{print $1; exit}' <<<"$aa_output")"
        log_info "AppArmor enabled: ${enforced:-?} enforce, ${complain:-?} complain"
    else
        log_error "AppArmor is not enabled — Ubuntu Server 26.04 should ship with it active"
        exit 1
    fi
    system_service_enable_start apparmor || true
fi

# 3. auditd
if plan_action "install auditd and load custom rules"; then
    pkg_install auditd audispd-plugins
    rules_template="$TOOLKIT_ROOT/templates/auditd.rules"
    rules_target="/etc/audit/rules.d/99-toolkit.rules"
    if system_file_install "$rules_template" "$rules_target" 0640; then
        if command -v augenrules >/dev/null 2>&1; then
            run_quiet augenrules --load || log_warn "augenrules --load failed (rules may be -e 2 from earlier load)"
        fi
    fi
    system_service_enable_start auditd || true
fi

log_info "Hardening complete"
