#!/usr/bin/env bash
# MODULE: 00-preflight
# DESC: Verify Ubuntu 24.04 LTS, network, disk space, and apt locks before any changes
# DEPENDS:
# IDEMPOTENT: yes
# DESTRUCTIVE: no

set -euo pipefail
TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/common.sh
source "$TOOLKIT_ROOT/lib/common.sh"

PLAN_MODE="${TOOLKIT_PLAN_MODE:-0}"
errors=0

# 1. OS verification
if [ -f /etc/os-release ]; then
    if ! grep -q 'VERSION_ID="24\.04"' /etc/os-release || ! grep -q '^ID=ubuntu' /etc/os-release; then
        log_error "This system is not Ubuntu 24.04 LTS"
        errors=$((errors + 1))
    else
        log_info "OS check ok: Ubuntu 24.04"
    fi
else
    log_error "/etc/os-release missing"
    errors=$((errors + 1))
fi

# 2. Architecture
arch="$(uname -m)"
case "$arch" in
    x86_64|aarch64) log_info "Architecture ok: $arch" ;;
    *) log_error "Unsupported architecture: $arch"; errors=$((errors + 1)) ;;
esac

# 3. Internet connectivity
if ping -c1 -W3 archive.ubuntu.com >/dev/null 2>&1; then
    log_info "Internet connectivity ok"
else
    log_error "Cannot reach archive.ubuntu.com — apt will fail"
    errors=$((errors + 1))
fi

# 4. APT lock check
if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
    log_error "Another process holds the apt lock (/var/lib/dpkg/lock-frontend)"
    errors=$((errors + 1))
else
    log_info "APT lock ok"
fi

# 5. Disk space (root partition >=5 GB free)
free_gb="$(df -BG --output=avail / | awk 'NR==2 {gsub("G",""); print $1}')"
if [ -n "$free_gb" ] && [ "$free_gb" -lt 5 ]; then
    log_error "Root partition has only ${free_gb}GB free (need >=5GB)"
    errors=$((errors + 1))
else
    log_info "Disk space ok: ${free_gb}GB free on /"
fi

# 6. Required commands
missing=()
for cmd in apt-get curl ip systemctl ping awk grep sed; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if [ "${#missing[@]}" -gt 0 ]; then
    log_error "Missing required commands: ${missing[*]}"
    errors=$((errors + 1))
fi

# 7. Defense-in-depth: revalidate config
config_validate || errors=$((errors + 1))

if [ "$errors" -gt 0 ]; then
    log_error "Preflight failed with $errors error(s)"
    exit 1
fi

if [ "$PLAN_MODE" = "1" ]; then
    log_info "PLAN: preflight checks all passed"
fi

log_info "Preflight checks passed"
