#!/bin/bash

# Exit if any command fails
set -e

# Get the directory of this script
deploy_dir="$(cd "$(dirname "$0")" && pwd)"

# Set the working directory to that of this script
cd $deploy_dir

# Source the get-deploy-config script to read the configuration values
. ./get-deploy-config.sh

# Go to the main project directory
cd "$deploy_dir/.."

# Check if there are uncommitted changes
if [ -n "$(git status --porcelain)" ]; then
  echo "Error: There are uncommitted changes. Please commit or stash your changes before deploying."
  exit 1
fi

# Check if there are any unpushed commits
if [ -n "$(git log origin/$(git rev-parse --abbrev-ref HEAD)..HEAD)" ]; then
  echo "Error: There are unpushed commits. Please push your changes before deploying."
  exit 1
fi

# Perform the deployment using the host value
echo "Deploying branch '$(git rev-parse --abbrev-ref HEAD)' to $host..."

# Build the Golang binary
./build.sh app linux/amd64

# Copy built app to server
scp $ssh_key_flag ./app "$host:~"

# Remove the local binary
rm ./app

# Move back into this directory
cd $deploy_dir

# Copy config files to server
scp $ssh_key_flag ./Caddyfile "$host:~"
scp $ssh_key_flag ./caddy.service "$host:~"
scp $ssh_key_flag ./app.service "$host:~"

# Ensure app directory exists on the host
ssh $ssh_key_flag "$host" "sudo mkdir -p /opt/app"

# Move the scp'd files to their correct locations without overwriting the
# running app yet
ssh $ssh_key_flag "$host" "sudo mv ./Caddyfile /etc/caddy/Caddyfile"
ssh $ssh_key_flag "$host" "sudo mv ./caddy.service /etc/systemd/system/caddy.service"
ssh $ssh_key_flag "$host" "sudo mv ./app.service /etc/systemd/system/app.service"
ssh $ssh_key_flag "$host" "sudo mv ./app /opt/app/app.new"

# Set ownership
ssh $ssh_key_flag "$host" "sudo chown caddy:caddy /etc/caddy/Caddyfile"
ssh $ssh_key_flag "$host" "sudo chown -R app:app /opt/app"
                  
# Rename the binaries on the host
if ssh $ssh_key_flag "$host" "sudo [ -f /opt/app/app ]"; then
  ssh $ssh_key_flag "$host" "sudo mv /opt/app/app /opt/app/app.old"
fi
ssh $ssh_key_flag "$host" "sudo mv /opt/app/app.new /opt/app/app"

# Enable the services
ssh $ssh_key_flag "$host" "sudo systemctl daemon-reload"
ssh $ssh_key_flag "$host" "sudo systemctl enable app"
ssh $ssh_key_flag "$host" "sudo systemctl enable caddy"

# Restart the services
ssh $ssh_key_flag "$host" "sudo service app restart"
ssh $ssh_key_flag "$host" "sudo service caddy restart"

# Remove the old binary on the host if it exists
if ssh $ssh_key_flag "$host" "sudo [ -f /opt/app/app.old ]"; then
  ssh $ssh_key_flag "$host" "sudo rm /opt/app/app.old"
fi

echo "Deployment completed successfully."
