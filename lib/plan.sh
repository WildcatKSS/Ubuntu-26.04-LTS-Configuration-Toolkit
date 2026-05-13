#!/usr/bin/env bash
# Ubuntu Server 26.04 LTS Configuration Toolkit - SPDX-License-Identifier: MIT
# Copyright (c) 2025 WildcatKSS
#
# lib/plan.sh — Plan mode utilities for idempotent operations

# plan_action: Log an action and optionally execute it.
# Usage: plan_action "Description of action" [command to execute]
# If PLAN_MODE=1, logs the action and returns non-zero (skip execution).
# If PLAN_MODE=0, executes the command (if provided).
#
# Example:
#   if plan_action "Create admin user"; then
#       system_user_create "$ADMIN_USER" || return 1
#   fi
plan_action() {
    local description="$1"
    if [ "${TOOLKIT_PLAN_MODE:-0}" = "1" ]; then
        log_info "PLAN: $description"
        return 1
    fi
    return 0
}
