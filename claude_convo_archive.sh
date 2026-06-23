#!/usr/bin/env bash
# claude_convo_archive.sh
#
# Periodically mirror ~/.claude/projects/ into a git repo and commit any changes,
# so Claude Code conversation transcripts are durably versioned and recoverable.
#
# Motivation: transcripts live in a single live file per session under
# ~/.claude/projects/. A bad tool/extension (e.g. a "view jsonl as json"
# converter) or a node failure can truncate or rename that file out from under
# the live agent. This daemon keeps an append-only git history so any prior
# state can be recovered.
#
# Launch (from dotfiles install.sh):
#   nohup ~/dotfiles/claude_convo_archive.sh > /tmp/claude_convo_archive.log 2>&1 & disown
#
# Tunables via env:
#   CLAUDE_PROJECTS_DIR  source dir         (default ~/.claude/projects)
#   CLAUDE_CONVO_REPO    archive git repo   (default /workspaces/claude_convo_repo)
#   CLAUDE_CONVO_INTERVAL  seconds between syncs (default 1800 = 30 min)
#   CLAUDE_CONVO_LOG     log file           (default /tmp/claude_convo_archive.log)

set -uo pipefail

SRC="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}/"
REPO="${CLAUDE_CONVO_REPO:-/workspaces/claude_convo_repo}"
DEST="$REPO/projects/"
INTERVAL="${CLAUDE_CONVO_INTERVAL:-1800}"
LOG="${CLAUDE_CONVO_LOG:-/tmp/claude_convo_archive.log}"

USER_NAME="$(id -un)"
GROUP_NAME="$(id -gn)"

log() { echo "$(date -u +%FT%TZ) $*" >> "$LOG"; }

# One-time repo bootstrap so the daemon is self-sufficient if the repo is missing.
if [ ! -d "$REPO/.git" ]; then
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" commit -q --allow-empty -m "init claude convo archive"
fi
mkdir -p "$DEST"

log "claude_convo_archive started: src=$SRC repo=$REPO interval=${INTERVAL}s"

while true; do
  # Mirror source -> archive working tree.
  #  --delete            : reflect removals (still recoverable from git history)
  #  sudo                : guard against any unreadable files under the source tree
  #  --chown/--chmod     : keep the mirror owned/readable by us so `git add` works
  #                        despite sudo (otherwise files land root:root 0600)
  if ! sudo rsync -a --delete \
        --chown="${USER_NAME}:${GROUP_NAME}" --chmod=Du+rwx,Fu+rw \
        "$SRC" "$DEST" >> "$LOG" 2>&1; then
    log "rsync failed; will retry next cycle"
    sleep "$INTERVAL"
    continue
  fi

  if [ -n "$(git -C "$REPO" status --porcelain)" ]; then
    git -C "$REPO" add -A
    git -C "$REPO" commit -q -m "archive $(date -u +%FT%TZ)" >> "$LOG" 2>&1 \
      && log "committed changes" \
      || log "git commit failed"
  else
    log "no changes"
  fi

  sleep "$INTERVAL"
done
