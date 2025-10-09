#!/usr/bin/env bash

set -euxo pipefail

source "$(dirname "$0")/common.sh"

# Setup security directories with proper permissions
log_info "Setting up security directories..."
if [[ ! -d "$HOME/.ssh" ]]; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    log_success "Created $HOME/.ssh with secure permissions (700)."
else
    log_info "$HOME/.ssh already exists."
fi

if [[ ! -d "$HOME/.gnupg" ]]; then
    mkdir -p "$HOME/.gnupg"
    chmod 700 "$HOME/.gnupg"
    log_success "Created $HOME/.gnupg with secure permissions (700)."
else
    log_info "$HOME/.gnupg already exists."
fi

# Create XDG Base Directory structure
log_info "Creating XDG directories..."
mkdir -p \
  "$XDG_CONFIG_HOME" \
  "$XDG_STATE_HOME" \
  "$XDG_DATA_HOME/vim"
log_success "XDG directories created."

# Create symlinks for config files
log_info "Creating symlinks..."
ln -sfv "$REPO_DIR/config/"* "$XDG_CONFIG_HOME"
ln -sfv "$XDG_CONFIG_HOME/zsh/.zshenv" "$HOME/.zshenv"
ln -sfnv "$XDG_CONFIG_HOME/vim" "$HOME/.vim"
log_success "Symlinks created."
