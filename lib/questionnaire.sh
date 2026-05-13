#!/usr/bin/env bash
# lib/questionnaire.sh — Interactive questionnaire for all toolkit setup prompts
#
# This module collects all user input upfront, allowing the toolkit to run
# unattended after the initial questionnaire. All answers are stored as
# environment variables that persist across module execution.
#
# Usage: source this file and call questionnaire_run to collect all answers
#
# Environment variables set by this questionnaire:
#   ADMIN_MODE_CREATE_USER      "yes" to create new user, "no" to change password
#   ADMIN_USER                  Username for new admin user or existing user
#   ADMIN_PASSWORD              Password for admin user
#   TOOLKIT_LOG_LEVEL           Log level (debug|info|warn|error)
#   HOSTNAME                    System hostname
#   NETWORK_INTERFACE           Network interface name
#   USE_DHCP                    "true" or "false" for DHCP vs static IP
#   IP_ADDRESS                  Static IP address (if not using DHCP)
#   PREFIX_LENGTH               Network prefix length (if not using DHCP)
#   GATEWAY                     Default gateway (if not using DHCP)
#   DNS_SERVERS                 Space-separated DNS servers (if not using DHCP)
#   TIMEZONE                    System timezone
#   LOCALE                      System locale
#   EMAIL_TO                    Email address for alerts
#   SMTP_RELAY_HOST             SMTP relay hostname
#   SMTP_RELAY_PORT             SMTP relay port
#   DISK_ALERT_THRESHOLD        Disk usage alert threshold percentage
#   AUTO_SECURITY_UPDATES       "true" or "false" for unattended upgrades

# questionnaire_prompt_string <prompt> [default]
# Generic string prompt. Returns the answer or default if empty.
questionnaire_prompt_string() {
    local prompt="$1"
    local default="$2"
    local answer

    if [ -n "${default:-}" ]; then
        printf '%s [%s]: ' "$prompt" "$default" >&2
    else
        printf '%s: ' "$prompt" >&2
    fi

    read -r answer
    answer="${answer:-$default}"
    echo "$answer"
}

# questionnaire_prompt_password <prompt>
# Silent password input with confirmation.
questionnaire_prompt_password() {
    local prompt="$1"

    while true; do
        printf '%s: ' "$prompt" >&2
        read -rs password1
        echo >&2

        printf 'Confirm %s: ' "$(echo "$prompt" | tr '[:upper:]' '[:lower:]')" >&2
        read -rs password2
        echo >&2

        if [ "$password1" = "$password2" ] && [ -n "$password1" ]; then
            echo "$password1"
            return 0
        fi

        log_warn "Passwords do not match or empty. Try again."
    done
}

# questionnaire_run
# Main questionnaire: prompts for all configuration needed across modules.
questionnaire_run() {
    if [ "$PLAN_MODE" = "1" ] || [ "${TOOLKIT_NONINTERACTIVE:-0}" = "1" ]; then
        log_info "Skipping questionnaire (plan mode or non-interactive)"
        return 0
    fi

    echo
    log_info "=== Ubuntu Toolkit Interactive Setup ==="
    echo

    # Section 1: Admin User Setup
    log_info "Section 1: Admin User Configuration"
    echo

    log_info "Do you want to:"
    echo "  1. Create a new sudo user"
    echo "  2. Change password for an existing sudo user"
    echo

    while true; do
        printf 'Select option (1 or 2): ' >&2
        read -r user_choice
        case "$user_choice" in
            1)
                export ADMIN_MODE_CREATE_USER="yes"
                log_info "Mode: Creating new sudo user"
                echo

                # Get username
                ADMIN_USER=$(questionnaire_prompt_string "New admin username" "admin")
                export ADMIN_USER

                # Check if user already exists
                if system_user_exists "$ADMIN_USER"; then
                    log_warn "User '$ADMIN_USER' already exists!"
                    if system_confirm "Do you want to change their password instead?" no; then
                        export ADMIN_MODE_CREATE_USER="no"
                        break
                    else
                        continue
                    fi
                fi

                # Get password
                ADMIN_PASSWORD=$(questionnaire_prompt_password "Password for $ADMIN_USER")
                export ADMIN_PASSWORD
                break
                ;;
            2)
                export ADMIN_MODE_CREATE_USER="no"
                log_info "Mode: Changing password for existing user"
                echo

                # Get existing username
                while true; do
                    ADMIN_USER=$(questionnaire_prompt_string "Existing sudo username" "root")
                    export ADMIN_USER

                    if system_user_exists "$ADMIN_USER"; then
                        break
                    fi
                    log_warn "User '$ADMIN_USER' does not exist"
                done

                # Get new password
                ADMIN_PASSWORD=$(questionnaire_prompt_password "New password for $ADMIN_USER")
                export ADMIN_PASSWORD
                break
                ;;
            *)
                log_warn "Invalid choice. Enter 1 or 2."
                ;;
        esac
    done

    echo
    # Section 2: System Configuration
    log_info "Section 2: System Configuration"
    echo

    TOOLKIT_LOG_LEVEL=$(questionnaire_prompt_string "Log level" "info")
    export TOOLKIT_LOG_LEVEL

    HOSTNAME=$(questionnaire_prompt_string "Hostname" "server.local.lan")
    export HOSTNAME

    TIMEZONE=$(questionnaire_prompt_string "Timezone" "Europe/Amsterdam")
    export TIMEZONE

    LOCALE=$(questionnaire_prompt_string "Locale" "nl_NL.UTF-8")
    export LOCALE

    echo

    # Section 3: Network Configuration
    log_info "Section 3: Network Configuration"
    echo

    NETWORK_INTERFACE=$(questionnaire_prompt_string "Network interface" "ens3")
    export NETWORK_INTERFACE

    USE_DHCP=$(questionnaire_prompt_string "Use DHCP? (true/false)" "false")
    export USE_DHCP

    if [ "$USE_DHCP" = "false" ]; then
        IP_ADDRESS=$(questionnaire_prompt_string "IP address" "192.168.1.10")
        export IP_ADDRESS

        PREFIX_LENGTH=$(questionnaire_prompt_string "Network prefix length" "24")
        export PREFIX_LENGTH

        GATEWAY=$(questionnaire_prompt_string "Gateway" "192.168.1.1")
        export GATEWAY

        DNS_SERVERS=$(questionnaire_prompt_string "DNS servers (space-separated)" "1.1.1.3 1.0.0.3")
        export DNS_SERVERS
    fi

    echo

    # Section 4: Email and Alerts
    log_info "Section 4: Email and Alerts Configuration"
    echo

    EMAIL_TO=$(questionnaire_prompt_string "Email for alerts" "admin@example.com")
    export EMAIL_TO

    SMTP_RELAY_HOST=$(questionnaire_prompt_string "SMTP relay host" "smtp.example.com")
    export SMTP_RELAY_HOST

    SMTP_RELAY_PORT=$(questionnaire_prompt_string "SMTP relay port" "587")
    export SMTP_RELAY_PORT

    DISK_ALERT_THRESHOLD=$(questionnaire_prompt_string "Disk alert threshold (%)" "85")
    export DISK_ALERT_THRESHOLD

    echo

    # Section 5: Security Updates
    log_info "Section 5: Security Configuration"
    echo

    AUTO_SECURITY_UPDATES=$(questionnaire_prompt_string "Enable auto security updates? (true/false)" "true")
    export AUTO_SECURITY_UPDATES

    echo
    log_info "Questionnaire complete. Setup will proceed with your answers."
    echo
}

