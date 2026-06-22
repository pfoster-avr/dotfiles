#!/usr/bin/zsh

# Start the "perc_run3" tmux session and launch the vcut perception-recalculation resume script.
# resume_perc_vcut.sh builds + drives from the 30min_perc_recalc worktree (it hardcodes that path
# internally, so the pane CWD does not matter). It is idempotent/resumable: it recovers
# crash-completed items and skips already-done work, so a fresh launch after a wipe continues vcut
# where it left off. Logs to junk/pfoster/mylos_logs/ via tee.

tmux new-session -d -s perc_run3
sleep 2  # give tmux a moment to start the session before sending keys
tmux send-keys -t perc_run3 "cd /workspaces/av.worktrees/30min_perc_recalc && git switch --quiet 30min_perc_recalc; /workspaces/tmp/resume_perc_vcut.sh 1400 2>&1 | tee /workspaces/tmp/perc_inspect/vcut_PROD_\$(date +%Y%m%d_%H%M%S).log" C-m

# start model_dashboard
tmux new-session -d -s model_dashboard
sleep 2  # give tmux a moment to start the session before sending keys
tmux send-keys -t model_dashboard "cd /workspaces/av && /workspaces/tmp/launch_dashboard.sh" C-m

# Print PATH
echo "Current PATH: $PATH"

# Print whether /home/vscode/.nix-profile/bin/tmux exists
if [ -x "/home/vscode/.nix-profile/bin/tmux" ]; then
  echo "/home/vscode/.nix-profile/bin/tmux exists and is executable."
else
  echo "/home/vscode/.nix-profile/bin/tmux does not exist or is not executable."
fi

# Print which tmux is being used
which tmux