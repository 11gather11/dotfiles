#!/usr/bin/env bash

set -euxo pipefail

source "$(dirname "$0")/common.sh"

log_info "Setting up Git configuration..."

GITCONFIG_LOCAL="$HOME/.gitconfig-local"

# Check if running in CI environment
if [ -n "${CI:-}" ]; then
  log_info "CI environment detected. Skipping Git configuration setup."
  exit 0
fi

# Check if .gitconfig-local already exists
if [ -f "$GITCONFIG_LOCAL" ]; then
  log_warning ".gitconfig-local already exists."
  read -p "Do you want to overwrite it? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Skipping Git configuration setup."
    exit 0
  fi
fi

# Prompt for user information
read -p "Enter your Git user name: " git_name
read -p "Enter your Git email: " git_email
read -p "Enter your GitHub username: " github_user

# Create .gitconfig-local
cat > "$GITCONFIG_LOCAL" << EOF
[user]
  name = $git_name
  email = $git_email

[github]
  user = $github_user
EOF

log_success "Git configuration created at $GITCONFIG_LOCAL"
