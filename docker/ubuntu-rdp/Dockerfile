# syntax=docker/dockerfile:1.6
# Ubuntu 22.04 RDP Container — rdp-mega-toolkit v9
# XFCE4 desktop exposed over RDP via xrdp.
#
# Build:  docker build -t rdp-toolkit-ubuntu .
# Run:    docker run -d --name ubuntu-rdp -p 23389:3389 -e RDP_USER=ubuntu -e RDP_PASS=ubuntu rdp-toolkit-ubuntu
# Connect (host): xfreerdp /v:localhost:23389 /u:ubuntu /p:ubuntu

FROM ubuntu:22.04

LABEL org.opencontainers.image.title="rdp-toolkit-ubuntu" \
      org.opencontainers.image.description="Ubuntu 22.04 + XFCE4 + xRDP for the GitHub RDP Mega Toolkit" \
      org.opencontainers.image.source="https://github.com/usekarne/github-rdp-mega-toolkit" \
      org.opencontainers.image.version="9.0.0"

ENV DEBIAN_FRONTEND=noninteractive \
    RDP_USER=ubuntu \
    RDP_PASS=ubuntu \
    RDP_UID=1000 \
    RDP_GID=1000 \
    TZ=UTC \
    LANG=C.UTF-8

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        xfce4 \
        xfce4-terminal \
        xfce4-goodies \
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
    locale-gen en_US.UTF-8 C.UTF-8 && \
    update-locale LANG=C.UTF-8 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Make XFCE the default xRDP session.
RUN mkdir -p /etc/xrdp /var/log/xrdp /run/xrdp && \
    echo "xfce4-session" > /etc/skel/.xsession && \
    chmod +x /etc/skel/.xsession && \
    sed -i 's|^port=3389|port=3389|' /etc/xrdp/xrdp.ini

RUN mkdir -p /run/sshd && \
    ssh-keygen -A 2>/dev/null || true

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 3389 22

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD (ss -ltn | grep -q ':3389') || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["xrdp"]
