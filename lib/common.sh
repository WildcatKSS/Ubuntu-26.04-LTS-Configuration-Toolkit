#!/usr/bin/env bash
# lib/common.sh — Single entry point sourcing all helper modules.
#
# Usage from a module:
#   TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
#   source "$TOOLKIT_ROOT/lib/common.sh"

_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=log.sh
source "$_lib_dir/log.sh"
# shellcheck source=config.sh
source "$_lib_dir/config.sh"
# shellcheck source=system.sh
source "$_lib_dir/system.sh"
# shellcheck source=pkg.sh
source "$_lib_dir/pkg.sh"
# shellcheck source=state.sh
source "$_lib_dir/state.sh"

unset _lib_dir
