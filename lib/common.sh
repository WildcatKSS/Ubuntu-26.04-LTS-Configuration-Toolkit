#!/usr/bin/env bash
# Ubuntu Server 26.04 LTS Configuration Toolkit - SPDX-License-Identifier: MIT
# Copyright (c) 2026 WildcatKSS
#
# lib/common.sh — Single entry point sourcing all helper modules.
#
# Usage from a module:
#   TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
#   source "$TOOLKIT_ROOT/lib/common.sh"

_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=log.sh
source "$_lib_dir/log.sh"
# shellcheck source=config.sh
source "$_lib_dir/config.sh"
# shellcheck source=system.sh
source "$_lib_dir/system.sh"
# shellcheck source=pkg.sh
source "$_lib_dir/pkg.sh"
# shellcheck source=state.sh
source "$_lib_dir/state.sh"
# shellcheck source=plan.sh
source "$_lib_dir/plan.sh"

unset _lib_dir

# Configuration path constants
export TOOLKIT_CLOUD_INIT_DISABLE="/etc/cloud/cloud-init.disabled"
export TOOLKIT_SYSCTL_DIR="/etc/sysctl.d"
export TOOLKIT_NETPLAN_DIR="/etc/netplan"
export TOOLKIT_FAIL2BAN_JAIL="/etc/fail2ban/jail.local"
export TOOLKIT_APT_UPGRADES="/etc/apt/apt.conf.d/20auto-upgrades"
export TOOLKIT_CHRONY_CONF="/etc/chrony/chrony.conf"
export TOOLKIT_POSTFIX_MAIN_CF="/etc/postfix/main.cf"
