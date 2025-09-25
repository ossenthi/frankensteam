#!/bin/bash

# =============================================================================
# Variable declarations)
# =============================================================================

readonly CONTAINER_NAME=frankensteam
readonly IMAGE=frankensteam
readonly REQUIRED_COMMANDS=(podman nvidia-smi xwayland-satellite)
readonly USER_UID=1000
readonly USER_GID=1000
readonly USER_NAME=user
readonly HOST_NAME=frankensteam

# Directory paths
BASE_DIR="$(pwd)"
CONTAINER_HOME="${BASE_DIR}/home"
DATA_STORAGE="$(dirname "${BASE_DIR}")/Library" #change this to your Steam Library location

# =============================================================================
# Script logic starts here
# =============================================================================

load_config() {
export CONTAINERS_STORAGE_CONF=$(pwd)/storage.conf
}

cleanup_on_failure() {
    podman rm -f "${CONTAINER_NAME}" 2>/dev/null || true
}

error_handler() {
    local line_no=$1
    local error_code=$2
    local last_command="${BASH_COMMAND}"
    echo "Error in line ${line_no}: Command '${last_command}' exited with status ${error_code}"
    cleanup_on_failure
    exit "${error_code}"
}

trap 'error_handler ${LINENO} $?' ERR

check_dependencies() {
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "Missing required command: "$cmd""
            exit 1
        fi
    done
}

validate_and_set_paths() {
    if [[ ! -d "${DATA_STORAGE}" ]]; then
        mkdir -p "${DATA_STORAGE}"
    fi

    if [[ ! -d "${CONTAINER_HOME}" ]]; then
        mkdir -p "${CONTAINER_HOME}"

    fi
}   

setup_nvidia_gpu() {
    if ! nvidia-smi --query-gpu=gpu_name --format=csv,noheader >/dev/null 2>&1; then
        return 1
    fi

    if [ ! -f "/etc/cdi/nvidia.yaml" ]; then
        if ! nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml; then
            return 1
        fi
    fi

    nvidia-smi --query-gpu=gpu_name,memory.total,driver_version --format=csv,noheader
}

setup_audio_proxy() {
    pw-container &  # Start pw-container in the background
    # Wait for the PipeWire socket to be created
    SOURCE_SOCKET=""
    for i in {1..10}; do
        SOURCE_SOCKET=$(lsof -p "$PW_PID" 2>/dev/null | grep /tmp/pipewire- | awk '{print $9}' | head -n 1)
        if [ -S "$SOURCE_SOCKET" ]; then
            break
        fi
        sleep 0.01
    done

    TARGET_LINK="/tmp/pipewire-socket"
    if [ -S "$SOURCE_SOCKET" ]; then
        # Create or update the symbolic link
        ln -sf "$SOURCE_SOCKET" "$TARGET_LINK"
    else
        return 1
    fi
}

setup_dbus_proxy() {
    mkdir -p /run/user/1000/.dbus-proxy
    xdg-dbus-proxy --fd=3 \
    unix:path=/run/user/1000/bus /run/user/1000/.dbus-proxy/session-bus-proxy-flatpod \
    --filter \
    --own=com.steampowered.* \
    --talk=org.freedesktop.Notifications \
    --talk=org.freedesktop.PowerManagement \
    --talk=org.freedesktop.ScreenSaver \
    --talk=org.gnome.SettingsDaemon.MediaKeys \
    --talk=org.kde.StatusNotifierWatcher \
    --talk=org.freedesktop.UPower \
    --talk=org.freedesktop.UDisks2 >/dev/null 2>&1 &
      local socket="/run/user/1000/.dbus-proxy/session-bus-proxy-flatpod"
    for i in {1..10}; do
        if [ -S "$socket" ]; then
            break
        fi
        sleep 0.1
    done
}
remove_old_sockets(){
    rm -f /tmp/pipewire-socket
    rm -f /run/user/1000/wayland-9
    rm -f /tmp/.X11-unix/X9
}

waylad_setup() {
    ./wayland-proxy-virtwl --wayland-display wayland-9 >/dev/null 2>&1 &
}
xwaylad_setup() {
    xwayland-satellite :9 >/dev/null 2>&1 &
    for i in {1..10}; do
        if [ -S "/tmp/.X11-unix/X9" ]; then
            break
        fi
        sleep 0.01
    done
    xauth generate :9 . trusted
    xauth list :9 > "$CONTAINER_HOME/xauth"
    if [ ! -S "$XDG_RUNTIME_DIR/wayland-9" ]; then
    socat UNIX-LISTEN:"$XDG_RUNTIME_DIR/wayland-9",fork - &
    fi
}

host_sockets(){
    ln -sf /tmp/.X11-unix/X0 /tmp/.X11-unix/X9
    ln -sf "$XDG_RUNTIME_DIR/wayland-0" "$XDG_RUNTIME_DIR/wayland-9"
    cp -f $XAUTHORITY "$CONTAINER_HOME/xauth"
}

container_exists() {
    podman container exists "${CONTAINER_NAME}"
}

container_running() {
   [[ "$(podman inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null || echo "false")" == "true" ]]
}
create_pkg_cache(){
    if ! podman volume inspect pacman-pkg > /dev/null 2>&1; then
    echo "creating volume pacman-pkg"
    podman volume create pacman-pkg
    else
    echo "volume pacman-pkg already exists"
    fi

}
create_container() {
    podman create -it \
        --name "${CONTAINER_NAME}" \
        --hostname="${HOST_NAME}" \
        --userns=keep-id \
        --shm-size="1gb" \
        --device=nvidia.com/gpu=all \
        --mount type=bind,source="${BASE_DIR}/init",destination=/init,readonly \
        --mount type=bind,source=/tmp/pipewire-socket,destination="$XDG_RUNTIME_DIR/pipewire-0",readonly \
        --mount type=bind,source="$XDG_RUNTIME_DIR/wayland-9",destination=/run/user/1000/wayland-0,readonly \
        --mount type=bind,source=/tmp/.X11-unix/X9,destination=/tmp/.X11-unix/X0,readonly \
        -v /run/user/1000/.dbus-proxy/session-bus-proxy-flatpod:/run/user/1000/bus \
        -v "${CONTAINER_HOME}:/home/${USER_NAME}" \
        -v pacman-pkg:/var/cache/pacman/pkg \
        -v "${DATA_STORAGE}":/mnt/Steam \
        -e XDG_RUNTIME_DIR=/run/user/"${USER_UID}" \
        -e DBUS_SESSION_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS" \
        "${IMAGE}"
}
cleanup() {

    remove_old_sockets
    kill 0
    wait
}

main() {
    load_config
    #waylad_setup # wayland is not needed but if you want build the binery wayland-proxy-virtwl from the source and put it on script directory
    xwaylad_setup
    #host_sockets # using host sockes are buggy and not grate for security need to comment out waylad_setup and xwaylad_setup
    setup_dbus_proxy
    setup_audio_proxy
    if container_exists; then
        echo "Container '${CONTAINER_NAME}' exists."
        if ! container_running; then
            echo "Starting existing container '${CONTAINER_NAME}'..."
        else
            echo "Container '${CONTAINER_NAME}' is already running."
            exit 0
        fi
    else
        echo "Creating container '${CONTAINER_NAME}'..."
        check_dependencies
        validate_and_set_paths
        setup_nvidia_gpu
        create_pkg_cache
        create_container
    fi
    podman start -ia "${CONTAINER_NAME}"
}

trap 'trap - SIGTERM SIGINT; cleanup' SIGTERM SIGINT EXIT
main