# questionnaire_create_config <toolkit_root>
# Generate defaults.conf from questionnaire answers
questionnaire_create_config() {
    local toolkit_root="$1"
    local conf_file="$toolkit_root/config/defaults.conf"

    cat > "$conf_file" <<'EOF'
# Ubuntu Server 26.04 LTS Configuration Toolkit — defaults
# Generated by interactive questionnaire
#
# Variables prompted interactively (or via env var) — NOT in this file:
#   ADMIN_USER, ADMIN_PASSWORD       (script 01)

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
EOF

    echo "TOOLKIT_LOG_LEVEL=\"${TOOLKIT_LOG_LEVEL:-info}\"" >> "$conf_file"

    cat >> "$conf_file" <<'EOF'

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------
EOF

    echo "NETWORK_INTERFACE=\"${NETWORK_INTERFACE:-ens3}\"" >> "$conf_file"
    echo "USE_DHCP=\"${USE_DHCP:-false}\"" >> "$conf_file"
    echo "IP_ADDRESS=\"${IP_ADDRESS:-192.168.1.10}\"" >> "$conf_file"
    echo "PREFIX_LENGTH=\"${PREFIX_LENGTH:-24}\"" >> "$conf_file"
    echo "GATEWAY=\"${GATEWAY:-192.168.1.1}\"" >> "$conf_file"
    echo "DNS_SERVERS=\"${DNS_SERVERS:-1.1.1.3 1.0.0.3}\"" >> "$conf_file"

    cat >> "$conf_file" <<'EOF'

# ---------------------------------------------------------------------------
# System identity
# ---------------------------------------------------------------------------
EOF

    echo "HOSTNAME=\"${HOSTNAME:-server.local.lan}\"" >> "$conf_file"

    cat >> "$conf_file" <<'EOF'

# ---------------------------------------------------------------------------
# Time / NTP
# ---------------------------------------------------------------------------
NTP_SERVERS=(
  "0.nl.pool.ntp.org"
  "1.nl.pool.ntp.org"
  "2.nl.pool.ntp.org"
  "3.nl.pool.ntp.org"
)
FALLBACK_NTP="time.cloudflare.com time.google.com"

EOF

    echo "TIMEZONE=\"${TIMEZONE:-Europe/Amsterdam}\"" >> "$conf_file"
    echo "LOCALE=\"${LOCALE:-nl_NL.UTF-8}\"" >> "$conf_file"

    cat >> "$conf_file" <<'EOF'

# ---------------------------------------------------------------------------
# Email / SMTP relay
# ---------------------------------------------------------------------------
EOF

    echo "EMAIL_TO=\"${EMAIL_TO:-admin@example.com}\"" >> "$conf_file"
    echo "SMTP_RELAY_HOST=\"${SMTP_RELAY_HOST:-smtp.example.com}\"" >> "$conf_file"
    echo "SMTP_RELAY_PORT=\"${SMTP_RELAY_PORT:-587}\"" >> "$conf_file"

    cat >> "$conf_file" <<'EOF'

# ---------------------------------------------------------------------------
# Alerts
# ---------------------------------------------------------------------------
EOF

    echo "DISK_ALERT_THRESHOLD=${DISK_ALERT_THRESHOLD:-85}" >> "$conf_file"

    cat >> "$conf_file" <<'EOF'

# ---------------------------------------------------------------------------
# Unattended upgrades
# ---------------------------------------------------------------------------
EOF

    echo "AUTO_SECURITY_UPDATES=\"${AUTO_SECURITY_UPDATES:-true}\"" >> "$conf_file"

    chmod 600 "$conf_file"
    log_info "Created config file: $conf_file (mode 600)"
}
