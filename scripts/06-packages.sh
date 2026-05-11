#!/usr/bin/env bash
# MODULE: 06-packages
# DESC: Install of standard package set
# DEPENDS: 05-system-settings
# IDEMPOTENT: yes
# DESTRUCTIVE: no

set -euo pipefail
TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/common.sh
source "$TOOLKIT_ROOT/lib/common.sh"

PLAN_MODE="${TOOLKIT_PLAN_MODE:-0}"

# Install standard package groups
if [ "$PLAN_MODE" = "1" ]; then
    log_info "PLAN: would install editor, monitoring, and network packages"
else
    pkg_install vim nano
    pkg_install htop iotop sysstat
    pkg_install rsyslog logrotate
    pkg_install iproute2 iputils-ping traceroute curl wget
    pkg_install tree unzip zip tar
    pkg_install gnupg ca-certificates
fi

log_info "Packages installation complete"
