# syntax=docker/dockerfile:1
###############################################################################
# xfcevdi - XFCE Virtual Desktop (X2Go) + MetaTrader 5 on Debian
#
# Software stack: Debian 12 (bookworm) + XFCE 4.18 + X2Go 4.1 + Wine stable
# (WineHQ) + MetaTrader 5.
#
# Layering contract (important for MT5, which is upgraded very frequently):
#   1..N  OS / desktop / dev toolchain (rarely change)
#   N+1   Wine + MT5 helper tooling (rarely change)
#   LAST  MetaTrader 5 itself - the only layer that re-fetches the MT5
#         web-installer, so a rebuild always yields the newest MT5 build while
#         every lower layer stays cached. The install/upgrade logic lives in
#         /usr/local/bin/mt5-install and runs on first container start.
###############################################################################
ARG DEBIAN_IMAGE=debian:bookworm-slim
FROM ${DEBIAN_IMAGE}

LABEL maintainer="melroy@melroy.org"
LABEL org.opencontainers.image.title="xfcevdi"
LABEL org.opencontainers.image.description="XFCE4 / X2Go VDI image with MetaTrader 5 (auto-install & auto-update)"

# ---------------------------------------------------------------------------
# Default (run-time) environment variables - used during initial setup
# ---------------------------------------------------------------------------
ENV USERNAME=user \
    USER_ID=1000 \
    ALLOW_APT=yes \
    ENTER_PASS=no \
    # MetaTrader 5 tuning (see scripts/mt5-install.sh for every switch)
    MT5_INSTALL=yes \
    MT5_AUTOUPDATE=yes \
    MT5_CACHE_DIR=/var/cache/mt5 \
    MT5_INSTALL_WEBVIEW2=yes \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Build arguments, _only_ used during Docker build
ARG DEBIAN_FRONTEND=noninteractive
ARG APT_PROXY

WORKDIR /app

# ---------------------------------------------------------------------------
# 1. APT proxy + Debian mirrors
# ---------------------------------------------------------------------------
COPY ./configs/apt.conf ./
COPY ./scripts/apt_proxy.sh ./
RUN ./apt_proxy.sh

# Debian mirrors with contrib/non-free (Debian 12). The bookworm-slim image
# ships a deb822-style /etc/apt/sources.list.d/debian.sources pointing at
# deb.debian.org; we replace the legacy file and remove that default so only
# the configured mirror is used.
COPY ./configs/sources.list /etc/apt/sources.list
RUN set -eux; rm -f /etc/apt/sources.list.d/debian.sources

# ---------------------------------------------------------------------------
# 2. Base tooling (kept small - bookworm-slim start point)
# ---------------------------------------------------------------------------
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg gpg-agent dirmngr \
        apt-transport-https software-properties-common apt-utils \
        lsb-release sudo locales tzdata net-tools \
        procps; \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# 3. X2Go repository + server (Debian bookworm)
# ---------------------------------------------------------------------------
# Import the X2Go signing key, add the repo, then install server + session.
COPY ./configs/x2go.list /etc/apt/sources.list.d/x2go.list

RUN set -eux; \
    gpg --keyserver keyserver.ubuntu.com --recv-keys 972FD88FA0BAFB578D0476DFE1F958385BFE2B6E; \
    gpg --export 972FD88FA0BAFB578D0476DFE1F958385BFE2B6E \
        | tee /etc/apt/trusted.gpg.d/x2go-archive-keyring.gpg >/dev/null; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        x2go-keyring \
        x2goserver x2goserver-xsession; \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# 5. Core services / CLI / general applications
# ---------------------------------------------------------------------------
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        openssh-server \
        pulseaudio \
        pavucontrol \
        dbus-x11 \
        dbus \
        rsyslog \
        cron \
        git \
        wget \
        sudo \
        zip \
        bzip2 \
        unzip \
        xz-utils \
        file \
        dialog \
        pwgen \
        nano \
        vim-tiny \
        at-spi2-core \
        util-linux \
        coreutils \
        xdg-utils \
        ffmpeg \
        htop \
        tmux \
        less; \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# 6. X11 / multimedia / fonts
# ---------------------------------------------------------------------------
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        x11-utils \
        x11-xkb-utils \
        x11-apps \
        xfonts-base \
        fonts-dejavu-core \
        fonts-liberation \
        fonts-noto-core \
        fonts-wqy-microhei \
        fonts-wqy-zenhei \
        fonts-hack-ttf \
        librsvg2-common \
        libgtk-3-0 \
        libnotify4 \
        libxrender1 \
        libxss1 \
        libxmu6; \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# 7. Development / build toolchain (compile-and-test workflow lives here)
