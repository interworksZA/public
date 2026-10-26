#!/bin/bash

# Interworks SSH Access Verification
#
# Read-only check of an Interworks SSH key installation. Makes no changes.
# Run as root:
#     curl -fsS https://raw.githubusercontent.com/interworksZA/public/main/keys/verify_interworks.sh | bash
#
# Exit code: 0 = no failures (warnings allowed)
#            1 = one or more failures
#            2 = not run as root

USERNAME="interworks"
UPDATER="/usr/local/bin/public_keys_installer_interworks.sh"
KEYS_URL="https://raw.githubusercontent.com/interworksZA/public/main/keys/public_keys.txt"
KEY_REGEX='^(ssh-rsa|ssh-ed25519|ssh-dss|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521) '

FAILS=0
WARNS=0

pass() { echo "[PASS] $1"; }
fail() { echo "[FAIL] $1"; FAILS=$((FAILS + 1)); }
warn() { echo "[WARN] $1"; WARNS=$((WARNS + 1)); }
info() { echo "[INFO] $1"; }

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This check must be run as root."
    exit 2
fi

echo "=== Interworks SSH access check: $(hostname) ==="
echo

# ------------------------------------------------------------
# User, group and password
# ------------------------------------------------------------

echo "-- User --"

USER_ENTRY=$(getent passwd "$USERNAME")

if [ -z "$USER_ENTRY" ]; then
    fail "User '$USERNAME' does not exist"
    echo
    echo "RESULT: cannot continue without the user. 1 FAILED"
    exit 1
fi

pass "User '$USERNAME' exists"

HOME_DIR=$(echo "$USER_ENTRY" | awk -F: '{print $6}')
SSH_DIR="$HOME_DIR/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"
EXPECT_OWNER="$USERNAME:$(id -gn "$USERNAME")"

ADMIN_GROUP=""
for g in sudo wheel; do
    if getent group "$g" >/dev/null 2>&1 && id -nG "$USERNAME" | tr ' ' '\n' | grep -qx "$g"; then
        ADMIN_GROUP="$g"
    fi
done

if [ -n "$ADMIN_GROUP" ]; then
    pass "Member of administrative group '$ADMIN_GROUP'"
else
    fail "Not a member of 'sudo' or 'wheel'"
fi

PW_STATUS=$(passwd -S "$USERNAME" 2>/dev/null | awk '{print $2}')
case "$PW_STATUS" in
    P|PS) pass "Password is set (sudo needs it)" ;;
    L|LK) warn "Password is locked - sudo will not work with a password" ;;
    NP)   warn "No password set - run: passwd $USERNAME (sudo needs it)" ;;
    *)    warn "Could not determine password status" ;;
esac

echo

# ------------------------------------------------------------
# SSH files and permissions
# ------------------------------------------------------------

echo "-- SSH files --"

check_path() {
    # $1 = path, $2 = expected mode, $3 = label
    if [ ! -e "$1" ]; then
        fail "$3 missing: $1"
        return
    fi

    mode=$(stat -c '%a' "$1")
    owner=$(stat -c '%U:%G' "$1")

    if [ "$mode" = "$2" ]; then
        pass "$3 mode is $mode"
    else
        fail "$3 mode is $mode, expected $2"
    fi

    if [ "$owner" = "$EXPECT_OWNER" ]; then
        pass "$3 owned by $owner"
    else
        fail "$3 owned by $owner, expected $EXPECT_OWNER"
    fi
}

