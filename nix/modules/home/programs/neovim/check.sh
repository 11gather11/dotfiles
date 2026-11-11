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

# Lazy.nvim ends every run by writing lazy-lock.json from whatever is checked
# out, and a restore whose fetch failed still exits cleanly. The lock is then
# rewritten with the old revisions, undoing the update that was just pulled.
# A restore must never change the lock, so keep a copy to put back.
if [[ $ACTION == restore ]]; then
  LOCK_BEFORE="$(mktemp)"
  trap 'rm -f "$LOCK_BEFORE"' EXIT
  cp "$LAZY_LOCK" "$LOCK_BEFORE"
fi

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

# Leave the timestamp untouched, so the lock stays newer than it and the next
# switch tries the restore again.
if [[ $ACTION == restore ]] && ! cmp -s "$LOCK_BEFORE" "$LAZY_LOCK"; then
  cp "$LOCK_BEFORE" "$LAZY_LOCK"
  echo "⚠️  Lazy! restore did not reach the revisions in lazy-lock.json; kept the lock and will retry on the next switch." >&2
  exit 0
fi

mkdir -p "$LAZY_DIR"
touch "$LAZY_LOCK_TIMESTAMP"
echo "✅ Lazy! $ACTION finished."
