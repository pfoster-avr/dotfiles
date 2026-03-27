#!/bin/sh

# Personal dotfiles install script for Coder.
# Configure in Coder UI: workspace → Settings → Parameters → dotfiles URI
# Runs after corporate install.sh, before workspace is marked "Ready".

PERSIST_SCRIPT="/workspaces/av/junk/pfoster/persist_home.sh"

if [ -x "$PERSIST_SCRIPT" ]; then
  echo "Starting home directory backup daemon..."
  nohup "$PERSIST_SCRIPT" > /tmp/persist_home.log 2>&1 &
  disown
  echo "Backup daemon started (PID $!, log at /tmp/persist_home.log)"
fi
