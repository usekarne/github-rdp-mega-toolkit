# syntax=docker/dockerfile:1.6
# Kali Linux RDP Container — rdp-mega-toolkit v9
# Provides a full Kali Rolling desktop over RDP via xrdp + XFCE.
#
# Build:  docker build -t rdp-toolkit-kali .
# Run:    docker run -d --name kali-rdp -p 13389:3389 -e RDP_USER=kali -e RDP_PASS=kali rdp-toolkit-kali
# Connect (host): xfreerdp /v:localhost:13389 /u:kali /p:kali

FROM kalilinux/kali-rolling:latest

LABEL org.opencontainers.image.title="rdp-toolkit-kali" \
      org.opencontainers.image.description="Kali Rolling + XFCE + xRDP for the GitHub RDP Mega Toolkit" \
      org.opencontainers.image.source="https://github.com/usekarne/github-rdp-mega-toolkit" \
      org.opencontainers.image.version="9.0.0"

ENV DEBIAN_FRONTEND=noninteractive \
    RDP_USER=kali \
    RDP_PASS=kali \
    RDP_UID=1000 \
    RDP_GID=1000 \
    TZ=UTC \
    LANG=C.UTF-8

# Install XFCE desktop, xrdp, SSH, python, sudo, common Kali tooling headers.
# NOTE: kali-desktop-xfce pulls a large metapackage; pin core pieces if image size matters.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        kali-desktop-xfce \
        xrdp \
        python3 \
        python3-pip \
        python3-venv \
        openssh-server \
        sudo \
        dbus-x11 \
        x11-xserver-utils \
        curl \
        ca-certificates \
        tzdata \
        locales && \
    sed -i 's/^#\?en_US\.UTF-8/en_US.UTF-8/' /etc/locale.gen && \
    sed -i 's/^#\?C\.UTF-8/C.UTF-8/' /etc/locale.gen && \
    locale-gen && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Configure xrdp to launch XFCE for all users.
RUN mkdir -p /etc/xrdp /var/log/xrdp /run/xrdp && \
    echo "xfce4-session" > /etc/skel/.xsession && \
    chmod +x /etc/skel/.xsession && \
    sed -i 's|^port=3389|port=3389|' /etc/xrdp/xrdp.ini && \
    sed -i 's|^useport=.*|useport=true|' /etc/xrdp/sesman.ini 2>/dev/null || true

# Pre-create sshd runtime dirs so the entrypoint can start sshd cleanly.
RUN mkdir -p /run/sshd && \
    ssh-keygen -A 2>/dev/null || true

# Copy entrypoint (kept outside the image build to allow env-driven config).
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 3389 22

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD (ss -ltn | grep -q ':3389') || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["xrdp"]
