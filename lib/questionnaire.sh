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
#   ADMIN_MODE_CREATE_USER      "yes" to create new user, "no" to change password, "skip" to leave unchanged
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
#   SEND_TEST_MAIL              "yes" to send a test mail after postfix setup

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
    if [ "${TOOLKIT_PLAN_MODE:-0}" = "1" ] || [ "${TOOLKIT_NONINTERACTIVE:-0}" = "1" ]; then
        log_info "Skipping questionnaire (plan mode or non-interactive)"
        return 0
    fi

    echo
    log_info "=== Ubuntu Toolkit Interactive Setup ==="
    echo
    echo "Dit script configureert een verse Ubuntu Server 26.04 LTS installatie end-to-end."
    echo "Beantwoord de vragen per sectie. Druk op Enter om de standaardwaarde te accepteren."
    echo

    # -------------------------------------------------------------------------
    # Section 1: Admin User
    # -------------------------------------------------------------------------
    log_info "Sectie 1: Beheerder (sudo gebruiker)"
    echo
    echo "De toolkit maakt of configureert een gebruiker met sudo-rechten."
    echo "Deze account wordt gebruikt voor beheer na de installatie."
    echo "Root-login via SSH wordt na de installatie uitgeschakeld, dus"
    echo "zorg dat deze gebruiker correct is ingesteld voordat je doorgaat."
    echo

    if [ "${ADMIN_MODE_CREATE_USER:-}" = "skip" ]; then
        log_info "Beheerder configuratie overgeslagen (ADMIN_MODE_CREATE_USER=skip)"
    else

    log_info "Wat wil je doen met de beheerder?"
    echo "  1. Nieuwe sudo gebruiker aanmaken"
    echo "  2. Wachtwoord wijzigen van een bestaande sudo gebruiker"
    echo "  3. Overslaan (geen wijzigingen aan sudo gebruiker)"
    echo

    while true; do
        printf 'Kies optie (1, 2 of 3): ' >&2
        read -r user_choice
        case "$user_choice" in
            1)
                export ADMIN_MODE_CREATE_USER="yes"
                log_info "Modus: Nieuwe sudo gebruiker aanmaken"
                echo

                ADMIN_USER=$(questionnaire_prompt_string "Gebruikersnaam nieuwe beheerder" "admin")
                export ADMIN_USER

                if system_user_exists "$ADMIN_USER"; then
                    log_warn "Gebruiker '$ADMIN_USER' bestaat al!"
                    if system_confirm "Wachtwoord van deze gebruiker wijzigen?" no; then
                        export ADMIN_MODE_CREATE_USER="no"
                        break
                    else
                        continue
                    fi
                fi

                ADMIN_PASSWORD=$(questionnaire_prompt_password "Wachtwoord voor $ADMIN_USER")
                export ADMIN_PASSWORD
                break
                ;;
            2)
                export ADMIN_MODE_CREATE_USER="no"
                log_info "Modus: Wachtwoord wijzigen bestaande gebruiker"
                echo

                while true; do
                    ADMIN_USER=$(questionnaire_prompt_string "Gebruikersnaam bestaande sudo gebruiker" "root")
                    export ADMIN_USER

                    if system_user_exists "$ADMIN_USER"; then
                        break
                    fi
                    log_warn "Gebruiker '$ADMIN_USER' bestaat niet"
                done

                ADMIN_PASSWORD=$(questionnaire_prompt_password "Nieuw wachtwoord voor $ADMIN_USER")
                export ADMIN_PASSWORD
                break
                ;;
            3)
                export ADMIN_MODE_CREATE_USER="skip"
                log_info "Modus: Sudo gebruiker configuratie overgeslagen"
                break
                ;;
            *)
                log_warn "Ongeldige keuze. Voer 1, 2 of 3 in."
                ;;
        esac
    done

    fi  # end ADMIN_MODE_CREATE_USER != skip

    echo

    # -------------------------------------------------------------------------
    # Section 2: System Configuration
    # -------------------------------------------------------------------------
    log_info "Sectie 2: Systeeminstellingen"
    echo
    echo "Basisidentiteit van de server: hostnaam, tijdzone en taal."
    echo "De hostnaam wordt gebruikt in e-mailmeldingen en logregels."
    echo "De tijdzone bepaalt de lokale tijd voor cron-jobs en logbestanden."
    echo "Het log-niveau regelt hoeveel detail de toolkit naar het logbestand schrijft."
    echo

    TOOLKIT_LOG_LEVEL=$(questionnaire_prompt_string "Log niveau (debug|info|warn|error)" "info")
    export TOOLKIT_LOG_LEVEL

    HOSTNAME=$(questionnaire_prompt_string "Hostnaam van de server" "server.local.lan")
    export HOSTNAME

    TIMEZONE=$(questionnaire_prompt_string "Tijdzone" "Europe/Amsterdam")
    export TIMEZONE

    LOCALE=$(questionnaire_prompt_string "Systeemtaal (locale)" "nl_NL.UTF-8")
    export LOCALE

    echo

    # -------------------------------------------------------------------------
    # Section 3: Network Configuration
    # -------------------------------------------------------------------------
    log_info "Sectie 3: Netwerkconfiguratie"
    echo
    echo "Configuratie van het primaire netwerkinterface via Netplan."
    echo "Kies DHCP als het netwerk automatisch een IP-adres toewijst."
    echo "Kies statisch als de server altijd hetzelfde IP-adres moet hebben"
    echo "(aanbevolen voor servers die bereikbaar moeten zijn op een vast adres)."
    echo "Let op: een verkeerde netwerkconfiguratie kan de SSH-verbinding verbreken."
    echo "De toolkit maakt automatisch een backup van de bestaande Netplan-config."
    echo

    NETWORK_INTERFACE=$(questionnaire_prompt_string "Naam van het netwerkinterface" "ens3")
    export NETWORK_INTERFACE

    USE_DHCP=$(questionnaire_prompt_string "DHCP gebruiken? (true/false)" "false")
    export USE_DHCP

    if [ "$USE_DHCP" = "false" ]; then
        IP_ADDRESS=$(questionnaire_prompt_string "Statisch IP-adres" "192.168.1.10")
        export IP_ADDRESS

        PREFIX_LENGTH=$(questionnaire_prompt_string "Netwerkprefix lengte (bijv. 24 voor /24)" "24")
        export PREFIX_LENGTH

        GATEWAY=$(questionnaire_prompt_string "Standaard gateway" "192.168.1.1")
        export GATEWAY

        DNS_SERVERS=$(questionnaire_prompt_string "DNS-servers (spatie-gescheiden)" "1.1.1.3 1.0.0.3")
        export DNS_SERVERS
    fi

    echo

    # -------------------------------------------------------------------------
    # Section 4: Email and Alerts
    # -------------------------------------------------------------------------
    log_info "Sectie 4: E-mail en meldingen"
    echo
    echo "De toolkit configureert Postfix als SMTP-relay voor e-mailmeldingen."
    echo "Je ontvangt dagelijkse rapportages over de serverstatus en directe"
    echo "waarschuwingen bij hoge schijfbezetting of uitgevallen services."
    echo "Vul het adres in van je eigen SMTP-relay (bijv. je mailprovider of"
    echo "een interne mailserver). Authenticatiecredentials sla je op in"
    echo "/etc/postfix/sasl_passwd na de installatie."
    echo

    EMAIL_TO=$(questionnaire_prompt_string "E-mailadres voor meldingen" "admin@example.com")
    export EMAIL_TO

    SMTP_RELAY_HOST=$(questionnaire_prompt_string "SMTP relay hostname" "smtp.example.com")
    export SMTP_RELAY_HOST

    SMTP_RELAY_PORT=$(questionnaire_prompt_string "SMTP relay poort" "587")
    export SMTP_RELAY_PORT

    DISK_ALERT_THRESHOLD=$(questionnaire_prompt_string "Schijfgebruik drempel voor melding (%)" "85")
    export DISK_ALERT_THRESHOLD

    echo
    echo "Na de installatie van Postfix kan een testmail verstuurd worden naar"
    echo "$EMAIL_TO om te controleren of de mailrelay correct werkt."
    echo

    while true; do
        printf 'Testmail sturen na Postfix installatie? (ja/nee) [nee]: ' >&2
        read -r test_mail_choice
        test_mail_choice="${test_mail_choice:-nee}"
        case "$test_mail_choice" in
            ja|j|yes|y)
                export SEND_TEST_MAIL="yes"
                log_info "Testmail wordt verstuurd na Postfix configuratie"
                break
                ;;
            nee|n|no)
                export SEND_TEST_MAIL="no"
                break
                ;;
            *)
                log_warn "Ongeldige keuze. Voer 'ja' of 'nee' in."
                ;;
        esac
    done

    echo

    # -------------------------------------------------------------------------
    # Section 5: Security Updates
    # -------------------------------------------------------------------------
    log_info "Sectie 5: Beveiligingsupdates"
    echo
    echo "Unattended-upgrades installeert beveiligingsupdates automatisch,"
    echo "zonder handmatige tussenkomst. Dit houdt de server up-to-date tegen"
    echo "bekende kwetsbaarheden. Alleen beveiligingspakketten worden automatisch"
    echo "bijgewerkt; grote versie-upgrades vereisen altijd handmatige actie."
    echo

    AUTO_SECURITY_UPDATES=$(questionnaire_prompt_string "Automatische beveiligingsupdates inschakelen? (true/false)" "true")
    export AUTO_SECURITY_UPDATES

    echo
    log_info "Vragenlijst compleet. De installatie start met de opgegeven instellingen."
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
# Admin user
# ---------------------------------------------------------------------------
EOF

    echo "ADMIN_MODE_CREATE_USER=\"${ADMIN_MODE_CREATE_USER:-yes}\"" >> "$conf_file"

    cat >> "$conf_file" <<'EOF'

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
    echo "SEND_TEST_MAIL=\"${SEND_TEST_MAIL:-no}\"" >> "$conf_file"

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
    log_info "Configuratiebestand aangemaakt: $conf_file (mode 600)"
}
