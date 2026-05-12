#!/usr/bin/env bash
# MODULE: 07-monitoring
# DESC: Sysstat collection, custom rsyslog rules, logrotate policies
# DEPENDS: 06-hardening
# IDEMPOTENT: yes
# DESTRUCTIVE: no

set -euo pipefail
TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/common.sh
source "$TOOLKIT_ROOT/lib/common.sh"

PLAN_MODE="${TOOLKIT_PLAN_MODE:-0}"

# 1. sysstat
if [ "$PLAN_MODE" = "1" ]; then
    log_info "PLAN: would enable sysstat collection"
else
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
if [ "$PLAN_MODE" = "1" ]; then
    log_info "PLAN: would install custom rsyslog rules"
else
    pkg_install rsyslog
    template="$TOOLKIT_ROOT/templates/rsyslog-custom.conf"
    target="/etc/rsyslog.d/99-custom.conf"
    if system_file_install "$template" "$target" 0644; then
        systemctl restart rsyslog 2>/dev/null || log_warn "rsyslog restart failed"
    fi
fi

# 3. logrotate
if [ "$PLAN_MODE" = "1" ]; then
    log_info "PLAN: would install logrotate policy /etc/logrotate.d/custom"
else
    pkg_install logrotate
    template="$TOOLKIT_ROOT/templates/logrotate-custom"
    target="/etc/logrotate.d/custom"
    system_file_install "$template" "$target" 0644
fi

log_info "Monitoring complete"
