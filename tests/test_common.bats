#!/usr/bin/env bats
# Unit tests for lib/* helpers — safe to run without root.

setup() {
    TOOLKIT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export TOOLKIT_ROOT
    export TOOLKIT_PERSISTENT_DIR="$BATS_TEST_TMPDIR/persistent"
    export TOOLKIT_LOG_FILE="$BATS_TEST_TMPDIR/test.log"
    mkdir -p "$TOOLKIT_PERSISTENT_DIR"
    # shellcheck disable=SC1091
    source "$TOOLKIT_ROOT/lib/common.sh"
}

@test "log_info writes to log file" {
    log_info "hello world"
    grep -q "hello world" "$TOOLKIT_LOG_FILE"
}

@test "log_error writes ERROR level" {
    log_error "boom" 2>/dev/null
    grep -q "\[ERROR\]" "$TOOLKIT_LOG_FILE"
}

@test "log_debug writes DEBUG level when TOOLKIT_LOG_LEVEL=debug" {
    TOOLKIT_LOG_LEVEL=debug log_debug "debug message"
    grep -q "\[DEBUG\]" "$TOOLKIT_LOG_FILE"
}

@test "log_debug is suppressed when TOOLKIT_LOG_LEVEL=info" {
    TOOLKIT_LOG_LEVEL=info log_debug "should not appear"
    ! grep -q "\[DEBUG\]" "$TOOLKIT_LOG_FILE"
}

@test "log_info is suppressed when TOOLKIT_LOG_LEVEL=warn" {
    TOOLKIT_LOG_LEVEL=warn log_info "should not appear"
    ! grep -q "\[INFO\]" "$TOOLKIT_LOG_FILE"
}

@test "log_warn still appears when TOOLKIT_LOG_LEVEL=warn" {
    TOOLKIT_LOG_LEVEL=warn log_warn "visible warning" 2>/dev/null
    grep -q "\[WARN\]" "$TOOLKIT_LOG_FILE"
}

@test "log_check_diskspace returns 0 on /tmp" {
    run log_check_diskspace /tmp 1
    [ "$status" -eq 0 ]
}

@test "log_info works from a top-level script under set -u (regression)" {
    # Modules source lib/common.sh and call log_info directly with `set -u`
    # active. The call stack is too shallow for BASH_SOURCE[3], so the
    # logger must tolerate that without tripping nounset.
    local script="$BATS_TEST_TMPDIR/topcaller.sh"
    cat >"$script" <<EOF
set -euo pipefail
source "$TOOLKIT_ROOT/lib/common.sh"
log_info "from-top-level"
EOF
    # Invoke bash directly rather than relying on a shebang line + chmod +x,
    # so the test is robust against noexec mounts on BATS_TEST_TMPDIR.
    run bash "$script"
    if [ "$status" -ne 0 ]; then
        printf 'topcaller exited %s; output:\n%s\n' "$status" "$output" >&2
    fi
    [ "$status" -eq 0 ]
    [[ "$output" == *"from-top-level"* ]]
}

@test "config_validate fails when required vars missing" {
    unset HOSTNAME EMAIL_TO NETWORK_INTERFACE
    run config_validate
    [ "$status" -ne 0 ]
}

@test "config_validate passes with required vars set (DHCP)" {
    export HOSTNAME="test.local"
    export EMAIL_TO="a@b.com"
    export NETWORK_INTERFACE="lo"
    export USE_DHCP="true"
    run config_validate
    [ "$status" -eq 0 ]
}

@test "config_validate fails on invalid email" {
    export HOSTNAME="t.local" EMAIL_TO="not-an-email" NETWORK_INTERFACE="lo" USE_DHCP="true"
    run config_validate
    [ "$status" -ne 0 ]
}

@test "config_validate fails on invalid IP when static" {
    export HOSTNAME="t.local" EMAIL_TO="a@b.com" NETWORK_INTERFACE="lo"
    export USE_DHCP="false" IP_ADDRESS="999.0.0.1" PREFIX_LENGTH="24" GATEWAY="1.2.3.4" DNS_SERVERS="1.1.1.1"
    run config_validate
    [ "$status" -ne 0 ]
}

@test "system_user_exists detects existing user (root)" {
    run system_user_exists root
    [ "$status" -eq 0 ]
}

@test "system_user_exists returns 1 for missing user" {
    run system_user_exists nonexistent_user_xyz_$$
    [ "$status" -ne 0 ]
}

@test "state_init creates state file" {
    state_init
    [ -f "$TOOLKIT_PERSISTENT_DIR/.state" ]
}

@test "state_mark_complete + state_is_complete round trip" {
    state_init
    state_mark_complete "test-module"
    run state_is_complete "test-module"
    [ "$status" -eq 0 ]
}

@test "state_is_complete returns 1 for unknown module" {
    state_init
    run state_is_complete "never-ran"
    [ "$status" -ne 0 ]
}

@test "state_summary on empty state" {
    state_init
    run state_summary
    [ "$status" -eq 0 ]
    [[ "$output" == *"no modules"* ]]
}
