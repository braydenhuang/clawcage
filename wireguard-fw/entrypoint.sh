#!/bin/sh
set -e

# ============================================================
# 1. Resolve WireGuard keys from Docker secrets
# ============================================================
FW_PRIVATE_KEY_PATH="/run/secrets/fw_private_key"
OPENCLAW_PUBKEY_PATH="/run/secrets/openclaw_public_key"

for f in "$FW_PRIVATE_KEY_PATH" "$OPENCLAW_PUBKEY_PATH"; do
    if [ ! -f "$f" ]; then
        echo "[entrypoint] ERROR: required secret not found: $f"
        exit 1
    fi
done

mkdir -p /run/wireguard
chmod 700 /run/wireguard

sed \
    -e "s|REPLACE_FW_PRIVATE_KEY|$(cat $FW_PRIVATE_KEY_PATH)|" \
    -e "s|REPLACE_OPENCLAW_PUBKEY|$(cat $OPENCLAW_PUBKEY_PATH)|" \
    /etc/wireguard/wg0.conf > /run/wireguard/wg0.conf

chmod 600 /run/wireguard/wg0.conf

# ============================================================
# 2. Bring up WireGuard
# ============================================================
wg-quick up /run/wireguard/wg0.conf

# ============================================================
# 3. Bootstrap DNSSEC trust anchor
# ============================================================
unbound-anchor -a /var/lib/unbound/root.key || true

# ============================================================
# 4. Start Unbound
# ============================================================
unbound -c /etc/unbound/unbound.conf
sleep 1

# ============================================================
# 5. Load nftables ruleset
# ============================================================
nft -f /etc/nftables.conf

# ============================================================
# 6. Initial ingest of firewall allowlists
# ============================================================
/usr/local/bin/refresh.sh

# ============================================================
# 7. Schedule firewall allowlists refresh every 3 minutes
# ============================================================
(while true; do sleep 180; /usr/local/bin/refresh.sh; done) &

# ============================================================
# 8. Keep container alive
# ============================================================
wait