FROM debian:bookworm-slim

# ============================================================
# System dependencies
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    wireguard-tools \
    iproute2 \
    openresolv \
    dnsutils \
    procps \
    ca-certificates \
    # ------------------
    # Remove these network utilities for more hardwalling
    iputils-ping \
    curl \
    wget \
    # ------------------
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# WireGuard client config
# (keys are injected at runtime from Docker secrets by entrypoint.sh)
# ============================================================
COPY wg-client.conf /etc/wireguard/wg0.conf
RUN chmod 600 /etc/wireguard/wg0.conf && \
    mkdir -p /run/wireguard && chmod 700 /run/wireguard   # added

# ============================================================
# Install OpenClaw
# ============================================================
# TODO: Install openclaw from the Dockerfile

# ============================================================
# Entrypoint
# ============================================================
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]