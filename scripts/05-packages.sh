#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 WildcatKSS
# Ubuntu Server 26.04 LTS Configuration Toolkit
#
# MODULE:      05-packages
# SUMMARY:     Install standard package set
# DEPENDS:     01-base-config
# IDEMPOTENT:  yes
# DESTRUCTIVE: no
# ADDED:       1.0.0

set -euo pipefail
TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/common.sh
source "$TOOLKIT_ROOT/lib/common.sh"

# Install standard package groups
if [ "$PLAN_MODE" = "1" ]; then
    log_info "PLAN: would install editor, monitoring, and network packages"
else
    pkg_install vim nano htop iotop sysstat rsyslog logrotate \
        iproute2 iputils-ping traceroute curl wget tree unzip zip tar \
        gnupg ca-certificates
fi

log_info "Packages installation complete"
