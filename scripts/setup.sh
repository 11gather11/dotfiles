#!/usr/bin/env bash

set -euxo pipefail

source "$(dirname "$0")/common.sh"

# Request sudo access once at the beginning (skip in CI)
if [[ -z "${CI:-}" ]]; then
  log_info "Requesting sudo access for system configuration..."
  sudo -v
  # Keep sudo credentials cached in background
  while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
fi

source "$CUR_DIR/setup-homebrew.sh"
source "$CUR_DIR/setup-links.sh"
source "$CUR_DIR/setup-mise.sh"
source "$CUR_DIR/setup-shell.sh"
source "$CUR_DIR/setup-fisher.sh"
