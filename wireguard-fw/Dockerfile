FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    wireguard-tools \
    nftables \
    unbound \
    unbound-anchor \
    dnsutils \
    iproute2 \
    procps \
    ca-certificates \
    # ------------------
    # Add these network utilities for debugging
    # (Note: Expect most to fail due to firewall rules)
    # iputils-ping \
    # curl \
    # wget \
    # ------------------
    && rm -rf /var/lib/apt/lists/*

COPY unbound.conf      /etc/unbound/unbound.conf
COPY nftables.conf     /etc/nftables.conf
COPY refresh.sh        /usr/local/bin/refresh.sh
COPY wg0.conf          /etc/wireguard/wg0.conf
COPY entrypoint.sh     /entrypoint.sh

RUN chmod +x /usr/local/bin/refresh.sh /entrypoint.sh && \
    chmod 600 /etc/wireguard/wg0.conf && \
    mkdir -p /run/wireguard && chmod 700 /run/wireguard

EXPOSE 51820/udp

ENTRYPOINT ["/entrypoint.sh"]