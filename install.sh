#!/bin/sh
set -ue

# Personal dotfiles install script for Coder.
# Place this as install.sh in the root of your personal dotfiles repo.
# Configure the repo URL in Coder UI: workspace → Settings → Parameters → dotfiles URI
#
# This runs after the corporate install.sh, before the workspace is marked "Ready".

# Persist home directory across container rebuilds
# If /workspaces/.home exists (created by persist_home.sh), bind-mount it
# over $HOME so all home dir state survives container restarts.
if [ -d "/workspaces/.home" ]; then
  echo "Restoring persistent home directory..."

  # Capture the cache mount device BEFORE the bind mount hides it
  CACHE_DEV=$(findmnt -n -o SOURCE --target "$HOME/.cache" 2>/dev/null | sed 's/\[.*//') || true

  sudo mount --bind /workspaces/.home "$HOME"

  mkdir -p "$HOME/.cache"

  # Remount the cache volume if we found it
  if [ -n "${CACHE_DEV:-}" ] && [ -b "$CACHE_DEV" ]; then
    sudo mount "$CACHE_DEV" "$HOME/.cache"
    echo "Cache remounted from $CACHE_DEV"
  fi

  echo "Persistent home directory mounted."
fi
