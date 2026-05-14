#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 WildcatKSS
# Ubuntu Server 26.04 LTS Configuration Toolkit
#
# MODULE:      05-packages
# SUMMARY:     Install standard package set
# DEPENDS:     04-system-settings
# IDEMPOTENT:  yes
# DESTRUCTIVE: no
# ADDED:       1.0.0

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
