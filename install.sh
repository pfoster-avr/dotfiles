#!/bin/zsh

# Personal dotfiles install script for Coder.
# Configure in Coder UI: workspace → Settings → Parameters → dotfiles URI
# Runs after corporate install.sh, before workspace is marked "Ready".

# PERSIST_SCRIPT="/workspaces/av/junk/pfoster/persist_home.sh"

# if [ -x "$PERSIST_SCRIPT" ]; then
#   echo "Starting home directory backup daemon..."
#   nohup "$PERSIST_SCRIPT" > /tmp/persist_home.log 2>&1 &
#   disown
#   echo "Backup daemon started (PID $!, log at /tmp/persist_home.log)"
# fi

# Install moreutils (provides `ts` for timestamping pipe output)
sudo apt update
sudo apt install -y moreutils

# move old configuration files to ~/early_backup before copying new ones!
mkdir -p ~/early_backup
mv ~/.tmux.conf ~/early_backup/
mv ~/.zshrc.local ~/early_backup/
mv ~/.aws ~/early_backup/
mv ~/.config ~/early_backup/
mv ~/.ssh ~/early_backup/
mv ~/.gitconfig ~/early_backup/

# Copy tmux conf, .zshrc.local, AWS, config, ssh, .gitconfig configuration to home directory early
sudo rsync -ivaAXSH --inplace --no-l -K --exclude='**.cache' --exclude='.av_bazel_cache' /workspaces/home/vscode/.tmux.conf ~/
sudo rsync -ivaAXSH --inplace --no-l -K --exclude='**.cache' --exclude='.av_bazel_cache' /workspaces/home/vscode/.zshrc.local ~/
sudo rsync -ivaAXSH --inplace --no-l -K --exclude='**.cache' --exclude='.av_bazel_cache' /workspaces/home/vscode/.aws ~/
sudo rsync -ivaAXSH --inplace --no-l -K --exclude='**.cache' --exclude='.av_bazel_cache' /workspaces/home/vscode/.config ~/
sudo rsync -ivaAXSH --inplace --no-l -K --exclude='**.cache' --exclude='.av_bazel_cache' /workspaces/home/vscode/.ssh ~/
sudo rsync -ivaAXSH --inplace --no-l -K --exclude='**.cache' --exclude='.av_bazel_cache' /workspaces/home/vscode/.gitconfig ~/

# add source $HOME/.zshrc.local to the end of .zshrc if it's not already there
if ! grep -q "source \$HOME/.zshrc.local" ~/.zshrc; then
  echo "source \$HOME/.zshrc.local" >> ~/.zshrc
fi

# Start the "perc_run3" tmux session and launch the resume script.
tmux new-session -d -s perc_run3
sleep 2  # give tmux a moment to start the session before sending keys
tmux send-keys -t perc_run3 "cd /workspaces/av.worktrees/background_mylos && git switch --quiet background_mylos && /workspaces/tmp/resume_perc.sh" C-m

# start model_dashboard
tmux new-session -d -s model_dashboard
sleep 2  # give tmux a moment to start the session before sending keys
tmux send-keys -t model_dashboard "cd /workspaces/av && /workspaces/tmp/launch_dashboard.sh" C-m

# Ensure SSH configuration is updated idempotently
SSHD_CONFIG="/etc/ssh/sshd_config"

# Replace or append configuration lines
sudo sed -i \
  -e "/^TCPKeepAlive /c\TCPKeepAlive no" \
  -e "/^ClientAliveInterval /c\ClientAliveInterval 86400" \
  -e "/^ClientAliveCountMax /c\ClientAliveCountMax 18" "$SSHD_CONFIG"

# Append lines if they were not replaced
if ! grep -q "^TCPKeepAlive no" "$SSHD_CONFIG"; then
  echo "TCPKeepAlive no" | sudo tee -a "$SSHD_CONFIG" > /dev/null
fi
if ! grep -q "^ClientAliveInterval 86400" "$SSHD_CONFIG"; then
  echo "ClientAliveInterval 86400" | sudo tee -a "$SSHD_CONFIG" > /dev/null
fi
if ! grep -q "^ClientAliveCountMax 18" "$SSHD_CONFIG"; then
  echo "ClientAliveCountMax 18" | sudo tee -a "$SSHD_CONFIG" > /dev/null
fi

# Restart SSH service
sudo service ssh restart
echo "SSH configuration updated and service restarted."

# Ensure sysctl configuration is updated idempotently
SYSCTL_CONFIG="/etc/sysctl.conf"

# Replace or append sysctl parameters
sudo sed -i \
  -e "/^net.ipv4.tcp_keepalive_time /c\net.ipv4.tcp_keepalive_time = 1200000" \
  -e "/^net.ipv4.tcp_keepalive_intvl /c\net.ipv4.tcp_keepalive_intvl = 7200" \
  -e "/^net.ipv4.tcp_keepalive_probes /c\net.ipv4.tcp_keepalive_probes = 240" "$SYSCTL_CONFIG"

# Append parameters if they were not replaced
if ! grep -q "^net.ipv4.tcp_keepalive_time = 1200000" "$SYSCTL_CONFIG"; then
  echo "net.ipv4.tcp_keepalive_time = 1200000" | sudo tee -a "$SYSCTL_CONFIG" > /dev/null
fi
if ! grep -q "^net.ipv4.tcp_keepalive_intvl = 7200" "$SYSCTL_CONFIG"; then
  echo "net.ipv4.tcp_keepalive_intvl = 7200" | sudo tee -a "$SYSCTL_CONFIG" > /dev/null
fi
if ! grep -q "^net.ipv4.tcp_keepalive_probes = 240" "$SYSCTL_CONFIG"; then
  echo "net.ipv4.tcp_keepalive_probes = 240" | sudo tee -a "$SYSCTL_CONFIG" > /dev/null
fi

# Apply sysctl changes
sudo sysctl -p
echo "Sysctl configuration updated and applied."

# Launch the backup daemon (if it exists and is executable)
DAEMON="/workspaces/dotfiles/persist_home.sh"
if [ -x "$DAEMON" ]; then
  echo "Starting home directory backup daemon..."
  nohup zsh "$DAEMON" > /tmp/persist_home.log 2>&1 &
  disown
  echo "Backup daemon started (PID $!, log at /tmp/persist_home.log)"
else
  echo "Backup daemon script not found or not executable at $DAEMON. Skipping daemon launch."
fi  
