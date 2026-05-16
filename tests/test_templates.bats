#!/usr/bin/env bats
# Template rendering tests — verifies envsubst expansion produces valid output.
# Safe to run without root; uses only mktemp and envsubst.

setup() {
    TOOLKIT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export TOOLKIT_ROOT

    export HOSTNAME="server.example.com"
    export SMTP_RELAY_HOST="smtp.example.com"
    export SMTP_RELAY_PORT="587"
    export MAIL_DOMAIN="${HOSTNAME#*.}"

    TEMPLATE="$TOOLKIT_ROOT/templates/postfix-relay.conf"
    RENDERED="$(mktemp)"
    envsubst '${HOSTNAME} ${MAIL_DOMAIN} ${SMTP_RELAY_HOST} ${SMTP_RELAY_PORT}' \
        < "$TEMPLATE" > "$RENDERED"
}

teardown() {
    rm -f "$RENDERED"
}

@test "postfix-relay.conf: no unresolved \${...} patterns after envsubst" {
    run grep -E '\$\{[^}]+\}' "$RENDERED"
    [ "$status" -ne 0 ]
}

@test "postfix-relay.conf: MAIL_DOMAIN is derived correctly from HOSTNAME" {
    [ "$MAIL_DOMAIN" = "example.com" ]
}

@test "postfix-relay.conf: MAIL_DOMAIN handles single-label hostname gracefully" {
    local h="server"
    [ "${h#*.}" = "server" ]
}

@test "postfix-relay.conf: rendered output contains correct myhostname value" {
    run grep "^myhostname = server.example.com$" "$RENDERED"
    [ "$status" -eq 0 ]
}

@test "postfix-relay.conf: rendered output contains correct mydomain value" {
    run grep "^mydomain   = example.com$" "$RENDERED"
    [ "$status" -eq 0 ]
}

@test "postfix-relay.conf: native postfix \$mydomain references are preserved" {
    run grep '\$mydomain' "$RENDERED"
    [ "$status" -eq 0 ]
}