# ---------------------------------------------------------------------------
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        gcc \
        g++ \
        make \
        cmake \
        pkg-config \
        ninja-build \
        autoconf \
        automake \
        libtool \
        pkgconf \
        binutils \
        gdb \
        strace \
        ltrace \
        valgrind \
        cppcheck \
        lcov \
        gcovr \
        clang-format \
        clang-tidy \
        ccache \
        python3 \
        python3-dev \
        python3-pip \
        python3-venv \
        python3-setuptools \
        python3-wheel \
        python3-coverage \
        python3-pytest \
        pipx \
        libpq-dev \
        libsqlite3-dev \
        libssl-dev \
        libffi-dev \
        zlib1g-dev \
        libbz2-dev \
        liblzma-dev \
        libreadline-dev \
        curl \
        wget \
        jq \
        shellcheck; \
    rm -rf /var/lib/apt/lists/*

# PEP 668: Debian 12 marks the system Python as externally-managed. Keep the
# documented behaviour (pip installs go to ~/.local) but never break apt.
ENV PIP_BREAK_SYSTEM_PACKAGES=1

# ---------------------------------------------------------------------------
# 8. XFCE 4 desktop
# ---------------------------------------------------------------------------
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        xfwm4 xfce4-session default-dbus-session-bus xfdesktop4 light-locker \
        xfce4-panel xfce4-terminal \
        xfce4-dict xfce4-screenshooter xfce4-appfinder \
        xfce4-taskmanager xfce4-notifyd xfce4-whiskermenu-plugin \
        xfce4-pulseaudio-plugin xfce4-clipman-plugin xfce4-indicator-plugin \
        ristretto tumbler xarchiver \
        thunar thunar-archive-plugin thunar-media-tags-plugin; \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# 9. Desktop applications (browser, editor, calculator, players)
# ---------------------------------------------------------------------------
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        firefox-esr \
        gnome-calculator \
        mousepad \
        celluloid \
        mugshot; \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# 10. Localisation, time zone, SSH host keys
# ---------------------------------------------------------------------------
RUN set -eux; \
    echo 'Aisa/Shanghai' >/etc/timezone || true; \
    ln -snf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime; \
    dpkg-reconfigure -f noninteractive tzdata >/dev/null; \
    update-locale LANG=C.UTF-8

# SSH host keys are generated at build time and regenerated on first start
RUN set -eux; rm -rf /etc/ssh/ssh_host_* && ssh-keygen -A

# ---------------------------------------------------------------------------
# 11. XFCE defaults / autostart tweaks
# ---------------------------------------------------------------------------
# Start default XFCE4 panels without asking (don't ask for it)
RUN set -eux; \
    if [ -f /etc/xdg/xfce4/panel/default.xml ]; then \
        mkdir -p /etc/xdg/xfce4/xfconf/xfce-perchannel-xml; \
        mv -f /etc/xdg/xfce4/panel/default.xml \
              /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml; \
    fi
# Use Mice as default Splash
COPY ./configs/xfconf/xfce4-session.xml /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml
# Add XFCE4 settings to start-up
COPY ./configs/xfce4-settings.desktop /etc/xdg/autostart/
# Enable Clipman by default during start-up
RUN set -eux; \
    if [ -f /etc/xdg/autostart/xfce4-clipman-plugin-autostart.desktop ]; then \
        sed -i 's/Hidden=.*/Hidden=false/' /etc/xdg/autostart/xfce4-clipman-plugin-autostart.desktop; \
    fi; \
    rm -rf /etc/xdg/autostart/light-locker.desktop /etc/xdg/autostart/xscreensaver.desktop || true

# ---------------------------------------------------------------------------
# 12. Hardening: disable the root shell
# ---------------------------------------------------------------------------
RUN usermod -s /usr/sbin/nologin root

# ---------------------------------------------------------------------------
# 13. "worker" service user + sudoers (runs run.sh, owns the desktop)
# ---------------------------------------------------------------------------
RUN useradd -d /app -s /bin/bash -u 1001 worker
RUN echo "Defaults!/app/setup.sh setenv" >>/etc/sudoers
RUN echo "worker ALL=(root) NOPASSWD:/usr/sbin/service ssh start, /usr/sbin/service dbus start, /usr/sbin/service rsyslog start, /usr/sbin/service cron start, /app/setup.sh" >>/etc/sudoers

# ---------------------------------------------------------------------------
# 14. Runtime scripts (copied early so shellcheck sees them & cache stays hot)
# ---------------------------------------------------------------------------
COPY ./scripts/setup.sh ./
COPY ./scripts/run.sh ./
COPY ./scripts/xfce_settings.sh ./
COPY ./configs/terminalrc ./
COPY ./configs/whiskermenu-1.rc ./
COPY ./configs/pip.conf /root/.pip/pip.conf

