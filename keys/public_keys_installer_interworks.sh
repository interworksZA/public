#!/bin/bash

# Downloads and installs the Interworks public keys for the 'interworks' user.
# This script is intended to run as root from cron.

# Configuration
GITHUB_RAW_URL="https://raw.githubusercontent.com/interworksZA/public/main/keys/public_keys.txt"

USERNAME="interworks"

USER_ENTRY=$(getent passwd "$USERNAME")

if [ -z "$USER_ENTRY" ]; then
    logger -t update_authorized_keys "User '$USERNAME' does not exist."
    exit 1
fi

HOME_DIR=$(echo "$USER_ENTRY" | awk -F: '{print $6}')

if [ ! -d "$HOME_DIR" ]; then
    logger -t update_authorized_keys "Home directory '$HOME_DIR' does not exist."
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

# Recognized SSH public key types
KEY_TYPE_REGEX='^(ssh-rsa|ssh-ed25519|ssh-dss|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521)$'
BASE64_REGEX='^[A-Za-z0-9+/]+=*$'

VALID_KEYS_FILE=$(mktemp)

# Validate each line: must have a known key type, plausible base64 blob, and a comment
while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue

    KEY_TYPE=$(echo "$line" | awk '{print $1}')
    KEY_BLOB=$(echo "$line" | awk '{print $2}')
    NUM_FIELDS=$(echo "$line" | awk '{print NF}')

    if [ "$NUM_FIELDS" -lt 3 ]; then
        logger -t update_authorized_keys "Skipping malformed line (missing comment): $line"
        continue
    fi

    if ! echo "$KEY_TYPE" | grep -qE "$KEY_TYPE_REGEX"; then
        logger -t update_authorized_keys "Skipping line with unrecognized key type: $KEY_TYPE"
        continue
    fi

    if ! echo "$KEY_BLOB" | grep -qE "$BASE64_REGEX"; then
        logger -t update_authorized_keys "Skipping line with invalid key data for type: $KEY_TYPE"
        continue
    fi

    echo "$line" >> "$VALID_KEYS_FILE"
done < "$TEMP_KEYS_FILE"

# Remove old versions of users that exist in the validated key set
# Match is done on the exact last field (comment), not a substring/regex match,
# to avoid unsafe pattern injection and accidental partial matches.
while IFS= read -r line; do
    [ -z "$line" ] && continue

    COMMENT=$(echo "$line" | awk '{print $NF}')

    if awk -v c="$COMMENT" '$NF == c { found=1 } END { exit !found }' "$AUTHORIZED_KEYS_FILE"; then
        awk -v c="$COMMENT" '$NF != c' "$AUTHORIZED_KEYS_FILE" > "${AUTHORIZED_KEYS_FILE}.tmp"
        mv "${AUTHORIZED_KEYS_FILE}.tmp" "$AUTHORIZED_KEYS_FILE"
        logger -t update_authorized_keys "Removed old key for user: $COMMENT"
    fi
done < "$VALID_KEYS_FILE"

# Add latest validated keys
cat "$VALID_KEYS_FILE" >> "$AUTHORIZED_KEYS_FILE"

# Remove duplicates
sort -u "$AUTHORIZED_KEYS_FILE" > "${AUTHORIZED_KEYS_FILE}.new"
mv "${AUTHORIZED_KEYS_FILE}.new" "$AUTHORIZED_KEYS_FILE"

# Final permissions
chown "$USERNAME:$USERNAME" "$AUTHORIZED_KEYS_FILE"
chmod 600 "$AUTHORIZED_KEYS_FILE"

logger -t update_authorized_keys "Updated $AUTHORIZED_KEYS_FILE with keys from GitHub."

# Cleanup
rm -f "$TEMP_KEYS_FILE" "$VALID_KEYS_FILE"
logger -t update_authorized_keys "Temporary files removed."

# Self-update
SCRIPT_URL="https://raw.githubusercontent.com/interworksZA/public/main/keys/public_keys_installer_interworks.sh"
SCRIPT_PATH="/usr/local/bin/public_keys_installer_interworks.sh"

if curl -fsS -o "$SCRIPT_PATH" "$SCRIPT_URL"; then
    chmod +x "$SCRIPT_PATH"
    logger -t update_authorized_keys "Updated installer script."
else
    logger -t update_authorized_keys "Failed to update installer script."
fi