if [ -d "$HOME_DIR" ]; then
    home_mode=$(stat -c '%a' "$HOME_DIR")
    if [ $(( 8#$home_mode & 8#022 )) -eq 0 ]; then
        pass "Home directory $HOME_DIR is not group/world-writable ($home_mode)"
    else
        fail "Home directory $HOME_DIR is group/world-writable ($home_mode) - sshd will ignore keys"
    fi
else
    fail "Home directory missing: $HOME_DIR"
fi

check_path "$SSH_DIR" 700 "$SSH_DIR"
check_path "$AUTH_KEYS" 600 "$AUTH_KEYS"

KEY_COUNT=$(grep -cE "$KEY_REGEX" "$AUTH_KEYS" 2>/dev/null)
KEY_COUNT=${KEY_COUNT:-0}

if [ "$KEY_COUNT" -gt 0 ]; then
    pass "authorized_keys holds $KEY_COUNT valid key(s)"
else
    fail "authorized_keys holds no valid keys"
fi

TMP_KEYS=$(mktemp)
if curl -fsS --max-time 30 -o "$TMP_KEYS" "$KEYS_URL" 2>/dev/null; then
    total=0
    missing=0
    while IFS= read -r line; do
        total=$((total + 1))
        grep -qxF "$line" "$AUTH_KEYS" 2>/dev/null || missing=$((missing + 1))
    done < <(grep -E "$KEY_REGEX" "$TMP_KEYS")

    if [ "$total" -eq 0 ]; then
        warn "GitHub key list contained no valid keys"
    elif [ "$missing" -eq 0 ]; then
        pass "All $total managed key(s) from GitHub are present"
    else
        fail "$missing of $total managed key(s) from GitHub are missing - run the updater"
    fi
else
    warn "Could not download $KEYS_URL - GitHub comparison skipped"
fi
rm -f "$TMP_KEYS"

echo

# ------------------------------------------------------------
# Updater script and cron
# ------------------------------------------------------------

echo "-- Updater and cron --"

if [ ! -f "$UPDATER" ]; then
    fail "Updater missing: $UPDATER"
else
    if [ -x "$UPDATER" ]; then
        pass "Updater is executable"
    else
        fail "Updater is not executable"
    fi

    up_owner=$(stat -c '%U' "$UPDATER")
    up_mode=$(stat -c '%a' "$UPDATER")

    if [ "$up_owner" = "root" ]; then
        pass "Updater is owned by root"
    else
        fail "Updater is owned by $up_owner, expected root"
    fi

    # Cron runs this as root, so it must not be writable by anyone else.
    if [ $(( 8#$up_mode & 8#022 )) -eq 0 ]; then
        pass "Updater is not group/world-writable ($up_mode)"
    else
        fail "Updater is group/world-writable ($up_mode) - root runs this from cron"
    fi
fi

if command -v crontab >/dev/null 2>&1; then
    pass "crontab command is present"
else
    fail "crontab command not found - cron is not installed"
fi

if command -v systemctl >/dev/null 2>&1; then
    CRON_SVC=""
    for svc in cron crond; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            CRON_SVC="$svc"
        fi
    done

    if [ -n "$CRON_SVC" ]; then
        pass "Cron service '$CRON_SVC' is running"
    else
        fail "Cron service is not running (checked cron and crond)"
    fi
else
    warn "systemctl not found - cannot verify the cron service"
fi

CRON_COUNT=$(crontab -l 2>/dev/null | grep -v '^[[:space:]]*#' | grep -cF "$UPDATER")
CRON_COUNT=${CRON_COUNT:-0}

if [ "$CRON_COUNT" -eq 1 ]; then
    pass "Root crontab has the updater entry"
elif [ "$CRON_COUNT" -eq 0 ]; then
    fail "Root crontab has NO updater entry - keys will never update"
else
    warn "Root crontab has $CRON_COUNT updater entries (expected 1)"
fi

echo

# ------------------------------------------------------------
# sudo
# ------------------------------------------------------------

echo "-- sudo --"

if command -v sudo >/dev/null 2>&1; then
    if sudo -l -U "$USERNAME" 2>/dev/null | grep -qE '\(ALL[^)]*\)[[:space:]]+(NOPASSWD:[[:space:]]*|PASSWD:[[:space:]]*)?ALL'; then
        pass "sudo grants '$USERNAME' full root rights"
    else
        fail "sudo does not grant '$USERNAME' full root rights"
    fi
else
    fail "sudo is not installed"
fi

echo

# ------------------------------------------------------------
# sshd
# ------------------------------------------------------------

echo "-- sshd --"

SSHD=$(command -v sshd || echo /usr/sbin/sshd)

if [ -x "$SSHD" ]; then
    SSHD_CFG=$("$SSHD" -T -C "user=$USERNAME,host=localhost,addr=127.0.0.1" 2>/dev/null)

    if [ -z "$SSHD_CFG" ]; then
        warn "Could not read the effective sshd configuration"
    else
        if echo "$SSHD_CFG" | grep -qi '^pubkeyauthentication yes'; then
            pass "sshd allows public key authentication"
        else
            fail "sshd does not allow public key authentication"
        fi

        if echo "$SSHD_CFG" | grep -i '^authorizedkeysfile' | grep -q '\.ssh/authorized_keys'; then
            pass "sshd reads .ssh/authorized_keys"
        else
            warn "sshd AuthorizedKeysFile does not include .ssh/authorized_keys"
        fi

        RESTRICT=$(echo "$SSHD_CFG" | grep -Ei '^(allowusers|allowgroups|denyusers|denygroups) ')
        if [ -n "$RESTRICT" ]; then
            warn "sshd has user/group restrictions - confirm '$USERNAME' is permitted:"
            echo "$RESTRICT" | sed 's/^/         /'
        else
            pass "No sshd user/group restrictions"
        fi

        info "sshd $(echo "$SSHD_CFG" | grep -i '^permitrootlogin ')"
    fi
else
    warn "sshd not found - SSH configuration not checked"
fi

echo

if [ "$FAILS" -eq 0 ]; then
    echo "RESULT: OK ($WARNS warning(s))"
    exit 0
else
    echo "RESULT: $FAILS FAILED, $WARNS warning(s)"
    exit 1
fi
