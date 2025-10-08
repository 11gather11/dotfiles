#!/usr/bin/env bash
set -euxo pipefail

CUR_DIR="$(cd "$(dirname "$0")" && pwd)" || exit 1
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)" || exit 1
export CUR_DIR REPO_DIR

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
