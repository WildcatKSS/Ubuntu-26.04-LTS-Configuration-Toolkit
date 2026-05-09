#!/usr/bin/env bash
# Disk and service alert — installed to /usr/local/bin/disk-alert.sh by script 09
#
# Sends an alert email when:
#   - Any mounted filesystem exceeds DISK_ALERT_THRESHOLD percent
#   - Any systemd service is in failed state
#
# Always saves a local copy of any alert to /var/log/alerts/.

set -u

CONF="/etc/toolkit-setup/disk-alert.env"
[ -f "$CONF" ] && . "$CONF"

EMAIL_TO="${EMAIL_TO:-root}"
DISK_ALERT_THRESHOLD="${DISK_ALERT_THRESHOLD:-85}"
HOSTNAME_CACHED="$(hostname -f 2>/dev/null || hostname)"
ALERT_DIR="/var/log/alerts"
mkdir -p "$ALERT_DIR"

ALERTS=""

# --- Disk usage ---
while IFS= read -r line; do
    pct="$(echo "$line" | awk '{print $5}' | tr -d '%')"
    [ -z "$pct" ] && continue
    if [ "$pct" -ge "$DISK_ALERT_THRESHOLD" ]; then
        ALERTS+="DISK: $line\n"
    fi
done < <(df -h --output=source,size,used,avail,pcent,target -x tmpfs -x devtmpfs | tail -n +2)

# --- Failed services ---
failed_services="$(systemctl --failed --no-legend --plain 2>/dev/null)"
if [ -n "$failed_services" ]; then
    ALERTS+="\nFAILED SERVICES:\n$failed_services\n"
fi

if [ -z "$ALERTS" ]; then
    exit 0
fi

ALERT_FILE="$ALERT_DIR/$(date +%Y%m%d-%H%M%S).txt"
{
    echo "Alert from $HOSTNAME_CACHED — $(date '+%Y-%m-%d %H:%M:%S')"
    echo "================================================================"
    printf '%b' "$ALERTS"
} > "$ALERT_FILE"

if command -v mail >/dev/null 2>&1; then
    mail -s "ALERT $HOSTNAME_CACHED" "$EMAIL_TO" < "$ALERT_FILE" 2>/dev/null \
        || echo "mail send failed; alert saved to $ALERT_FILE" >&2
fi

exit 0
