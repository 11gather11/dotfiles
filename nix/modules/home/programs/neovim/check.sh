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

"$NVIM_BIN" --headless "+Lazy! $ACTION" +qa

# `--headless` reports a failed startup command on stderr and still exits 0, so
# the run above proves nothing on its own: a Neovim that never found the config
# answers `E492: Not an editor command: Lazy!` and reports success, which is how
# CI passed for months while checking nothing. Ask Lazy.nvim itself instead —
# `cq` is the headless way to exit non-zero. Warnings the config prints on the
# way (nvim-treesitter has no CLI in CI, say) leave this assertion alone.
"$NVIM_BIN" --headless \
  -c 'lua local ok, lazy = pcall(require, "lazy"); if not ok or #lazy.plugins() == 0 then vim.cmd("cq") end' \
  -c 'qa'

mkdir -p "$LAZY_DIR"
touch "$LAZY_LOCK_TIMESTAMP"
echo "✅ Lazy! $ACTION finished."
