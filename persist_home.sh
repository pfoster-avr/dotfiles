#!/bin/zsh

# Background daemon that periodically rsyncs $HOME to persistent storage.
# Only runs the sync if $HOME/RSYNC_SENTINEL exists.
# Timestamps are logged into RSYNC_SENTINEL so you can see it's working.
#
# Restore with:
# rsync -ivaAXSH --inplace --no-l -K  --exclude='**.cache'  --exclude='.av_bazel_cache'  /workspaces/home/vscode ~/
# To see stuff you might want to delete before restoring:
# rsync --delete -nivaAXSH --inplace --no-l -K  --exclude='**.cache'  --exclude='.av_bazel_cache'  /workspaces/home/vscode ~/
BACKUP_BASE="/workspaces/home"
BACKUP_DIR="$BACKUP_BASE/vscode"
BACKUP_NEXT="$BACKUP_BASE/vscode_next"
BACKUP_OLD="$BACKUP_BASE/vscode_old"
SENTINEL="$HOME/RSYNC_SENTINEL"
INTERVAL=3600  # 1 hour
set -o pipefail

while true; do
  if [ -f "$SENTINEL" ]; then
    echo "$(date -Iseconds) Starting rsync..." >> "$SENTINEL"

    mkdir -p "$BACKUP_NEXT"

    # exclude circular links from backup
    if (cd "$HOME/" && { find -L . \( -name ".cache" -o -name ".av_bazel_cache" \) -prune -type l 2>&1 >/dev/null ; true; } | grep "loop" | awk -F'‘|’' '{print $2}' | sed 's|^\./||')  > /tmp/excludes.txt && \
       sudo rsync -aAXSH --delete \
         --exclude='**.cache' --exclude='.av_bazel_cache' --exclude='.nix-defexpr/channels_root' \
         --exclude-from=/tmp/excludes.txt \
         "$HOME/" "$BACKUP_NEXT/" && \
       sudo rsync -aAXSH -L \
         --exclude='**.cache' --exclude='.av_bazel_cache' --exclude='.nix-defexpr/channels_root' \
         --exclude-from=/tmp/excludes.txt \
         "$HOME/" "$BACKUP_NEXT/"; then
      echo "$(date -Iseconds) Rsync succeeded, rotating backup..." >> "$SENTINEL"
      mv "$BACKUP_DIR" "$BACKUP_OLD" && \
        mv "$BACKUP_NEXT" "$BACKUP_DIR" && \
        rm -rf "$BACKUP_OLD"
      echo "$(date -Iseconds) Backup complete." >> "$SENTINEL"
    else
      echo "$(date -Iseconds) ERROR: rsync failed, keeping previous backup intact." >> "$SENTINEL"
    fi
  fi

  sleep "$INTERVAL"
done
