#!/usr/bin/env bash

set -euxo pipefail

source "$(dirname "$0")/common.sh"

/bin/bash "$CUR_DIR/setup_homebrew.sh"
