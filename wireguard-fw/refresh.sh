#!/bin/sh
# =============================================================================
# refresh.sh — Firewall allowlist refresh script
#
# Reads allowlist files for static IPs and domains, resolves domains via a
# local Unbound resolver, and loads the results into nftables sets separated
# by protocol (TCP / UDP).
#
# Allowlist file formats:
#   allowlist-ips.txt      →  ip:port:protocol      (e.g. 1.1.1.1:443:tcp)
#   allowlist-domains.txt  →  domain:port:protocol   (e.g. example.com:443:udp)
#
# Valid protocols: tcp, udp
#
# nftables sets managed:
#   inet filter allowed_tcp_endpoints   — ip . port pairs for TCP
#   inet filter allowed_udp_endpoints   — ip . port pairs for UDP
#   inet filter allowed_domain_ips      — bare IPs resolved from domains
#
# Idempotency: sets are flushed before loading, so repeated runs with the
# same input produce the same state with no duplicates or errors.
#
# Exit codes:
#   0  — all entries processed without error
#   1  — one or more errors occurred (details in log)
# =============================================================================

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
UNBOUND="127.0.0.1"
DOMAIN_ALLOWLIST="/etc/fw/allowlist-domains.txt"
IP_ALLOWLIST="/etc/fw/allowlist-ips.txt"
LOG_FILE="/var/log/fw-refresh.log"

# Temporary working files — cleaned up on exit via trap
TMP_IPS="/tmp/fw_ips_clean.$$.txt"
TMP_DOMAINS="/tmp/fw_domains_clean.$$.txt"

# Counters
TCP_COUNT=0
UDP_COUNT=0
DOMAIN_IP_COUNT=0
WARN_COUNT=0
ERR_COUNT=0

# ---------------------------------------------------------------------------
# Cleanup — remove temp files on exit, interrupt, or termination
# ---------------------------------------------------------------------------
cleanup() {
    rm -f "$TMP_IPS" "$TMP_DOMAINS"
}
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------
# Logging helpers
#
# All messages are written to both stdout and the log file with a consistent
# format:  [YYYY-MM-DD HH:MM:SS] [LEVEL] message
# ---------------------------------------------------------------------------
_log() {
    _level="$1"; shift
    _ts=$(date '+%Y-%m-%d %H:%M:%S')
    printf '[%s] [%-7s] %s\n' "$_ts" "$_level" "$*" | tee -a "$LOG_FILE"
}

log_info()    { _log "INFO"    "$@"; }
log_warn()    { _log "WARNING" "$@"; WARN_COUNT=$((WARN_COUNT + 1)); }
log_error()   { _log "ERROR"   "$@"; ERR_COUNT=$((ERR_COUNT + 1)); }

# ---------------------------------------------------------------------------
# strip_comments — emit non-blank, non-comment lines from a file
# ---------------------------------------------------------------------------
strip_comments() {
    grep -v '^\s*#' "$1" | grep -v '^\s*$'
}

# ---------------------------------------------------------------------------
# resolve — return A-record IPs for a domain via the local Unbound resolver
#
# Only lines that look like valid IPv4 addresses are kept (dig may return
# CNAMEs or other records).
# ---------------------------------------------------------------------------
resolve() {
    dig +short "$1" A @"$UNBOUND" \
        | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'
}

# ---------------------------------------------------------------------------
# is_valid_ipv4 — basic structural check for an IPv4 address
#
# Validates that the string is four dot-separated decimal octets (0-255).
# ---------------------------------------------------------------------------
is_valid_ipv4() {
    echo "$1" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || return 1

    # Check each octet is in 0–255
    IFS='.' read -r a b c d <<EOF
$1
EOF
    for octet in $a $b $c $d; do
        [ "$octet" -ge 0 ] 2>/dev/null && [ "$octet" -le 255 ] || return 1
    done
    return 0
}

# ---------------------------------------------------------------------------
# is_valid_port — check that port is a number in 1–65535
# ---------------------------------------------------------------------------
is_valid_port() {
    echo "$1" | grep -qE '^[0-9]+$' || return 1
    [ "$1" -ge 1 ] 2>/dev/null && [ "$1" -le 65535 ] || return 1
    return 0
}

# ---------------------------------------------------------------------------
# is_valid_protocol — accept "tcp" or "udp" (case-insensitive)
# ---------------------------------------------------------------------------
is_valid_protocol() {
    _proto=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    [ "$_proto" = "tcp" ] || [ "$_proto" = "udp" ]
}

# ---------------------------------------------------------------------------
# append_element — append "ip . port" to the correct protocol accumulator
#
# Usage: append_element <ip> <port> <protocol> <source_label>
#
# Globals modified: TCP_ELEMENTS, UDP_ELEMENTS, TCP_COUNT, UDP_COUNT
# ---------------------------------------------------------------------------
append_element() {
    _ip="$1" _port="$2" _proto="$3" _src="$4"
    _proto=$(echo "$_proto" | tr '[:upper:]' '[:lower:]')

    if [ "$_proto" = "tcp" ]; then
        TCP_ELEMENTS="$TCP_ELEMENTS $_ip . $_port,"
        TCP_COUNT=$((TCP_COUNT + 1))
        log_info "$_src: TCP $_ip:$_port"
    else
        UDP_ELEMENTS="$UDP_ELEMENTS $_ip . $_port,"
        UDP_COUNT=$((UDP_COUNT + 1))
        log_info "$_src: UDP $_ip:$_port"
    fi
}

