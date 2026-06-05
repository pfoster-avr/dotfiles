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

    # Build the exclude list of circular symlink loops. `grep` exits 1 when there are no loops,
    # which is the normal case — so tolerate it (|| true) and keep this OUT of the rsync `if`
    # condition. Otherwise `set -o pipefail` turns "no loops" into a fake rsync failure and the
    # backup gets skipped/logged as an error.
    ( cd "$HOME/" && { find -L . \( -name ".cache" -o -name ".av_bazel_cache" \) -prune -type l 2>&1 >/dev/null ; true; } \
        | grep "loop" | awk -F'‘|’' '{print $2}' | sed 's|^\./||' ) > /tmp/excludes.txt || true

    if sudo rsync -aAXSH --delete \
         --exclude='**.cache' --exclude='.av_bazel_cache' --exclude='.nix-defexpr/channels_root' \
         --exclude-from=/tmp/excludes.txt \
         "$HOME/" "$BACKUP_NEXT/" && \
       sudo rsync -aAXSH -L \
         --exclude='**.cache' --exclude='.av_bazel_cache' --exclude='.nix-defexpr/channels_root' \
         --exclude-from=/tmp/excludes.txt \
         "$HOME/" "$BACKUP_NEXT/"; then
      echo "$(date -Iseconds) Rsync succeeded, rotating backup..." >> "$SENTINEL"
      # Rotate so a COMPLETE backup always survives even if a step is interrupted (e.g. reboot):
      # clear any stale OLD first (this is what previously wedged: a leftover OLD made
      # `mv DIR OLD` nest instead of rename), then demote DIR -> OLD, promote NEXT -> DIR, drop OLD.
      # Every step is checked; on failure we roll back and log a REAL error instead of
      # unconditionally printing "Backup complete." like the old code did.
      rm -rf "$BACKUP_OLD"
      rotated=0
      if [ -e "$BACKUP_DIR" ]; then
        mv "$BACKUP_DIR" "$BACKUP_OLD" && mv "$BACKUP_NEXT" "$BACKUP_DIR" && rotated=1
      else
        mv "$BACKUP_NEXT" "$BACKUP_DIR" && rotated=1   # first run: no DIR to demote
      fi
      if [ "$rotated" = 1 ]; then
        rm -rf "$BACKUP_OLD"
        echo "$(date -Iseconds) Backup complete." >> "$SENTINEL"
      else
        [ -e "$BACKUP_DIR" ] || { [ -e "$BACKUP_OLD" ] && mv "$BACKUP_OLD" "$BACKUP_DIR"; }
        echo "$(date -Iseconds) ERROR: rotation failed; BACKUP_NEXT kept, BACKUP_DIR intact." >> "$SENTINEL"
      fi
    else
      echo "$(date -Iseconds) ERROR: rsync failed, keeping previous backup intact." >> "$SENTINEL"
    fi
  fi

  sleep "$INTERVAL"
done
