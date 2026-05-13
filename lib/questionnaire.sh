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
#   ADMIN_PASSWORD_CONFIRM      (internal validation only)

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
    log_info "Questionnaire complete. Setup will proceed with your answers."
    echo
}

# questionnaire_export_to_env
# (Optional) Export all questionnaire answers to a sourceable environment file.
questionnaire_export_to_env() {
    local env_file="${1:-.toolkit-env}"
    {
        [ -n "${ADMIN_MODE_CREATE_USER:-}" ] && echo "export ADMIN_MODE_CREATE_USER='$ADMIN_MODE_CREATE_USER'"
        [ -n "${ADMIN_USER:-}" ] && echo "export ADMIN_USER='$ADMIN_USER'"
        [ -n "${ADMIN_PASSWORD:-}" ] && echo "export ADMIN_PASSWORD='$ADMIN_PASSWORD'"
    } > "$env_file"
    log_info "Questionnaire answers saved to: $env_file"
}
