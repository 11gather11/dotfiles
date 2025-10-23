#!/usr/bin/env bash

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

cleanup() {
  trap - SIGINT SIGTERM ERR EXIT
  tput cnorm # enable cursor
  # script cleanup here
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)"

if [[ -f "$script_dir/lib/common.sh" ]]; then
  source "$script_dir/lib/common.sh"
else
  echo "Error: Unable to source common.sh"
  exit 1
fi




source "$DOTFILES/bin/setup-links.sh"
source "$DOTFILES/bin/setup-homebrew.sh"
source "$DOTFILES/bin/setup-mise.sh"
source "$DOTFILES/bin/setup-shell.sh"
source "$DOTFILES/bin/setup-fisher.sh"
source "$DOTFILES/bin/setup-git.sh"
