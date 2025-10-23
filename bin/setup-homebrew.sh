#!/usr/bin/env bash

set -Eeuo pipefail

source "$(dirname "$0")/lib/common.sh"

fmt_title_underline "Setting up Homebrew"

# Check if Homebrew is already installed
if test "$(command -v brew)"; then
  log_info "Homebrew already installed."
else
  # Install Homebrew
  curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | bash --login

  # Add Homebrew to PATH for this session
  if [ -f /home/linuxbrew/.linuxbrew/bin/brew ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  fi
  log_success "Homebrew installed successfully."
fi

# Update Homebrew
log_info "Updating Homebrew..."
brew update
log_success "Homebrew updated."

# Unlink openssl@1.1 on macOS to avoid conflicts with openssl@3
if [[ "$OSTYPE" == "darwin"* ]]; then
  if brew list openssl@1.1 &>/dev/null; then
    log_info "Unlinking openssl@1.1 on macOS..."
    brew unlink openssl@1.1
  fi
  # Force remove openssl symlink if it still exists
  if [[ -L /opt/homebrew/bin/openssl ]]; then
    log_info "Removing conflicting openssl symlink..."
    rm -f /opt/homebrew/bin/openssl
    log_success "Conflicting symlink removed."
  fi
fi

# Install packages from Brewfile
log_info "Installing packages from Brewfile..."
brew bundle --file="${DOTFILES}/config/homebrew/Brewfile"
log_success "Packages installed from Brewfile."
