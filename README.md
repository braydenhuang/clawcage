# ClawCage
Secure, zero-trust sandbox and firewall for OpenClaw. Provides maximum isolation for OpenClaw instances running in sensitive network environments.

**Features:**
- Select specific `IP`:`Port`:`Protocol` pairings to allow. ✅

- Select specific `Domain`:`Port`:`Protocol` pairings to allow. ✅

- Deny-first Firewall ✅

- Firewall resolves all domains over TLS and with DNSSEC *(where applicable)* to avoid DNS attacks. ✅

- Firewall updates every 3 minutes with fresh resolutions ✅

- Old resolutions are purged upon each refresh. ✅

- Sandbox hardened to isolate OpenClaw bots that go rouge ✅

- Support for internal domains resolved using internal DNS servers ✅
    - Compatible with corporate networks, can be reconfigured for DNS-over-HTTPS.

#

![Main Logo](logo.jpg)

#

## Quick Start:

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

Then Run:
```bash
docker-compose -f 'docker-compose.yml' up -d --build
```
The OpenClaw gateway will start, but might not be configured properly.

Afterwards, get a terminal in your `openclaw` container:
```bash
docker exec -it openclaw sh -c "exec gosu openclaw bash"
```

Then set up OpenClaw, while noting key differences with the [docker sandbox](https://docs.openclaw.ai/install/docker):
```bash
# In openclaw container

openclaw@openclaw:/$ openclaw onboard
```

> **Note:** 
> The gateway is started as the `openclaw` user with limited permissions. 
> However, you have root access through the shell.
> You should try all commands as the `openclaw` user, reserving `root` only for when permission issues arise. 

> **Warning:**
> `gosu` is used to drop permissions *(such as going from `root` to `openclaw` user)* when standard 
> means like `su` are unavailable due to `no-new-privileges:true` being set.
> 
> **You must specify `exec gosu` when using it at all times.**
>
> A [privilege escalation attack](https://nvd.nist.gov/vuln/detail/CVE-2016-2779) is possible with `gosu`
> unless the parent shell is replaced by it. `exec` allows `gosu` to be used safely.
>
> For more information, see: https://github.com/tianon/gosu/issues/37

## Tips:

#### Restarting OpenClaw
- The settings in `/home/openclaw/.openclaw` are saved as a volume, so you can restart OpenClaw by running:
    ```bash
    docker-compose -f 'docker-compose.yml' up -d --build 'openclaw'
    ```
    > **Note:** The `--build` must be included to copy `entrypoint.sh` into the container every startup, since it deletes itself for security purposes.

## Troubleshooting:

#### My OpenClaw browser doesn't work
- Setting up a headless browser in the Docker container requires more steps, but there are many methods available. See the [OpenClaw docs](https://docs.openclaw.ai/install/docker).

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