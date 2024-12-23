#!/bin/bash

# Below script will download and install the Interworks public keys from the public_keys.txt file.

# Configuration
GITHUB_RAW_URL="https://raw.githubusercontent.com/interworksZA/public/main/keys/public_keys.txt"
AUTHORIZED_KEYS_FILE="/root/.ssh/authorized_keys"

# Create a backup of the current authorized_keys file
BACKUP_FILE="${AUTHORIZED_KEYS_FILE}.bak.$(date +%F_%T)"
cp "$AUTHORIZED_KEYS_FILE" "$BACKUP_FILE"
logger -t update_authorized_keys "Backup created: $BACKUP_FILE"

# Download the public keys file from GitHub
TEMP_KEYS_FILE=$(mktemp)
curl -s -o "$TEMP_KEYS_FILE" "$GITHUB_RAW_URL"

if [ $? -ne 0 ]; then
    logger -t update_authorized_keys "Failed to download keys from GitHub."
    exit 1
fi

# Ensure the authorized_keys file exists
touch "$AUTHORIZED_KEYS_FILE"

# Remove existing keys for the same users in the GitHub file
while read -r line; do
    # Extract comment part of the key (assuming it's after the key material)
    COMMENT=$(echo "$line" | awk '{print $NF}')
    if grep -q "$COMMENT" "$AUTHORIZED_KEYS_FILE"; then
        # Remove the matching line(s) for this comment
        sed -i "/$COMMENT/d" "$AUTHORIZED_KEYS_FILE"
        logger -t update_authorized_keys "Removed old key for user: $COMMENT"
    fi
done < "$TEMP_KEYS_FILE"

# Append new keys to the authorized_keys file
cat "$TEMP_KEYS_FILE" >> "$AUTHORIZED_KEYS_FILE"

# Deduplicate and sort keys
sort -u "$AUTHORIZED_KEYS_FILE" > "${AUTHORIZED_KEYS_FILE}.new"
mv "${AUTHORIZED_KEYS_FILE}.new" "$AUTHORIZED_KEYS_FILE"
chmod 600 "$AUTHORIZED_KEYS_FILE"
logger -t update_authorized_keys "Updated $AUTHORIZED_KEYS_FILE with keys from GitHub."

# Clean up
rm -f "$TEMP_KEYS_FILE"
logger -t update_authorized_keys "Temporary file $TEMP_KEYS_FILE removed."
