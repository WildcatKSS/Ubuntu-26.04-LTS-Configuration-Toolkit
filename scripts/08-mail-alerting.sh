#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 WildcatKSS
# Ubuntu Server 26.04 LTS Configuration Toolkit
#
# MODULE:      08-mail-alerting
# SUMMARY:     Postfix relay, daily report cron, disk/service alerts
# DEPENDS:     07-monitoring
# IDEMPOTENT:  yes
# DESTRUCTIVE: no
# ADDED:       1.0.0
# CHANGED:     1.0.2

set -euo pipefail
TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/common.sh
source "$TOOLKIT_ROOT/lib/common.sh"
PLAN_MODE="${TOOLKIT_PLAN_MODE:-0}"

# Pre-seed postfix to avoid debconf prompts
if plan_action "pre-seed postfix and install postfix/mailutils"; then
    debconf-set-selections <<EOF
postfix postfix/main_mailer_type select Internet with smarthost
postfix postfix/mailname string ${HOSTNAME}
postfix postfix/relayhost string [${SMTP_RELAY_HOST}]:${SMTP_RELAY_PORT}
EOF
    pkg_install postfix mailutils bsd-mailx
fi

# 1. Postfix main.cf from template
template="$TOOLKIT_ROOT/templates/postfix-relay.conf"
if plan_action "render $template -> $TOOLKIT_POSTFIX_MAIN_CF"; then
    MAIL_DOMAIN="${HOSTNAME#*.}"
    export HOSTNAME MAIL_DOMAIN SMTP_RELAY_HOST SMTP_RELAY_PORT
    install_result=0
    system_install_from_template "$template" "$TOOLKIT_POSTFIX_MAIN_CF" "HOSTNAME MAIL_DOMAIN SMTP_RELAY_HOST SMTP_RELAY_PORT" 0644 || install_result=$?
    # Only restart if config actually changed (return 0), not if unchanged (return 2)
    if [ "$install_result" -eq 0 ]; then
        run_quiet systemctl restart postfix || log_warn "postfix restart failed"
    fi

    # Ensure resolv.conf in chroot has correct ownership before starting postfix
    # Remove stale copy with wrong permissions so postfix creates a fresh one
    if [ -f /var/spool/postfix/etc/resolv.conf ]; then
        # Check if owned by wrong user and remove it
        owner=$(stat -c '%U' /var/spool/postfix/etc/resolv.conf 2>/dev/null || echo "")
        if [ "$owner" != "root" ]; then
            rm -f /var/spool/postfix/etc/resolv.conf
            log_info "Removed stale /var/spool/postfix/etc/resolv.conf with wrong owner ($owner)"
        fi
    fi

    system_service_enable_start postfix || true

    # Fix ownership if file was just created (in case it still has wrong permissions)
    if [ -f /var/spool/postfix/etc/resolv.conf ]; then
        chown root:root /var/spool/postfix/etc/resolv.conf 2>/dev/null || true
        chmod 0644 /var/spool/postfix/etc/resolv.conf 2>/dev/null || true
    fi
fi

# 2. Environment file shared by report/alert scripts
env_dir="/etc/toolkit-setup"
if plan_action "write $env_dir/{daily-report,disk-alert}.env"; then
    mkdir -p "$env_dir"
    echo "EMAIL_TO=\"${EMAIL_TO}\"" | system_write_file "$env_dir/daily-report.env" 0644
    {
        echo "EMAIL_TO=\"${EMAIL_TO}\""
        echo "DISK_ALERT_THRESHOLD=\"${DISK_ALERT_THRESHOLD:-85}\""
    } | system_write_file "$env_dir/disk-alert.env" 0644
fi

# 3. Daily report
if plan_action "install /usr/local/bin/daily-report.sh and cron entry"; then
    install -m 0755 "$TOOLKIT_ROOT/templates/daily-report.sh" /usr/local/bin/daily-report.sh
    system_write_file "/etc/cron.d/daily-report" 0644 <<'EOF'
# Daily server report — installed by ubuntu-26-toolkit
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
0 6 * * * root /usr/local/bin/daily-report.sh
EOF
fi

# 4. Disk/service alerts
if plan_action "install /usr/local/bin/disk-alert.sh and 15-min cron"; then
    install -m 0755 "$TOOLKIT_ROOT/templates/disk-alert.sh" /usr/local/bin/disk-alert.sh
    system_write_file "/etc/cron.d/disk-alert" 0644 <<'EOF'
# Disk usage and failed-service alert — installed by ubuntu-26-toolkit
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
*/15 * * * * root /usr/local/bin/disk-alert.sh
EOF
fi

# 5. Optional test mail
if [ "${SEND_TEST_MAIL:-no}" = "yes" ]; then
    if plan_action "send test mail to ${EMAIL_TO}"; then
        log_info "Sending test mail to ${EMAIL_TO}..."
        if echo "This is a test mail from the Ubuntu 26.04 Toolkit on $(hostname). Postfix relay is working correctly." \
            | mail -s "[toolkit] Postfix test mail from $(hostname)" "${EMAIL_TO}"; then
            log_info "Test mail sent to ${EMAIL_TO}"
        else
            log_warn "Test mail failed — check /var/log/mail.log and SMTP relay settings"
        fi
    fi
fi

log_info "Mail and alerting complete"
