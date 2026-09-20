#!/usr/bin/env bash
# Drive Lazy.nvim headlessly (Lazy.nvim itself is auto-installed by the Lua
# config). `restore` puts the plugins at the revisions lazy-lock.json names;
# `update` moves them to the newest and writes the lock back.
# Usage: check.sh <nvim-dotfiles-dir> <lazy-dir> <nvim-bin> [restore|update]

set -euo pipefail

NVIM_DOTFILES_DIR="$1"
LAZY_DIR="${2:-$HOME/.local/share/nvim/lazy}"
NVIM_BIN="${3:-nvim}"
ACTION="${4:-restore}"

LAZY_LOCK="$NVIM_DOTFILES_DIR/lazy-lock.json"
LAZY_LOCK_TIMESTAMP="$LAZY_DIR/.lazy-lock-timestamp"

if [[ ! -f $LAZY_LOCK ]]; then
  echo "No lazy-lock.json at $LAZY_LOCK, nothing to do."
  exit 0
fi

# Point Neovim at the checkout rather than at ~/.config/nvim. On this machine
# the two are the same directory through a symlink, but in CI nothing links
# them, and Neovim started without a config runs no Lazy command at all.
export XDG_CONFIG_HOME="$(dirname "$NVIM_DOTFILES_DIR")"

echo "📦 Running Lazy! $ACTION..."

# `--headless` reports a failed startup command on stderr and still exits 0, so
# the output is what has to be inspected. Without this the whole run is
# vacuous: a missing config answers `E492: Not an editor command: Lazy!` and
# reports success, which is how CI passed while checking nothing.
output=$("$NVIM_BIN" --headless "+Lazy! $ACTION" +qa 2>&1)
printf '%s\n' "$output"

if grep -qE '^E[0-9]+:|Error( in command line|:)' <<<"$output"; then
  echo "❌ Neovim reported an error above." >&2
  exit 1
fi

mkdir -p "$LAZY_DIR"
touch "$LAZY_LOCK_TIMESTAMP"
echo "✅ Lazy! $ACTION finished."
