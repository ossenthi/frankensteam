FROM archlinux:latest

RUN pacman -Syu --noconfirm curl tar jq

# Download and extract the latest s6-overlay release
RUN set -eux; \
    # set version for s6 overlay
    export S6_OVERLAY_VERSION=$(curl --silent -m 10 --connect-timeout 5 "https://api.github.com/repos/just-containers/s6-overlay/releases/latest" | jq -r .tag_name); \
    # add s6 overlay
    curl -L -o /tmp/s6-overlay-noarch.tar.xz https://github.com/just-containers/s6-overlay/releases/download/${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz; \
    tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz; \
    rm /tmp/s6-overlay-noarch.tar.xz; \
    curl -L -o /tmp/s6-overlay-x86_64.tar.xz https://github.com/just-containers/s6-overlay/releases/download/${S6_OVERLAY_VERSION}/s6-overlay-x86_64.tar.xz; \
    tar -C / -Jxpf /tmp/s6-overlay-x86_64.tar.xz; \
    rm /tmp/s6-overlay-x86_64.tar.xz; \
    # add s6 optional symlinks
    curl -L -o /tmp/s6-overlay-symlinks-noarch.tar.xz https://github.com/just-containers/s6-overlay/releases/download/${S6_OVERLAY_VERSION}/s6-overlay-symlinks-noarch.tar.xz; \
    tar -C / -Jxpf /tmp/s6-overlay-symlinks-noarch.tar.xz && unlink /usr/bin/with-contenv; \
    rm /tmp/s6-overlay-symlinks-arch.tar.xz

    # runtime stage
FROM scratch
COPY --from=pacstrap-stage /root-out/ /
ARG BUILD_DATE
ARG VERSION
ARG MODS_VERSION="v3"
ARG PKG_INST_VERSION="v1"
ARG LSIOWN_VERSION="v1"
ARG WITHCONTENV_VERSION="v1"
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="TheLamer"

ADD --chmod=744 "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/docker-mods.${MODS_VERSION}" "/docker-mods"
ADD --chmod=744 "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/package-install.${PKG_INST_VERSION}" "/etc/s6-overlay/s6-rc.d/init-mods-package-install/run"
ADD --chmod=744 "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/lsiown.${LSIOWN_VERSION}" "/usr/bin/lsiown"
ADD --chmod=755 "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/with-contenv.${WITHCONTENV_VERSION}" "/usr/bin/with-contenv"

# environment variables
ENV PS1="$(whoami)@$(hostname):$(pwd)\\$ " \
  HOME="/root" \
  TERM="xterm" \
  S6_CMD_WAIT_FOR_SERVICES_MAXTIME="0" \
  S6_VERBOSITY=1 \
  S6_STAGE2_HOOK=/docker-mods \
  VIRTUAL_ENV=/lsiopy \
  PATH="/lsiopy/bin:$PATH"

RUN \
echo "**** create abc user and make our folders ****" && \
useradd -u 911 -U -d /config -s /bin/bash abc && \
echo "abc:abc" | chpasswd && \
echo 'abc ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/abc && \
usermod -aG users abc && \
useradd -u 1000 -U -d /home/steam-user -s /bin/bash steam-user && \
echo "steam-user:steam" | chpasswd && \
echo 'steam-user ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/steam-user && \
usermod -aG users steam-user && \
mkdir -p /home/steam-user && \
chown 1000:1000 /home/steam-user && \
mkdir -p /var/run/pulse && \
chown 1000:root /var/run/pulse && \
echo "allowed_users=anybody" > /etc/X11/Xwrapper.config
mkdir -p \
    /app \
    /config \
    /defaults \
    /lsiopy && \
echo "**** configure pacman ****" && \
locale-gen && \
pacman-key --init && \
pacman-key --populate archlinux && \
echo "**** configure locale ****" && \
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
locale-gen && \
echo "**** cleanup ****" && \
rm -rf \
    /tmp/* \
    /var/cache/pacman/pkg/* \
    /var/lib/pacman/sync/*
 
# add local files
COPY root/ /

ENTRYPOINT ["/init"]
