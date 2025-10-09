#!/usr/bin/env bash
set -euxo pipefail

CUR_DIR="$(cd "$(dirname "$0")" && pwd)" || exit 1
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)" || exit 1
export CUR_DIR REPO_DIR

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

# Basic formatting
readonly RESET='\033[0m'
readonly BOLD='\033[1m'

# Standard colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'

# Bright colors
readonly BRIGHT_RED='\033[91m'
readonly BRIGHT_GREEN='\033[92m'
readonly BRIGHT_YELLOW='\033[93m'
readonly BRIGHT_BLUE="\033[94m"

# Icons
readonly INFO_ICON="ℹ"
readonly SUCCESS_ICON="✔"
readonly WARNING_ICON="⚠"
readonly ERROR_ICON="✖"

# Logging functions with colors
log_info() {
  echo -e "${BRIGHT_BLUE}${BOLD}${INFO_ICON}${RESET} ${BLUE}$*${RESET}"
}

log_success() {
  echo -e "${BRIGHT_GREEN}${BOLD}${SUCCESS_ICON}${RESET} ${GREEN}$*${RESET}"
}

log_warning() {
  echo -e "${BRIGHT_YELLOW}${BOLD}${WARNING_ICON}${RESET} ${YELLOW}$*${RESET}"
}

log_error() {
  echo -e "${BRIGHT_RED}${BOLD}${ERROR_ICON}${RESET} ${RED}$*${RESET}" >&2
}
