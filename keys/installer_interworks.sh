#!/bin/bash

# Interworks Linux User & SSH Key Installer
#
# This script:
# 1 - Creates the 'interworks' user if it does not exist
# 2 - Adds the user to the appropriate administrative group
# 3 - Downloads the Interworks public key updater
# 4 - Adds a weekly root cron job
# 5 - Runs the updater immediately
#
# The password for 'interworks' is NOT set by this script.
# After installation, set it with:
#     passwd interworks

set -e

USERNAME="interworks"

SCRIPT_URL="https://raw.githubusercontent.com/interworksZA/public/main/keys/public_keys_installer_interworks.sh"
SCRIPT_PATH="/usr/local/bin/public_keys_installer_interworks.sh"
CRON_JOB="0 2 * * 1 $SCRIPT_PATH"

# Must run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This installer must be run as root."
    exit 1
fi

echo "=== Interworks Linux User & SSH Key Installer ==="

# ------------------------------------------------------------
# Create interworks user if it does not already exist
# ------------------------------------------------------------

if id "$USERNAME" >/dev/null 2>&1; then
    echo "User '$USERNAME' already exists."
else
    echo "Creating user '$USERNAME'..."

    useradd -m -s /bin/bash "$USERNAME"

    echo "User '$USERNAME' created successfully."
fi

# ------------------------------------------------------------
# Determine administrative group
# ------------------------------------------------------------

if getent group sudo >/dev/null 2>&1; then
    ADMIN_GROUP="sudo"
elif getent group wheel >/dev/null 2>&1; then
    ADMIN_GROUP="wheel"
else
    echo "ERROR: Could not find a sudo or wheel administrative group."
    exit 1
fi

echo "Using administrative group: $ADMIN_GROUP"

# Add interworks to administrative group
usermod -aG "$ADMIN_GROUP" "$USERNAME"

echo "User '$USERNAME' added to '$ADMIN_GROUP'."

# ------------------------------------------------------------
# Download public key updater
# ------------------------------------------------------------

echo "Downloading Interworks public key updater..."

if ! curl -fsS -o "$SCRIPT_PATH" "$SCRIPT_URL"; then
    echo "ERROR: Failed to download:"
    echo "$SCRIPT_URL"
    exit 1
fi

chmod +x "$SCRIPT_PATH"

echo "Installed:"
echo "$SCRIPT_PATH"

# ------------------------------------------------------------
# Create root cron job
# ------------------------------------------------------------

if ! crontab -l 2>/dev/null | grep -qF "$CRON_JOB"; then
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo "Cron job added:"
    echo "$CRON_JOB"
else
    echo "Cron job already exists."
fi

# ------------------------------------------------------------
# Run updater immediately
# ------------------------------------------------------------

echo "Installing current Interworks public SSH keys..."

if ! "$SCRIPT_PATH"; then
    echo "ERROR: Initial SSH key installation failed."
    exit 1
fi

echo
echo "=== Installation complete ==="
echo
echo "User: $USERNAME"
echo "SSH keys: /home/$USERNAME/.ssh/authorized_keys"
echo "Cron: $CRON_JOB"
echo
echo "IMPORTANT:"
echo "Set the password for the '$USERNAME' user with:"
echo
echo "    passwd $USERNAME"
echo
echo "The user can then SSH using the installed Interworks"
echo "public key and use sudo to become root."
