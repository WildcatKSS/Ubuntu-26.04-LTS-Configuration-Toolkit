#!/usr/bin/env bats
# Template rendering tests — verifies envsubst expansion produces valid output.
# Safe to run without root; uses only mktemp and envsubst.

setup() {
    TOOLKIT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export TOOLKIT_ROOT
}

@test "postfix-relay.conf: no unresolved \${...} patterns after envsubst" {
    local template="$TOOLKIT_ROOT/templates/postfix-relay.conf"
    local tmp
    tmp="$(mktemp)"

    export HOSTNAME="server.example.com"
    export SMTP_RELAY_HOST="smtp.example.com"
    export SMTP_RELAY_PORT="587"
    export MAIL_DOMAIN="${HOSTNAME#*.}"

    envsubst '${HOSTNAME} ${MAIL_DOMAIN} ${SMTP_RELAY_HOST} ${SMTP_RELAY_PORT}' \
        < "$template" > "$tmp"

    run grep -E '\$\{[^}]+\}' "$tmp"
    rm -f "$tmp"
    [ "$status" -ne 0 ]
}

@test "postfix-relay.conf: MAIL_DOMAIN is derived correctly from HOSTNAME" {
    export HOSTNAME="server.example.com"
    MAIL_DOMAIN="${HOSTNAME#*.}"
    [ "$MAIL_DOMAIN" = "example.com" ]
}

@test "postfix-relay.conf: MAIL_DOMAIN handles single-label hostname gracefully" {
    export HOSTNAME="server"
    MAIL_DOMAIN="${HOSTNAME#*.}"
    [ "$MAIL_DOMAIN" = "server" ]
}

@test "postfix-relay.conf: rendered output contains correct myhostname value" {
    local template="$TOOLKIT_ROOT/templates/postfix-relay.conf"
    local tmp
    tmp="$(mktemp)"

    export HOSTNAME="server.example.com"
    export SMTP_RELAY_HOST="smtp.example.com"
    export SMTP_RELAY_PORT="587"
    export MAIL_DOMAIN="${HOSTNAME#*.}"

    envsubst '${HOSTNAME} ${MAIL_DOMAIN} ${SMTP_RELAY_HOST} ${SMTP_RELAY_PORT}' \
        < "$template" > "$tmp"

    run grep "^myhostname = server.example.com$" "$tmp"
    rm -f "$tmp"
    [ "$status" -eq 0 ]
}

@test "postfix-relay.conf: rendered output contains correct mydomain value" {
    local template="$TOOLKIT_ROOT/templates/postfix-relay.conf"
    local tmp
    tmp="$(mktemp)"

    export HOSTNAME="server.example.com"
    export SMTP_RELAY_HOST="smtp.example.com"
    export SMTP_RELAY_PORT="587"
    export MAIL_DOMAIN="${HOSTNAME#*.}"

    envsubst '${HOSTNAME} ${MAIL_DOMAIN} ${SMTP_RELAY_HOST} ${SMTP_RELAY_PORT}' \
        < "$template" > "$tmp"

    run grep "^mydomain   = example.com$" "$tmp"
    rm -f "$tmp"
    [ "$status" -eq 0 ]
}

@test "postfix-relay.conf: native postfix \$mydomain references are preserved" {
    local template="$TOOLKIT_ROOT/templates/postfix-relay.conf"
    local tmp
    tmp="$(mktemp)"

    export HOSTNAME="server.example.com"
    export SMTP_RELAY_HOST="smtp.example.com"
    export SMTP_RELAY_PORT="587"
    export MAIL_DOMAIN="${HOSTNAME#*.}"

    envsubst '${HOSTNAME} ${MAIL_DOMAIN} ${SMTP_RELAY_HOST} ${SMTP_RELAY_PORT}' \
        < "$template" > "$tmp"

    run grep '\$mydomain' "$tmp"
    rm -f "$tmp"
    [ "$status" -eq 0 ]
}
