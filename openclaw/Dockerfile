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
    iputils-ping \
    curl \
    wget \
    gosu \
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
RUN curl -fsSL --proto '=https' --tlsv1.3 https://openclaw.ai/install.sh | bash -s -- --no-onboard

# ============================================================
# Hardening
# ============================================================
# Mask the kernel string for extra security
# This might break kernel module tools (modprobe, depmod insmod, etc.)
# and build tools like dkms. Remove this portion if it's causing issues.
RUN printf '#!/bin/sh\n \
case "$1" in\n\
  -r) echo "6.1.0-bookworm-amd64" ;;\n \
  *)  exec /bin/uname "$@" ;;\n \
esac\n' > /usr/local/bin/uname \
    && chmod +x /usr/local/bin/uname

# Add a non-root user to run the OpenClaw gateway
RUN groupadd -r openclaw && useradd -r -g openclaw -s /bin/false openclaw


# ============================================================
# Entrypoint
# ============================================================
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]