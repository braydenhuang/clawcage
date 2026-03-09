# ClawCage
Secure, zero-trust sandbox and firewall for OpenClaw. Provides maximum isolation for OpenClaw instances running in sensitive network environments.

**Features:**
- Select specific `IP`:`Port`:`Protocol` pairings to allow for OpenClaw. ✅

- Select specific `Domain`:`Port`:`Protocol` pairings to allow. ✅

- Sandbox customized to minimize information leakage. ✅

- Firewall resolves all domains over TLS and with DNSSEC *(where applicable)* to avoid DNS attacks. ✅

- Firewall updates every 3 minutes with fresh resolutions ✅

- Old resolutions are purged upon each refresh. ✅

- Support for internal domains resolved using internal DNS servers ✅
    - Compatible with corporate networks, can be reconfigured for DNS-over-HTTPS.

#

![Main Logo](logo.jpg)

#

## Quick Start:

Run:
```bash
docker-compose up
```
*That's all it takes!*

Add allowed domains and IPs in `wireguard-fw/allowlist-domains.txt` and `wireguard-fw/allowlist-ips.txt`.
```makefile
# Example: allowlist-domains.txt

# Format: domain:port:protocol
# protocol must be one of {tcp, udp}
#
# Notes:
# The domain is first resolved by refresh.sh into an IP address, and the resulting IP:port:protocol is allowed

openclaw.ai:443:tcp
openclaw.ai:80:tcp
npmjs.com:443:tcp
npmjs.com:80:tcp
registry.npmjs.org:443:tcp
registry.npmjs.org:80:tcp
```

```makefile
# Example: allowlist-ips.txt

# Format: domain:port:protocol
# protocol must be one of {tcp, udp}

10.34.33.25:443:tcp
```

> **Note:** All unspecified endpoints are dropped by the firewall.

## Troubleshooting:

#### The firewall cannot resolve via DNS-over-TLS (DoT)
- This is common in corporate or restricted networks.
- Change to DNS-over-HTTPS (DoH) by making this edit in `wireguard-fw/nftables.conf`...
    ```bash
    # Old
    # Unbound DNS over TLS (DoT) upstream queries
    tcp dport 853 accept
    
    # New
    # Unbound DNS over HTTPS (DoH) upstream queries
    tcp dport 443 accept
    ```
    ... and by making this edit in `wireguard-fw/unbound.conf`.
    ```bash
    # Old
    # Cloudflare — primary
    forward-addr: 1.1.1.1@853#cloudflare-dns.com
    forward-addr: 1.0.0.1@853#cloudflare-dns.com

    # Google — fallback
    forward-addr: 8.8.8.8@853#dns.google
    forward-addr: 8.8.4.4@853#dns.google
    
    # New
    # Cloudflare — primary
    forward-addr: 1.1.1.1@443#cloudflare-dns.com
    forward-addr: 1.0.0.1@443#cloudflare-dns.com

    # Google — fallback
    forward-addr: 8.8.8.8@443#dns.google
    forward-addr: 8.8.4.4@443#dns.google
    ```    

## To-Do List:

- Add more protocols (ICMP)
- Preinstall OpenClaw in `./openclaw/Dockerfile`