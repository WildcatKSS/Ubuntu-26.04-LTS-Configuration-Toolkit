#!/usr/bin/env bash
# lib/version.sh — Semantic versioning helpers
# Part of Ubuntu Server 26.04 LTS Configuration Toolkit

TOOLKIT_VERSION_FILE="${TOOLKIT_ROOT}/VERSION"

toolkit_get_version() {
  if [ -f "$TOOLKIT_VERSION_FILE" ]; then
    cat "$TOOLKIT_VERSION_FILE"
  else
    echo "unknown"
  fi
}

toolkit_version_info() {
  local version
  version=$(toolkit_get_version)
  echo "Ubuntu Server 26.04 LTS Configuration Toolkit v${version}"
}

toolkit_validate_version_format() {
  local version="$1"
  if [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?(\+[a-zA-Z0-9.]+)?$ ]]; then
    return 0
  fi
  return 1
}
