#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 WildcatKSS
# Ubuntu Server 26.04 LTS Configuration Toolkit
#
# MODULE:      05-packages
# DESC:     Install standard package set
# DEPENDS:     01-base-config
# IDEMPOTENT:  yes
# DESTRUCTIVE: no

set -euo pipefail
TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/common.sh
source "$TOOLKIT_ROOT/lib/common.sh"

# Install standard package groups
if plan_action "install editor, monitoring, and network packages"; then
    pkg_install vim nano
    pkg_install htop iotop sysstat
    pkg_install rsyslog logrotate
    pkg_install iproute2 iputils-ping traceroute curl wget
    pkg_install tree unzip zip tar
    pkg_install gnupg ca-certificates
fi

log_info "Packages installation complete"
