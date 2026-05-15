#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 WildcatKSS
# Ubuntu Server 26.04 LTS Configuration Toolkit
#
# MODULE:      07-monitoring
# SUMMARY:     Sysstat collection, rsyslog rules, logrotate policies
# DEPENDS:     05-packages
# IDEMPOTENT:  yes
# DESTRUCTIVE: no
# ADDED:       1.0.0

set -euo pipefail
TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/common.sh
source "$TOOLKIT_ROOT/lib/common.sh"
PLAN_MODE="${TOOLKIT_PLAN_MODE:-0}"

# 1. sysstat
if plan_action "enable sysstat collection"; then
    pkg_install sysstat
    if [ -f /etc/default/sysstat ]; then
        if grep -q '^ENABLED="true"' /etc/default/sysstat; then
            log_info "sysstat already enabled"
        else
            sed -i 's/^ENABLED=.*/ENABLED="true"/' /etc/default/sysstat
            log_info "Enabled sysstat (/etc/default/sysstat)"
        fi
    fi
    system_service_enable_start sysstat || true
fi

# 2. rsyslog custom rules
if plan_action "install custom rsyslog rules"; then
    pkg_install rsyslog
    template="$TOOLKIT_ROOT/templates/rsyslog-custom.conf"
    target="/etc/rsyslog.d/99-custom.conf"
    if system_file_install "$template" "$target" 0644; then
        run_quiet systemctl restart rsyslog || log_warn "rsyslog restart failed"
    fi
fi

# 3. logrotate
if plan_action "install logrotate policy /etc/logrotate.d/custom"; then
    pkg_install logrotate
    template="$TOOLKIT_ROOT/templates/logrotate-custom"
    target="/etc/logrotate.d/custom"
    system_file_install "$template" "$target" 0644
fi

log_info "Monitoring complete"
