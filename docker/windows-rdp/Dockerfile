# syntax=docker/dockerfile:1.6
# "Windows RDP" container — rdp-mega-toolkit v9
# -----------------------------------------------------------------------------
# LICENSING: a real Microsoft Windows desktop image CANNOT be legally
# redistributed as a generic Docker container (Microsoft EULA only permits
# Windows container images on licensed Windows hosts using the official base
# images). This image therefore ships a Wine-based Windows *compatibility*
# layer on Ubuntu 22.04 + Fluxbox + xRDP, so users get a Linux desktop that
# runs many Windows .exe tools (notepad, winetricks apps, …) without
# shipping Microsoft binaries. To run a real Windows desktop, build your
# own image from mcr.microsoft.com/windows on a licensed host — the toolkit's
# entrypoint contract (xRDP on 3389) stays identical.
#
# Build:  docker build -t rdp-toolkit-windows .
# Run:    docker run -d --name windows-rdp -p 33389:3389 -e RDP_USER=win -e RDP_PASS=win rdp-toolkit-windows
# Connect (host): xfreerdp /v:localhost:33389 /u:win /p:win

FROM ubuntu:22.04

LABEL org.opencontainers.image.title="rdp-toolkit-windows" \
      org.opencontainers.image.description="Ubuntu 22.04 + Wine64 + Fluxbox + xRDP (Windows-compat desktop)" \
      org.opencontainers.image.source="https://github.com/usekarne/github-rdp-mega-toolkit" \
      org.opencontainers.image.version="9.0.0"

ENV DEBIAN_FRONTEND=noninteractive \
    RDP_USER=win \
    RDP_PASS=win \
    RDP_UID=1000 \
    RDP_GID=1000 \
    WINEPREFIX="/home/win/.wine" \
    WINEDEBUG=-all \
    TZ=UTC \
    LANG=C.UTF-8

# Wine needs i386 for many 32-bit Windows apps; enable multiarch.
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        wine64 \
        wine32 \
        winetricks \
        fluxbox \
        xrdp \
        python3 \
        python3-pip \
        python3-venv \
        openssh-server \
        sudo \
        dbus-x11 \
        x11-xserver-utils \
        xterm \
        curl \
        ca-certificates \
        tzdata \
        locales && \
    locale-gen en_US.UTF-8 C.UTF-8 && \
    update-locale LANG=C.UTF-8 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Configure xRDP to launch Fluxbox (lightweight WM, great for Wine).
RUN mkdir -p /etc/xrdp /var/log/xrdp /run/xrdp && \
    echo "exec fluxbox" > /etc/skel/.xsession && \
    chmod +x /etc/skel/.xsession

RUN mkdir -p /run/sshd && \
    ssh-keygen -A 2>/dev/null || true

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 3389 22

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD (ss -ltn | grep -q ':3389') || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["xrdp"]
