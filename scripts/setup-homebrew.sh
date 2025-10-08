#!/usr/bin/env bash

set -euxo pipefail

source "$(dirname "$0")/common.sh"

# Skip if running on macOS (Homebrew is already installed)
[ "$(uname)" = "Darwin" ] && exit 0

# Skip if SKIP_HOMEBREW is set
[ -n "${SKIP_HOMEBREW:-}" ] && exit 0

# Check if Homebrew is already installed
if command -v brew &> /dev/null; then
    echo "Homebrew is already installed."
else
    # Install Homebrew
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add Homebrew to PATH for this session
    if [ -f /home/linuxbrew/.linuxbrew/bin/brew ]; then
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi
fi

# Update Homebrew
echo "Updating Homebrew..."
brew update

# Install packages from Brewfile
echo "Installing packages from Brewfile..."
brew bundle install --file "${REPO_DIR}/config/homebrew/Brewfile" --verbose
