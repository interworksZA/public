#!/bin/bash

# Downloads and installs the Interworks public keys for the 'interworks' user.
# This script is intended to run as root from cron.

# Configuration
GITHUB_RAW_URL="https://raw.githubusercontent.com/interworksZA/public/main/keys/public_keys.txt"

USERNAME="interworks"
HOME_DIR=$(getent passwd "$USERNAME" | cut -d: -f6)

if [ -z "$HOME_DIR" ]; then
    logger -t update_authorized_keys "User '$USERNAME' does not exist."
    exit 1
fi

SSH_DIR="$HOME_DIR/.ssh"
AUTHORIZED_KEYS_FILE="$SSH_DIR/authorized_keys"

# Ensure ~/.ssh exists
mkdir -p "$SSH_DIR"
chown "$USERNAME:$USERNAME" "$SSH_DIR"
chmod 700 "$SSH_DIR"

# Backup existing authorized_keys if it exists
if [ -f "$AUTHORIZED_KEYS_FILE" ]; then
    BACKUP_FILE="${AUTHORIZED_KEYS_FILE}.bak.$(date +%F_%T)"
    cp "$AUTHORIZED_KEYS_FILE" "$BACKUP_FILE"
    logger -t update_authorized_keys "Backup created: $BACKUP_FILE"
fi

# Ensure authorized_keys exists
touch "$AUTHORIZED_KEYS_FILE"
chown "$USERNAME:$USERNAME" "$AUTHORIZED_KEYS_FILE"
chmod 600 "$AUTHORIZED_KEYS_FILE"

# Download the latest keys
TEMP_KEYS_FILE=$(mktemp)

if ! curl -fsS -o "$TEMP_KEYS_FILE" "$GITHUB_RAW_URL"; then
    logger -t update_authorized_keys "Failed to download keys from GitHub."
    rm -f "$TEMP_KEYS_FILE"
    exit 1
fi

# Remove old versions of users that exist in GitHub
while read -r line; do
    [ -z "$line" ] && continue

    COMMENT=$(echo "$line" | awk '{print $NF}')

    if grep -qF "$COMMENT" "$AUTHORIZED_KEYS_FILE"; then
        sed -i "\|$COMMENT|d" "$AUTHORIZED_KEYS_FILE"
        logger -t update_authorized_keys "Removed old key for user: $COMMENT"
    fi
done < "$TEMP_KEYS_FILE"

# Add latest keys
cat "$TEMP_KEYS_FILE" >> "$AUTHORIZED_KEYS_FILE"

# Remove duplicates
sort -u "$AUTHORIZED_KEYS_FILE" > "${AUTHORIZED_KEYS_FILE}.new"
mv "${AUTHORIZED_KEYS_FILE}.new" "$AUTHORIZED_KEYS_FILE"

# Final permissions
chown "$USERNAME:$USERNAME" "$AUTHORIZED_KEYS_FILE"
chmod 600 "$AUTHORIZED_KEYS_FILE"

logger -t update_authorized_keys "Updated $AUTHORIZED_KEYS_FILE with keys from GitHub."

# Cleanup
rm -f "$TEMP_KEYS_FILE"
logger -t update_authorized_keys "Temporary file removed."

# Self-update
SCRIPT_URL="https://raw.githubusercontent.com/interworksZA/public/main/keys/public_keys_installer_interworks.sh"
SCRIPT_PATH="/usr/local/bin/public_keys_installer_interworks.sh"

if curl -fsS -o "$SCRIPT_PATH" "$SCRIPT_URL"; then
    chmod +x "$SCRIPT_PATH"
    logger -t update_authorized_keys "Updated installer script."
else
    logger -t update_authorized_keys "Failed to update installer script."
fi
