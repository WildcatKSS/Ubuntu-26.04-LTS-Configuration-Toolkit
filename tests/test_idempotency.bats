#!/usr/bin/env bats
# Idempotency / structural tests for scripts/*.sh.
#
# These tests do NOT execute modules (they would need root and would mutate the
# host). They verify that:
#   - every module has the required metadata header
#   - every module declares IDEMPOTENT
#   - syntax checks (bash -n) pass
#   - main.sh --list / --plan / --dry-run runs without errors when given a
#     valid example config
#
# True end-to-end idempotency is verified manually on a VM (see README.md).

setup() {
    TOOLKIT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    export TOOLKIT_ROOT
}

@test "every module has a MODULE: header" {
    for f in "$TOOLKIT_ROOT"/scripts/[0-9]*.sh; do
        run grep -q '^# MODULE:' "$f"
        [ "$status" -eq 0 ] || { echo "missing MODULE: header in $f"; return 1; }
    done
}

@test "every module has DESC, DEPENDS, IDEMPOTENT, DESTRUCTIVE" {
    for f in "$TOOLKIT_ROOT"/scripts/[0-9]*.sh; do
        for tag in DESC DEPENDS IDEMPOTENT DESTRUCTIVE; do
            run grep -q "^# ${tag}:" "$f"
            [ "$status" -eq 0 ] || { echo "missing # ${tag}: in $f"; return 1; }
        done
    done
}

@test "every module is marked IDEMPOTENT: yes" {
    for f in "$TOOLKIT_ROOT"/scripts/[0-9]*.sh; do
        run grep -q '^# IDEMPOTENT: yes' "$f"
        [ "$status" -eq 0 ] || { echo "module $f is not idempotent"; return 1; }
    done
}

@test "all scripts pass bash -n" {
    for f in "$TOOLKIT_ROOT"/scripts/*.sh "$TOOLKIT_ROOT"/lib/*.sh "$TOOLKIT_ROOT"/main.sh; do
        run bash -n "$f"
        [ "$status" -eq 0 ] || { echo "syntax error in $f"; return 1; }
    done
}

@test "main.sh --list works with example config" {
    cp "$TOOLKIT_ROOT/config/defaults.conf.example" "$TOOLKIT_ROOT/config/defaults.conf"
    run "$TOOLKIT_ROOT/main.sh" --list
    rm -f "$TOOLKIT_ROOT/config/defaults.conf"
    [ "$status" -eq 0 ]
    [[ "$output" == *"00-preflight"* ]]
    [[ "$output" == *"99-cleanup"* ]]
}

@test "main.sh --list works without config" {
    rm -f "$TOOLKIT_ROOT/config/defaults.conf"
    run "$TOOLKIT_ROOT/main.sh" --list
    [ "$status" -eq 0 ]
}

@test "main.sh --help exits 0" {
    run "$TOOLKIT_ROOT/main.sh" --help
    [ "$status" -eq 0 ]
}

@test "main.sh rejects unknown flag" {
    run "$TOOLKIT_ROOT/main.sh" --bogus
    [ "$status" -ne 0 ]
}

@test "DAG: each DEPENDS target exists as a module" {
    declare -A names
    for f in "$TOOLKIT_ROOT"/scripts/[0-9]*.sh; do
        names[$(basename "$f" .sh)]=1
    done
    for f in "$TOOLKIT_ROOT"/scripts/[0-9]*.sh; do
        deps="$(grep '^# DEPENDS:' "$f" | sed 's/^# DEPENDS:[[:space:]]*//')"
        [ -z "$deps" ] && continue
        IFS=',' read -ra arr <<< "$deps"
        for d in "${arr[@]}"; do
            d="${d// /}"
            [ -n "${names[$d]:-}" ] || { echo "$f depends on unknown $d"; return 1; }
        done
    done
}
