#!/bin/zsh

# Background daemon that periodically rsyncs $HOME to persistent storage.
# Only runs the sync if $HOME/RSYNC_SENTINEL exists.
# Timestamps are logged into RSYNC_SENTINEL so you can see it's working.
#
# FAIL-STOP DESIGN: any unexpected condition writes ERROR to the sentinel and
# to $STATUS, then the daemon exits. No mutation continues past a surprise.
# Known consequence: an interrupted run leaves BACKUP_NEXT behind, and the
# daemon refuses to start a new cycle until you inspect and remove it by hand.
#
# PROMPT BANNER: each cycle the daemon injects (idempotently, marker-guarded)
# a status check into ~/.zshrc.local — others own ~/.zshrc, and $HOME is
# wiped on every rebuild, so the hook must be re-planted from here. The status
# file lives on the persistent mount so it survives home wipes too.
#
# Restore with (trailing slash on source matters, else you get ~/vscode/;
# the ~ is expanded by YOUR shell before sudo runs, so it stays /home/vscode):
# sudo rsync -ivaAXSH --inplace --no-l -K --exclude='**.cache' --exclude='.av_bazel_cache' /workspaces/home/vscode/ ~/
# To see stuff you might want to delete before restoring:
# sudo rsync --delete -nivaAXSH --inplace --no-l -K --exclude='**.cache' --exclude='.av_bazel_cache' /workspaces/home/vscode/ ~/
#
# This script lives at /workspaces/dotfiles/persist_home.sh, and you can launch it as a daemon by:
# nohup zsh /workspaces/dotfiles/persist_home.sh >/dev/null 2>&1 & ; disown
#
# To check if this daemon is running, look for its process:
# pgrep -fl persist_home.sh


BACKUP_BASE="/workspaces/home"
BACKUP_DIR="$BACKUP_BASE/vscode"
BACKUP_NEXT="$BACKUP_BASE/vscode_next"
BACKUP_OLD="$BACKUP_BASE/vscode_old"
SENTINEL="$HOME/RSYNC_SENTINEL"
STATUS="$BACKUP_BASE/.backup_daemon_status"  # persistent: survives home wipes
ZSHRC_LOCAL="$HOME/.zshrc.local"
INTERVAL=3600  # 1 hour
set -o pipefail

note() {
  # Exit whole script immediately if $SENTINEL does not exist
  [ -e "$SENTINEL" ] || exit 0

  # Timestamped line into the sentinel log; syslog as a second channel in case
  # the sentinel write itself fails (full disk has eaten error notes before).
  echo "$(date -Iseconds) $*" >> "$SENTINEL" 2>/dev/null \
    || logger -t backup-daemon "$*" 2>/dev/null
}

die() {
  # Fail-stop: record the error everywhere we can, then freeze (exit).
  note "ERROR: $*"
  echo "ERROR $(date -Iseconds) $*" > "$STATUS" 2>/dev/null
  logger -t backup-daemon "ERROR: $*" 2>/dev/null
  exit 1
}

ensure_prompt_hook() {
  # Re-plant the status banner into ~/.zshrc.local after every home wipe.
  # Marker-guarded so it appends at most once, including when a restore
  # brings back a .zshrc.local that already contains it.
  grep -qs "BACKUP-DAEMON-STATUS-BEGIN" "$ZSHRC_LOCAL" && return 0
  cat >> "$ZSHRC_LOCAL" <<'EOF' || die "could not inject status check into $ZSHRC_LOCAL"
# ---- BACKUP-DAEMON-STATUS-BEGIN (auto-injected by backup_daemon.zsh) ----
backup_daemon_check() {
  local f="/workspaces/home/.backup_daemon_status"
  local interval=3600   # keep in sync with INTERVAL in backup_daemon.zsh
  local state ts rest age
  if [[ ! -r $f ]]; then
    print -P "%F{red}%B!!! BACKUP DAEMON: no status file -- daemon never ran, or mount missing !!!%b%f"
    return
  fi
  read -r state ts rest < "$f"
  age=$(( $(date +%s) - $(stat -c %Y "$f") ))
  if [[ $state == ERROR ]]; then
    print -P "%F{red}%B!!! BACKUP DAEMON FROZEN since $ts: $rest !!!%b%f"
  elif (( age > 2 * interval + 300 )); then
    print -P "%F{red}%B!!! BACKUP DAEMON SILENT for $(( age / 60 )) min (last: $state $ts) !!!%b%f"
  elif [[ $state == DISARMED ]]; then
    print -P "%F{yellow}backup daemon: disarmed (no RSYNC_SENTINEL -- wiped home? restore & re-arm) as of $ts%f"
  else
    print -P "%F{244}backup: $state $ts%f"
  fi
}
backup_daemon_check
# ---- BACKUP-DAEMON-STATUS-END ----
EOF
  note "Injected status check into $ZSHRC_LOCAL"
}

backup_rsync() {
  # rsync wrapper that tolerates exactly one exit code: 24, "some files
  # vanished during transfer" -- routine when backing up a live $HOME.
  # Everything else (including 23) is a real failure and propagates.
  sudo rsync "$@"
  local rc=$?
  if [ $rc -eq 24 ]; then
    note "WARNING: rsync rc=24 (source files vanished mid-transfer); tolerated"
    return 0
  fi
  return $rc
}