# ---------------------------------------------------------------------------
# load_nft_set — flush and reload an nftables set
#
# Usage: load_nft_set <set_name> <elements_string> <label>
#
# The set is always flushed first (idempotency). If elements_string is
# non-empty the elements are added; otherwise an informational message is
# logged.
# ---------------------------------------------------------------------------
load_nft_set() {
    _set="$1" _elements="$2" _label="$3"

    nft flush set inet filter "$_set" || true

    if [ -n "$_elements" ]; then
        log_info "Loading $_label into $_set"
        if ! nft add element inet filter "$_set" "{ $_elements }"; then
            log_error "nft rejected $_label for set $_set"
        fi
    else
        log_info "No $_label to load into $_set"
    fi
}

# =============================================================================
# Main
# =============================================================================

# Ensure the log file exists and is writable
touch "$LOG_FILE" 2>/dev/null || {
    echo "FATAL: cannot write to $LOG_FILE" >&2
    exit 1
}

log_info "===== Firewall refresh started ====="

# ---- Accumulators for nft set elements ----
TCP_ELEMENTS=""
UDP_ELEMENTS=""
DOMAIN_IPS=""

# =========================================================================
# 1. Process allowlist-ips.txt  →  allowed_tcp_endpoints / allowed_udp_endpoints
# =========================================================================
if [ -f "$IP_ALLOWLIST" ]; then
    strip_comments "$IP_ALLOWLIST" > "$TMP_IPS"

    while IFS= read -r line; do
        ip=$(echo "$line"   | cut -d: -f1 | tr -d '[:space:]')
        port=$(echo "$line" | cut -d: -f2 | tr -d '[:space:]')
        proto=$(echo "$line"| cut -d: -f3 | tr -d '[:space:]')

        # --- Validate all three fields are present ---
        if [ -z "$ip" ] || [ -z "$port" ] || [ -z "$proto" ]; then
            log_warn "Malformed IP entry '$line' — expected ip:port:protocol, skipping"
            continue
        fi

        # --- Validate IP ---
        if ! is_valid_ipv4 "$ip"; then
            log_warn "Invalid IPv4 address '$ip' in entry '$line', skipping"
            continue
        fi

        # --- Validate port ---
        if ! is_valid_port "$port"; then
            log_warn "Invalid port '$port' in entry '$line', skipping"
            continue
        fi

        # --- Validate protocol ---
        if ! is_valid_protocol "$proto"; then
            log_warn "Invalid protocol '$proto' in entry '$line' — must be tcp or udp, skipping"
            continue
        fi

        append_element "$ip" "$port" "$proto" "IP-allowlist"

    done < "$TMP_IPS"
else
    log_warn "$IP_ALLOWLIST not found — skipping static IP entries"
fi

# =========================================================================
# 2. Process allowlist-domains.txt  →  resolve, then add to sets
# =========================================================================
if [ -f "$DOMAIN_ALLOWLIST" ]; then
    strip_comments "$DOMAIN_ALLOWLIST" > "$TMP_DOMAINS"

    while IFS= read -r line; do
        domain=$(echo "$line" | cut -d: -f1 | tr -d '[:space:]')
        port=$(echo "$line"   | cut -d: -f2 | tr -d '[:space:]')
        proto=$(echo "$line"  | cut -d: -f3 | tr -d '[:space:]')

        # --- Validate all three fields are present ---
        if [ -z "$domain" ] || [ -z "$port" ] || [ -z "$proto" ]; then
            log_warn "Malformed domain entry '$line' — expected domain:port:protocol, skipping"
            continue
        fi

        # --- Validate port ---
        if ! is_valid_port "$port"; then
            log_warn "Invalid port '$port' in entry '$line', skipping"
            continue
        fi

        # --- Validate protocol ---
        if ! is_valid_protocol "$proto"; then
            log_warn "Invalid protocol '$proto' in entry '$line' — must be tcp or udp, skipping"
            continue
        fi

        # --- Resolve domain to IPs ---
        IPS=$(resolve "$domain")
        if [ -z "$IPS" ]; then
            log_warn "No IPs resolved for domain '$domain' — skipping entry"
            continue
        fi

        log_info "Resolved $domain → $(echo "$IPS" | tr '\n' ' ')"

        for ip in $IPS; do
            # Accumulate bare IP for the domain-IP set
            DOMAIN_IPS="$DOMAIN_IPS $ip,"
            DOMAIN_IP_COUNT=$((DOMAIN_IP_COUNT + 1))

            # Add to the protocol-appropriate endpoint set
            append_element "$ip" "$port" "$proto" "Domain-allowlist ($domain)"
        done

    done < "$TMP_DOMAINS"
else
    log_warn "$DOMAIN_ALLOWLIST not found — skipping domain entries"
fi

# =========================================================================
# 3. Load accumulated elements into nftables sets
# =========================================================================

# Strip trailing commas
TCP_ELEMENTS="${TCP_ELEMENTS%,}"
UDP_ELEMENTS="${UDP_ELEMENTS%,}"
DOMAIN_IPS="${DOMAIN_IPS%,}"

load_nft_set "allowed_tcp_endpoints" "$TCP_ELEMENTS"  "TCP endpoints"
load_nft_set "allowed_udp_endpoints" "$UDP_ELEMENTS"  "UDP endpoints"
load_nft_set "allowed_domain_ips"    "$DOMAIN_IPS"    "domain IPs"

# =========================================================================
# 4. Summary
# =========================================================================
log_info "----- Refresh summary -----"
log_info "TCP endpoint entries added : $TCP_COUNT"
log_info "UDP endpoint entries added : $UDP_COUNT"
log_info "Domain IP entries added    : $DOMAIN_IP_COUNT"
log_info "Warnings encountered       : $WARN_COUNT"
log_info "Errors encountered         : $ERR_COUNT"

if [ "$ERR_COUNT" -gt 0 ]; then
    log_error "Completed with $ERR_COUNT error(s)"
    exit 1
fi

log_info "===== Firewall refresh completed successfully ====="
exit 0