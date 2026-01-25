#!/bin/bash
# One-time setup for OpenStack runner VM
# Usage: curl -sL https://raw.githubusercontent.com/mdsumner/gdalcheck/main/scripts/setup_runner.sh | bash

set -euo pipefail

REPO="${REPO:-mdsumner/gdalcheck}"
WORKDIR="${WORKDIR:-$HOME/gdalcheck-runner}"

echo "=== gdalcheck runner setup ==="
echo "Repo: $REPO"
echo "Workdir: $WORKDIR"

# Install dependencies
echo "Installing dependencies..."
sudo apt-get update
sudo apt-get install -y \
  docker.io \
  r-base-core \
  jq \
  parallel \
  git \
  curl

# Add user to docker group
sudo usermod -aG docker "$USER"

# Install R packages
echo "Installing R packages..."
sudo Rscript -e "install.packages('jsonlite', repos='https://cloud.r-project.org')"

# Create workspace
echo "Creating workspace..."
mkdir -p "$WORKDIR"/{logs,results,repo}

# Clone repo
echo "Cloning repo..."
git clone "https://github.com/${REPO}.git" "$WORKDIR/repo" || true

# Copy runner script
cp "$WORKDIR/repo/scripts/poll_and_run.sh" "$WORKDIR/"
chmod +x "$WORKDIR/poll_and_run.sh"

# Set up Git credentials (user will need to configure)
cat << 'EOF'

=== Setup Complete ===

Next steps:

1. Configure Git credentials for pushing results:
   
   # Option A: Personal Access Token (recommended for servers)
   git config --global credential.helper store
   echo "https://<username>:<token>@github.com" > ~/.git-credentials
   
   # Option B: SSH key
   ssh-keygen -t ed25519 -C "gdalcheck-runner"
   # Add public key to GitHub

2. Login to GHCR:
   
   echo $GITHUB_TOKEN | docker login ghcr.io -u <username> --password-stdin

3. Test the runner:
   
   cd ~/gdalcheck-runner
   ./poll_and_run.sh

4. Set up cron:
   
   crontab -e
   # Add: */15 * * * * /home/$USER/gdalcheck-runner/poll_and_run.sh >> /home/$USER/gdalcheck-runner/logs/cron.log 2>&1

5. (Optional) Adjust parallelism:
   
   export PARALLEL_JOBS=8  # or edit poll_and_run.sh

EOF

echo "Done! Log out and back in for docker group to take effect."