RUN echo 'echo "Info: Thank you for using Melroys VDI XFCE Docker image!"' >>/app/.bashrc

# ---------------------------------------------------------------------------
# 15. MetaTrader 5 helper tooling (installed OUTSIDE the final MT5 layer so
#     rebuilding only the MT5 layer stays cheap and never rebuilds Wine).
# ---------------------------------------------------------------------------
RUN set -eux; \
    mkdir -p /usr/local/bin /var/log/mt5; \
    chmod 0777 /var/log/mt5

COPY ./scripts/mt5-launch.sh     /usr/local/bin/mt5-launch
COPY ./scripts/mt5-autoupdate.sh /usr/local/bin/mt5-autoupdate
COPY ./configs/metatrader5.desktop /usr/share/applications/metatrader5.desktop
COPY ./configs/mt5-cron          /etc/cron.d/mt5-autoupdate

RUN set -eux; \
    chmod +x /usr/local/bin/mt5-launch /usr/local/bin/mt5-autoupdate; \
    chmod 0644 /etc/cron.d/mt5-autoupdate

# ---------------------------------------------------------------------------
# 16. Wine (WineHQ stable) + MT5 runtime dependencies
# ---------------------------------------------------------------------------
RUN set -eux; \
    dpkg --add-architecture i386; \
    mkdir -p /etc/apt/keyrings; \
    curl -fsSL https://dl.winehq.org/wine-builds/winehq.key \
        | gpg --dearmor -o /etc/apt/keyrings/winehq-archive.key; \
    wget -NP /etc/apt/sources.list.d/ \
        https://dl.winehq.org/wine-builds/debian/dists/bookworm/winehq-bookworm.sources; \
    apt-get update; \
    apt-get install -y --install-recommends winehq-stable; \
    apt-get install -y --no-install-recommends \
        winbind \
        cabextract \
        p7zip-full \
        fonts-wine \
        libgl1 \
        libglu1-mesa \
        libxcomposite1 \
        libxinerama1 \
        libxcursor1 \
        libxi6 \
        libxrandr2 \
        libcups2 \
        libdbus-1-3 \
        libfontconfig1 \
        libfreetype6 \
        libglib2.0-0 \
        libgstreamer1.0-0 \
        libgstreamer-plugins-base1.0-0 \
        libjpeg62-turbo \
        libodbc1 \
        libosmesa6 \
        libpng16-16 \
        libsdl2-2.0-0 \
        libtiff6 \
        libudev1 \
        libxkbcommon0 \
        libxfixes3 \
        libgdk-pixbuf-2.0-0 \
        xdg-utils \
        x11-utils; \
    rm -rf /var/lib/apt/lists/*; \
    wine --version

###############################################################################
# 17. **LAST LAYER - MetaTrader 5**
#
# Everything above is stable. This layer only contains MT5-specific state, so
# when MetaQuotes ships a new build you re-run `docker build` (or just refresh
# this layer): every lower layer is reused from cache and only the installer is
# re-fetched, giving you the newest MT5 build without rebuilding the OS.
#
# The installer is prefetched here (best effort - the image still builds if the
# MetaQuotes CDN is unreachable). Actual install/upgrade runs:
#   * on first container start (mt5-install), and
#   * every 6 hours via /etc/cron.d/mt5-autoupdate (mt5-autoupdate).
###############################################################################
RUN set -eux; \
    mkdir -p /opt/mt5 /var/cache/mt5; \
    chmod 0777 /var/cache/mt5

COPY ./scripts/mt5-install.sh /usr/local/bin/mt5-install

RUN /usr/local/bin/mt5-install --prefetch || true

# Smoke test: the tooling must be present even when the CDN was unreachable.
RUN set -eux; \
    command -v mt5-install >/dev/null; \
    command -v mt5-launch >/dev/null; \
    command -v mt5-autoupdate >/dev/null; \
    test -f /usr/share/applications/metatrader5.desktop; \
    test -f /etc/cron.d/mt5-autoupdate; \
    wine --version

# ---------------------------------------------------------------------------
# 18. Final runtime contract
# ---------------------------------------------------------------------------
# Permit the worker user to run the MT5 install/refresh without a password
RUN echo "worker ALL=(root) NOPASSWD:/usr/local/bin/mt5-install, /usr/local/bin/mt5-autoupdate" >>/etc/sudoers

USER worker
EXPOSE 22
CMD ["/bin/bash", "/app/run.sh"]
