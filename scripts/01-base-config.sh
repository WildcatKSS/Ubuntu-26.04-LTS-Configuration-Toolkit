#!/usr/bin/env bash
# MODULE: 01-base-config
# DESC: System update, admin sudo user, unattended-upgrades
# DEPENDS: 00-preflight
# IDEMPOTENT: yes
# DESTRUCTIVE: no

set -euo pipefail
TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/common.sh
source "$TOOLKIT_ROOT/lib/common.sh"

PLAN_MODE="${TOOLKIT_PLAN_MODE:-0}"

# 1. apt update + upgrade
if [ "$PLAN_MODE" = "1" ]; then
    log_info "PLAN: would run apt-get update && apt-get upgrade -y && dist-upgrade"
else
    pkg_update
    log_info "Running apt-get upgrade"
    apt-get upgrade -y
    log_info "Running apt-get dist-upgrade"
    apt-get dist-upgrade -y
fi

# 2. Admin credentials (provided by main.sh interactive phase or environment)
if [ "$PLAN_MODE" = "1" ]; then
    log_info "PLAN: would use ADMIN_USER and ADMIN_PASSWORD from environment"
    ADMIN_USER="${ADMIN_USER:-admin}"
    ADMIN_PASSWORD=""
else
    if [ -z "${ADMIN_USER:-}" ]; then
        ADMIN_USER="admin"
        log_warn "ADMIN_USER not set; using default: $ADMIN_USER"
    fi
    log_info "Using admin user: $ADMIN_USER"
fi

# 3. Create user (idempotent)
if [ "$PLAN_MODE" = "1" ]; then
    log_info "PLAN: would ensure user $ADMIN_USER exists and is in sudo group"
elif system_user_exists "$ADMIN_USER"; then
    log_info "User already exists: $ADMIN_USER"
else
    log_info "Creating user: $ADMIN_USER"
    useradd -m -s /bin/bash -G sudo "$ADMIN_USER"
    if [ -n "${ADMIN_PASSWORD:-}" ]; then
        echo "${ADMIN_USER}:${ADMIN_PASSWORD}" | chpasswd
    fi
fi

# 4. Sudo group membership (defensive — covers case where user pre-existed without sudo)
if [ "$PLAN_MODE" != "1" ]; then
    if id -nG "$ADMIN_USER" | tr ' ' '\n' | grep -qx sudo; then
        log_info "User $ADMIN_USER is already in sudo group"
    else
        usermod -aG sudo "$ADMIN_USER"
        log_info "Added $ADMIN_USER to sudo group"
    fi
fi

# 5. Clear sensitive variables
unset ADMIN_PASSWORD

# 6. unattended-upgrades
if [ "${AUTO_SECURITY_UPDATES:-true}" = "true" ]; then
    if [ "$PLAN_MODE" = "1" ]; then
        log_info "PLAN: would install and enable unattended-upgrades"
    else
        pkg_install unattended-upgrades apt-listchanges
        if [ -f /etc/apt/apt.conf.d/20auto-upgrades ] \
           && grep -q 'APT::Periodic::Unattended-Upgrade "1"' /etc/apt/apt.conf.d/20auto-upgrades; then
            log_info "unattended-upgrades already enabled"
        else
            cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
            log_info "Enabled unattended-upgrades (20auto-upgrades)"
        fi
        if [ -n "${EMAIL_TO:-}" ] && [ -f /etc/apt/apt.conf.d/50unattended-upgrades ]; then
            if ! grep -q "^Unattended-Upgrade::Mail \"${EMAIL_TO}\"" /etc/apt/apt.conf.d/50unattended-upgrades; then
                sed -i "s|^//Unattended-Upgrade::Mail .*|Unattended-Upgrade::Mail \"${EMAIL_TO}\";|" \
                    /etc/apt/apt.conf.d/50unattended-upgrades
                log_info "Configured unattended-upgrades to mail $EMAIL_TO on errors"
            fi
        fi
    fi
fi

log_info "Base configuration complete"
