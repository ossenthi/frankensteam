# ---------- Build stage ----------
ARG BASE_IMAGE=cachyos/cachyos:latest
FROM docker.io/${BASE_IMAGE} AS rootfs

ARG USER_NAME=user
ARG USER_UID=1000
ARG USER_GID=1000

# remove unwanted pkgs
RUN pacman -Sy && \
    pacman -D --asexplicit sudo which &&\
    pacman -Runs --noconfirm base-devel

# Pacman config
COPY pacman-znver4.conf /etc/pacman.conf

# System upgrade and cleanup
RUN pacman -Syyuu --noconfirm && \
    pacman -Scc --noconfirm && \
    rm -r /var/lib/pacman/sync/* && \
    find /var/cache/pacman/ -type f -delete

# Create user & groups
RUN if ! getent group ${USER_GID}; then \
        groupadd -g ${USER_GID} ${USER_NAME}; \
    fi && \
    if ! id ${USER_NAME} &>/dev/null; then \
        useradd -m -u ${USER_UID} -g ${USER_GID} -s /bin/bash ${USER_NAME}; \
    fi && \
    usermod -aG audio,video,input,render ${USER_NAME}

# Password‑less sudo (drop‑in)
RUN echo "${USER_NAME} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/${USER_NAME} && \
    chmod 0440 /etc/sudoers.d/${USER_NAME}

# Runtime directory
RUN mkdir -p "/run/user/${USER_UID}" && \
    chown "${USER_UID}:${USER_GID}" "/run/user/${USER_UID}" && \
    chmod 0700 "/run/user/${USER_UID}"

# DBus setup
RUN sed -i "/<user>/c\<user>${USER_NAME}</user>" /usr/share/dbus-1/system.conf && \
    mkdir -p /var/run/dbus && \
    chown "${USER_UID}:${USER_GID}" /var/run/dbus && \
    dbus-uuidgen > /var/lib/dbus/machine-id

# ---------- Final image ----------
FROM scratch
LABEL org.opencontainers.image.description="CachyOS – Arch‑based distro with performance optimizations."
COPY --from=rootfs / /

USER ${USER_NAME}
WORKDIR /home/${USER_NAME}
ENTRYPOINT ["/init"]
