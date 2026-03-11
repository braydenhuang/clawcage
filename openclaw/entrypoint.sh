#!/bin/sh
set -e

# ============================================================
# 1. Resolve WireGuard keys from Docker secrets
# ============================================================
OPENCLAW_PRIVATE_KEY_PATH="/run/secrets/openclaw_private_key"
FW_PUBKEY_PATH="/run/secrets/fw_public_key"

for f in "$OPENCLAW_PRIVATE_KEY_PATH" "$FW_PUBKEY_PATH"; do
    if [ ! -f "$f" ]; then
        echo "[entrypoint] ERROR: required secret not found: $f"
        exit 1
    fi
done

mkdir -p /run/wireguard
chmod 700 /run/wireguard

sed \
    -e "s|REPLACE_PRIVATE_KEY|$(cat $OPENCLAW_PRIVATE_KEY_PATH)|" \
    -e "s|REPLACE_FW_PUBKEY|$(cat $FW_PUBKEY_PATH)|" \
    /etc/wireguard/wg0.conf > /run/wireguard/wg0.conf

chmod 600 /run/wireguard/wg0.conf

# ============================================================
# 2. Verify tunnel is up, harden container
# ============================================================
wg-quick up /run/wireguard/wg0.conf

# Delete any default route that does not use wg0
ip route | grep '^default' | grep -v 'dev wg0' | while read -r route; do
    ip route del $route || true
done

# Add default route through WireGuard tunnel
ip route add default dev wg0

echo "[entrypoint] Waiting for wg0..."
for i in $(seq 1 10); do
    ip link show wg0 > /dev/null 2>&1 && break
    sleep 1
done

ip link show wg0 > /dev/null 2>&1 || { echo "[entrypoint] ERROR: wg0 failed"; exit 1; }

echo "[entrypoint] Testing DNS via tunnel..."
dig +short +time=3 +tries=2 openclaw.ai @10.0.0.1 > /dev/null 2>&1 || \
    echo "[entrypoint] WARNING: DNS resolution failed"

# Ensure the app binary and any data dirs are owned correctly
# Must be done at entrypoint or else a restart on a volume would cause permission issues
chown -R openclaw:openclaw /home

# ============================================================
# 3. Start OpenClaw gateway, delete entrypoint script, exec as openclaw user
# ============================================================
rm -f /entrypoint.sh # Delete this script after startup to minimize information available to an attacker
echo "[entrypoint] Executing \"openclaw onboard\"..."
exec gosu openclaw openclaw gateway run --allow-unconfigured