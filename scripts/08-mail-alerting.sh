#!/usr/bin/env bash
# Ubuntu Server 26.04 LTS Configuration Toolkit - SPDX-License-Identifier: MIT
# Copyright (c) 2025 WildcatKSS
#
# MODULE: 08-mail-alerting
# DESC: Postfix relay, daily report cron, disk/service alert cron with local fallback
# DEPENDS: 07-monitoring
# IDEMPOTENT: yes
# DESTRUCTIVE: no

set -euo pipefail
TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/common.sh
source "$TOOLKIT_ROOT/lib/common.sh"

PLAN_MODE="${TOOLKIT_PLAN_MODE:-0}"

# Pre-seed postfix to avoid debconf prompts
if [ "$PLAN_MODE" != "1" ]; then
    debconf-set-selections <<EOF
postfix postfix/main_mailer_type select Internet with smarthost
postfix postfix/mailname string ${HOSTNAME}
postfix postfix/relayhost string [${SMTP_RELAY_HOST}]:${SMTP_RELAY_PORT}
EOF
    pkg_install postfix mailutils bsd-mailx
fi

# 1. Postfix main.cf from template
target="/etc/postfix/main.cf"
template="$TOOLKIT_ROOT/templates/postfix-relay.conf"
if [ "$PLAN_MODE" = "1" ]; then
    log_info "PLAN: would render $template -> $target"
else
    MAIL_DOMAIN="${HOSTNAME#*.}"
    export HOSTNAME MAIL_DOMAIN SMTP_RELAY_HOST SMTP_RELAY_PORT
    tmp="$(mktemp)"
    # shellcheck disable=SC2016
    envsubst '${HOSTNAME} ${MAIL_DOMAIN} ${SMTP_RELAY_HOST} ${SMTP_RELAY_PORT}' < "$template" > "$tmp"
    if [ -f "$target" ] && cmp -s "$tmp" "$target"; then
        log_info "Postfix main.cf unchanged"
        rm -f "$tmp"
    else
        [ -f "$target" ] && [ ! -f "${target}.toolkit.bak" ] && cp "$target" "${target}.toolkit.bak"
        install -m 0644 "$tmp" "$target"
        rm -f "$tmp"
        systemctl restart postfix || log_warn "postfix restart failed"
    fi
    system_service_enable_start postfix || true
fi

# 2. Environment file shared by report/alert scripts
env_dir="/etc/toolkit-setup"
if [ "$PLAN_MODE" = "1" ]; then
    log_info "PLAN: would write $env_dir/{daily-report,disk-alert}.env"
else
    mkdir -p "$env_dir"
    cat >"$env_dir/daily-report.env" <<EOF
EMAIL_TO="${EMAIL_TO}"
EOF
    cat >"$env_dir/disk-alert.env" <<EOF
EMAIL_TO="${EMAIL_TO}"
DISK_ALERT_THRESHOLD="${DISK_ALERT_THRESHOLD:-85}"
EOF
    chmod 0644 "$env_dir/daily-report.env" "$env_dir/disk-alert.env"
fi

# 3. Daily report
if [ "$PLAN_MODE" = "1" ]; then
    log_info "PLAN: would install /usr/local/bin/daily-report.sh and cron entry"
else
    install -m 0755 "$TOOLKIT_ROOT/templates/daily-report.sh" /usr/local/bin/daily-report.sh
    cat >/etc/cron.d/daily-report <<'EOF'
# Daily server report — installed by ubuntu-26-toolkit
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
0 6 * * * root /usr/local/bin/daily-report.sh
EOF
    chmod 0644 /etc/cron.d/daily-report
fi

# 4. Disk/service alerts
if [ "$PLAN_MODE" = "1" ]; then
    log_info "PLAN: would install /usr/local/bin/disk-alert.sh and 15-min cron"
else
    install -m 0755 "$TOOLKIT_ROOT/templates/disk-alert.sh" /usr/local/bin/disk-alert.sh
    cat >/etc/cron.d/disk-alert <<'EOF'
# Disk usage and failed-service alert — installed by ubuntu-26-toolkit
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
*/15 * * * * root /usr/local/bin/disk-alert.sh
EOF
    chmod 0644 /etc/cron.d/disk-alert
fi

# 5. Optional test mail
if [ "${SEND_TEST_MAIL:-no}" = "yes" ]; then
    if [ "$PLAN_MODE" = "1" ]; then
        log_info "PLAN: would send test mail to ${EMAIL_TO}"
    else
        log_info "Testmail versturen naar ${EMAIL_TO}..."
        if echo "Dit is een testmail van de Ubuntu 26.04 Toolkit op $(hostname). Postfix relay werkt correct." \
            | mail -s "[toolkit] Postfix testmail van $(hostname)" "${EMAIL_TO}"; then
            log_info "Testmail verstuurd naar ${EMAIL_TO}"
        else
            log_warn "Testmail mislukt — controleer /var/log/mail.log en de SMTP-relay instellingen"
        fi
    fi
fi

log_info "Mail and alerting complete"
