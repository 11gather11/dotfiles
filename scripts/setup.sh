#!/usr/bin/env bash

set -euxo pipefail

source "$(dirname "$0")/common.sh"

source "$CUR_DIR/setup-homebrew.sh"
source "$CUR_DIR/setup-links.sh"
source "$CUR_DIR/setup-mise.sh"
source "$CUR_DIR/setup-shell.sh"
source "$CUR_DIR/setup-fisher.sh"
source "$CUR_DIR/setup-git.sh"
