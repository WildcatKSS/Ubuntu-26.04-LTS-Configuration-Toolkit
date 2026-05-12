#!/usr/bin/env bash
# Daily status report — installed to /usr/local/bin/daily-report.sh by script 08
#
# Generates a system status report and emails it to ${EMAIL_TO}.
# Always saves a local copy to /var/log/daily-reports/ (fallback if SMTP fails).

set -u

CONF="/etc/toolkit-setup/daily-report.env"
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

EMAIL_TO="${EMAIL_TO:-root}"
HOSTNAME_CACHED="$(hostname -f 2>/dev/null || hostname)"
REPORT_DIR="/var/log/daily-reports"
mkdir -p "$REPORT_DIR"
REPORT_FILE="$REPORT_DIR/$(date +%Y-%m-%d).txt"

{
    echo "Daily report for $HOSTNAME_CACHED — $(date '+%Y-%m-%d %H:%M:%S')"
    echo "================================================================"
    echo
    echo "## Uptime"
    uptime
    echo
    echo "## Memory"
    free -h
    echo
    echo "## Disk usage"
    df -h -x tmpfs -x devtmpfs
    echo
    echo "## CPU load (sar last hour)"
    if command -v sar >/dev/null 2>&1; then
        sar -u 2>/dev/null | tail -n 20 || echo "(sar data not available)"
    else
        echo "(sysstat not installed)"
    fi
    echo
    echo "## Failed services"
    systemctl --failed --no-legend || true
    echo
    echo "## Recent error log entries"
    journalctl -p err -n 50 --no-pager 2>/dev/null || echo "(journalctl unavailable)"
    echo
    echo "## Last 10 logins"
    last -n 10 2>/dev/null | head -n 10 || true
} > "$REPORT_FILE"

if command -v mail >/dev/null 2>&1; then
    mail -s "Daily report $HOSTNAME_CACHED" "$EMAIL_TO" < "$REPORT_FILE" 2>/dev/null \
        || echo "mail send failed; report saved to $REPORT_FILE" >&2
fi

exit 0