run_backup() {
  # ---- sanity checks BEFORE touching anything ----
  [ -e "$BACKUP_NEXT" ] && die "BACKUP_NEXT already exists (interrupted prior run?). Inspect and remove $BACKUP_NEXT manually, then restart."
  if [ ! -e "$BACKUP_DIR" ]; then
    [ -e "$BACKUP_OLD" ] && die "BACKUP_OLD exists without BACKUP_DIR -- suspicious. Sort out $BACKUP_BASE manually, then restart."
    note "No BACKUP_DIR and no BACKUP_OLD: assuming first run."
  fi

  echo "RUNNING $(date -Iseconds) backup in progress" > "$STATUS"
  note "Starting rsync..."

  local excludes
  excludes=$(mktemp) || die "mktemp failed"

  # Build the exclude list of circular symlink loops by parsing find's loop
  # errors. `sudo` so find sees everything rsync (also sudo) will see.
  # LC_ALL is pinned because the quote characters in the message are
  # locale-dependent: C gives 'x', C.UTF-8 gives the curly quotes awk expects.
  # `grep` exits 1 when there are no loops, which is the normal case -- so
  # tolerate it (|| true) and keep this OUT of any `if` condition. Otherwise
  # `set -o pipefail` turns "no loops" into a fake failure. find also exits
  # nonzero whenever it reports a loop, hence the `; true` inside the braces.
  ( cd "$HOME/" && { sudo env LC_ALL=C.UTF-8 find -L . \( -name ".cache" -o -name ".av_bazel_cache" \) -prune -type l 2>&1 >/dev/null ; true; } \
      | grep "loop" | awk -F'‘|’' '{print $2}' | sed 's|^\./||' ) > "$excludes" || true

  # Also exclude dangling symlinks: the -L pass errors on them ("symlink has
  # no referent", rc=23), and blanket-accepting 23 would mask real failures
  # like permission-denied. -xtype l matches only broken links (no -L needed).
  # This find should NOT error (it runs as root); if it does, that's real.
  ( cd "$HOME/" && sudo find . \( -name ".cache" -o -name ".av_bazel_cache" \) -prune -o -xtype l -print \
      | sed 's|^\./||' ) >> "$excludes" || die "dangling-symlink scan failed"

  # Pass 1: structure + deletions, symlinks as symlinks.
  # Pass 2: materialize symlink referents so everything reachable from $HOME
  # is physically in the backup, even if it lives outside $HOME.
  # This two-pass chain is battle-tested against this home's hazards
  # (hardlinks, cyclic symlink dirs, mounted cache fs, admin-made
  # dir->symlink swaps); do not "simplify" it without re-running those tests.
  backup_rsync -aAXSH --delete \
      --exclude='**.cache' --exclude='.av_bazel_cache' --exclude='.nix-defexpr/channels_root' \
      --exclude-from="$excludes" \
      "$HOME/" "$BACKUP_NEXT/" || die "rsync pass 1 (structure+delete) failed with rc=$?"

  backup_rsync -aAXSH -L \
      --exclude='**.cache' --exclude='.av_bazel_cache' --exclude='.nix-defexpr/channels_root' \
      --exclude-from="$excludes" \
      "$HOME/" "$BACKUP_NEXT/" || die "rsync pass 2 (materialize symlinks) failed with rc=$?"

  rm -f "$excludes"

  # ---- rotation: every step checked, freeze on any failure ----
  note "Rsync succeeded, rotating backup..."
  if [ -e "$BACKUP_OLD" ]; then
    # sudo because the backup contains root-owned files; an unchecked,
    # half-failed rm here is what previously made `mv DIR OLD` nest.
    sudo rm -rf "$BACKUP_OLD" || die "could not delete stale BACKUP_OLD"
    [ -e "$BACKUP_OLD" ] && die "BACKUP_OLD still present after rm -rf"
  fi
  if [ -e "$BACKUP_DIR" ]; then
    # mv -T = --no-target-directory: refuses to nest into an existing
    # non-empty directory and errors instead, so the old wedge can't recur.
    mv -T "$BACKUP_DIR" "$BACKUP_OLD" || die "demote BACKUP_DIR -> BACKUP_OLD failed"
  fi
  mv -T "$BACKUP_NEXT" "$BACKUP_DIR" \
      || die "promote BACKUP_NEXT -> BACKUP_DIR failed; complete backups exist at BACKUP_NEXT and BACKUP_OLD"
  sudo rm -rf "$BACKUP_OLD" || die "could not delete BACKUP_OLD after rotation"

  # Completion marker inside the backup: also marks which copy was restored
  # when the sentinel is copied back to re-arm.
  echo "$(date -Iseconds) This backup is complete." >> "$BACKUP_DIR/RSYNC_SENTINEL" \
      || die "could not write completion marker into backup"
  note "Backup complete."
  echo "OK $(date -Iseconds) backup completed" > "$STATUS" \
      || note "WARNING: could not write status file"
}

# ---- single instance, fail noisy ----
# flock takes a kernel advisory lock on fd 9; it dies with the process, so no
# stale-pidfile problem. A second copy of the daemon fails immediately.
command -v flock >/dev/null || die "flock not installed"
exec 9>>"$BACKUP_BASE/.daemon.lock" || die "cannot open lock file in $BACKUP_BASE"
flock -n 9 || die "another daemon instance is already running at: $(pgrep -fl persist_home.sh | grep -v $$)"

while true; do
  ensure_prompt_hook   # re-plant banner into freshly-wiped homes every cycle
  if [ -f "$SENTINEL" ]; then
    run_backup
  else
    echo "DISARMED $(date -Iseconds) no $SENTINEL; backups paused" > "$STATUS"
  fi
  sleep "$INTERVAL"
done