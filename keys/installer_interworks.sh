#!/bin/bash

# This script performs the following:
# 1 - Downloads public_keys_installer_interworks.sh
# 2 - Installs it into /usr/local/bin
# 3 - Creates a weekly cron job to keep SSH keys up to date

SCRIPT_URL="https://raw.githubusercontent.com/interworksZA/public/main/keys/public_keys_installer_interworks.sh"
SCRIPT_PATH="/usr/local/bin/public_keys_installer_interworks.sh"
CRON_JOB="0 2 * * 1 $SCRIPT_PATH"

# Download the script
if ! curl -fsS -o "$SCRIPT_PATH" "$SCRIPT_URL"; then
    echo "Failed to download $SCRIPT_URL"
    exit 1
fi

# Set permissions
chmod +x "$SCRIPT_PATH"
echo "Downloaded and set executable permissions for $SCRIPT_PATH"

# Add cron if it doesn't already exist
if ! crontab -l 2>/dev/null | grep -qF "$CRON_JOB"; then
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo "Cron job added to run every Monday at 02:00"
else
    echo "Cron job already exists"
fi
