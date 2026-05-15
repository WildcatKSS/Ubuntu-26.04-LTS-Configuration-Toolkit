#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 WildcatKSS
# Ubuntu Server 26.04 LTS Configuration Toolkit
#
# MODULE:      02-ip-config
# SUMMARY:     Hostname, /etc/hosts, Netplan IP/DNS/gateway with auto-restore
# DEPENDS:     01-base-config
# IDEMPOTENT:  yes
# DESTRUCTIVE: no
# ADDED:       1.0.0
# CHANGED:     1.0.2

set -euo pipefail
TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/common.sh
source "$TOOLKIT_ROOT/lib/common.sh"
PLAN_MODE="${TOOLKIT_PLAN_MODE:-0}"

# 1. Hostname
if plan_action "set hostname to $HOSTNAME"; then
    if [ "$(run_quiet hostname)" = "$HOSTNAME" ]; then
        log_info "Hostname already set: $HOSTNAME"
    else
        run_quiet hostnamectl set-hostname "$HOSTNAME"
        log_info "Hostname set: $HOSTNAME"
    fi

    # 2. /etc/hosts
    short_host="${HOSTNAME%%.*}"
    if grep -q "127.0.1.1.*${HOSTNAME}" /etc/hosts; then
        log_info "/etc/hosts already contains $HOSTNAME entry"
    else
        # Replace the first 127.0.1.1 line if present, otherwise append
        if grep -q '^127\.0\.1\.1' /etc/hosts; then
            sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t${HOSTNAME} ${short_host}/" /etc/hosts
        else
            printf '127.0.1.1\t%s %s\n' "$HOSTNAME" "$short_host" >> /etc/hosts
        fi
        log_info "/etc/hosts updated"
    fi
fi

# 3. Backup Netplan
if [ ! -d /etc/netplan.backup ] && [ -d /etc/netplan ]; then
    if plan_action "back up /etc/netplan to /etc/netplan.backup"; then
        cp -a /etc/netplan /etc/netplan.backup
        log_info "Backed up /etc/netplan to /etc/netplan.backup"
    fi
else
    log_info "/etc/netplan.backup already exists — skipping backup"
fi

# 4. Generate Netplan YAML from template
target="/etc/netplan/99-toolkit.yaml"
if [ "${USE_DHCP:-true}" = "true" ]; then
    template="$TOOLKIT_ROOT/templates/netplan-dhcp.yaml"
    log_info "Using DHCP Netplan template"
    export NETWORK_INTERFACE
else
    template="$TOOLKIT_ROOT/templates/netplan-static.yaml"
    log_info "Using static-IP Netplan template"
    # Build YAML list for DNS servers
    dns_yaml=""
    if [ -z "$DNS_SERVERS" ]; then
        log_warn "DNS_SERVERS is empty — using systemd-resolved defaults"
    else
        for srv in $DNS_SERVERS; do
            dns_yaml+="          - $srv"$'\n'
        done
    fi
    export NETWORK_INTERFACE IP_ADDRESS PREFIX_LENGTH GATEWAY
    export DNS_SERVERS_YAML="${dns_yaml%$'\n'}"
fi

if plan_action "render $template -> $target and run netplan apply"; then
    install_result=0
    system_install_from_template "$template" "$target" "NETWORK_INTERFACE IP_ADDRESS PREFIX_LENGTH GATEWAY DNS_SERVERS_YAML" 0600 || install_result=$?

    # Only apply netplan if file actually changed (return 0), not if unchanged (return 2)
    if [ "$install_result" -eq 0 ]; then
        # 5. Apply with auto-restore on connectivity failure
        netplan_err=$(mktemp)
        if ! netplan apply >"$netplan_err" 2>&1; then
            log_error "netplan apply failed — restoring backup"
            log_error "netplan output: $(cat "$netplan_err")"
            rm -f "$netplan_err"
            rm -f "$target"
            cp -a /etc/netplan.backup/. /etc/netplan/
            netplan apply >/dev/null 2>&1 || true
            exit 1
        fi
        # Log any warnings netplan may have printed even on success
        if [ -s "$netplan_err" ]; then
            log_warn "netplan apply output: $(cat "$netplan_err")"
        fi
        rm -f "$netplan_err"
        sleep 3

        target_ip="$GATEWAY"
        [ "${USE_DHCP:-true}" = "true" ] && target_ip="8.8.8.8"
        if ! timeout 30 bash -c "until ping -c1 -W1 '$target_ip' >/dev/null 2>&1; do sleep 1; done"; then
            log_error "Connectivity test failed (no reply from $target_ip) — restoring backup"
            rm -f "$target"
            cp -a /etc/netplan.backup/. /etc/netplan/
            netplan apply >/dev/null 2>&1 || true
            exit 1
        fi
        log_info "Connectivity verified ($target_ip reachable)"
    fi
fi

# 6. Verification (informational)
log_info "Active interface state:"
run_quiet ip -brief addr show "$NETWORK_INTERFACE" | sed 's/^/  /' || true
log_info "Routing table:"
run_quiet ip -4 route | sed 's/^/  /' || true
log_info "Listening sockets:"
run_quiet ss -tlnp | head -n 20 | sed 's/^/  /' || true

log_info "IP configuration complete"
