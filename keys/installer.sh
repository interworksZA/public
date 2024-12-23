#!/bin/bash

# This script downloads & installs the keys in public_keys.txt
# It also schedules a cron to update these keys once a week.
# To simplify installing this script, you can instead copy/paste the 'one-liner'
# command in installer_one_liner.txt.

# Configuration
SCRIPT_URL="https://raw.githubusercontent.com/interworksZA/public/main/keys/public_keys.sh"
SCRIPT_PATH="/usr/local/bin/public_keys.sh"
CRON_JOB="0 2 * * 1 $SCRIPT_PATH"

# Download the script
curl -s -o "$SCRIPT_PATH" "$SCRIPT_URL"
if [ $? -ne 0 ]; then
    echo "Failed to download $SCRIPT_URL"
    exit 1
fi

# Set permissions
chmod +x "$SCRIPT_PATH"
echo "Downloaded and set executable permissions for $SCRIPT_PATH"

# Add to cron if not already present
if ! crontab -l | grep -qF "$CRON_JOB"; then
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo "Cron job added to run $SCRIPT_PATH every Monday at 02:00"
else
    echo "Cron job already exists"
fi
