#!/bin/zsh

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
sudo rsync -ivaAXSH --inplace --no-l -K --chmod=D700,F600 --exclude='**.cache' --exclude='.av_bazel_cache' /workspaces/home/vscode/.ssh ~/ # Needs exact permissions
sudo rsync -ivaAXSH --inplace --no-l -K --exclude='**.cache' --exclude='.av_bazel_cache' /workspaces/home/vscode/.gitconfig ~/

# Append old  /home/vscode/early_backup/.ssh/environment to the current .ssh/environment if it exists
# By 1. updating any vars that exist in both
#    and 2. appending any new vars from the old environment file
OLD_ENV="/home/vscode/early_backup/.ssh/environment"
NEW_ENV="$HOME/.ssh/environment"
if [ -f "$OLD_ENV" ]; then
  while IFS= read -r line; do
    key=$(echo "$line" | cut -d= -f1)
    val=$(echo "$line" | cut -d= -f2-)
    if grep -q "^$key=" "$NEW_ENV"; then
      # Update existing variable
      sed -i "s|^$key=.*|$key=$val|" "$NEW_ENV"
    else
      # Append new variable
      echo "$key=$val" >> "$NEW_ENV"
    fi
  done < "$OLD_ENV"
fi

# add source $HOME/.zshrc.local to the end of .zshrc if it's not already there
if ! grep -q "source \$HOME/.zshrc.local" ~/.zshrc; then
  echo "source \$HOME/.zshrc.local" >> ~/.zshrc
fi

# Load the Coder/SSH environment into the current script process, so tmuxs work right
if [ -f "$HOME/.ssh/environment" ]; then
    echo "Loading SSH environment for tmux..."
    # Export to current shell so 'tmux new-session' inherits them
    cp "$HOME/.ssh/environment" /tmp/ssh_environment_cleanup
    sed -i -E 's/^([^=]+=)([^"].*|)$/\1"\2"/' /tmp/ssh_environment_cleanup # quote all unquoted vars
    sed -i -E '/^[^=]*\.[^=]*=/d' /tmp/ssh_environment_cleanup # remove illegal vars containing dots
    sed -i -E '/^PATH=/d' /tmp/ssh_environment_cleanup    # Remove PATH edits
    set -a; source "/tmp/ssh_environment_cleanup"; set +a  #Can't call export directly on the file, so source it instead
    rm /tmp/ssh_environment_cleanup
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


# The above ssh stuff doesn't really work. Context says this is better:
SSHD_CONFIG="/etc/ssh/sshd_config"
sudo sed -i "/^ClientAliveInterval /c\ClientAliveInterval 86400" "$SSHD_CONFIG"
sudo sed -i "/^ClientAliveCountMax /c\ClientAliveCountMax 18" "$SSHD_CONFIG"
sudo sed -i "/^TCPKeepAlive /c\TCPKeepAlive no" "$SSHD_CONFIG"

# 2. Kill the Coder-spawned sshd (it runs as root)
# The Coder agent will not auto-restart it if you kill it manually.
sudo pkill -f "/usr/sbin/sshd -D"

# 3. Start your own "Eternal" sshd with the exact same parameters Coder expects, 
# plus your new timeout rules.
sudo nohup /usr/sbin/sshd -D \
  -o "AcceptEnv=TZ" \
  -o "PermitUserEnvironment=yes" \
  -o "ClientAliveInterval=86400" \
  -o "ClientAliveCountMax=18" \
  -o "TCPKeepAlive=no" \
  -E /var/log/sshd >/tmp/sshd_eternal.log 2>&1 &

echo "Eternal SSHD started."

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
