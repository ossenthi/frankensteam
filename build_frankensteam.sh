#!/usr/bin/env bash
set -euo pipefail

#---------------- USER CONFIGURATION ----------------#
IMAGE_NAME="frankensteam"
DOCKERFILE_NAME="Dockerfile"
config_src="/usr/share/containers/storage.conf"
config_dst="$(pwd)/storage.conf"

#---------------------------------------------------#
# Patch storage.conf for rootless Podman in the current directory
set_podman_storage() {
  local runroot="${PWD}/containers/run"
  local graphroot="${PWD}/containers/storage"
  local tmp_file="$(pwd)/storage.conf.tmp"
  # If the final config file already exists, do nothing
  [[ -f "$config_dst" ]] && {
    echo "storage.conf already exists"
  }

  # Copy the source config to the temporary file
  cp -u "$config_src" "$tmp_file"

  # Apply the substitutions and write the result to the destination file
  sed -e "s|^runroot = \"/run/containers/storage\"|runroot = \"$runroot\"|" \
      -e "s|^graphroot = \"/var/lib/containers/storage\"|graphroot = \"$graphroot\"|" \
      -e "s|# rootless_storage_path.*|rootless_storage_path = \"$graphroot\"|" \
      "$tmp_file" > "$config_dst"

  # Clean up the temporary file
  rm -f "$tmp_file"
}


#---------------------------------------------------#
# Build the container image with Podman or Docker
build_image() {

    echo "Building image '$IMAGE_NAME'..."
    if command -v podman &>/dev/null; then
        podman build -t "$IMAGE_NAME" -f "$DOCKERFILE_NAME" .
    elif command -v docker &>/dev/null; then
        docker build -t "$IMAGE_NAME" -f "$DOCKERFILE_NAME" .
    else
        echo "Error: Neither podman nor docker is installed. Cannot build image."
        exit 1
    fi
}

#---------------------------------------------------#
main() {
    read -r -p "Do you want to change podman storage location to the current directory? [y/N] " answer
    case "$answer" in
        [Yy]* )
            set_podman_storage
            ;;
        * )
            echo "Skipping storage location change."
             cp -u "$config_src" "$config_dst"
            ;;
    esac
    export CONTAINERS_STORAGE_CONF="$config_dst"
    # Check if the image exists locally (Podman first, then Docker)
    if podman image inspect "$IMAGE_NAME" &>/dev/null \
       || docker image inspect "$IMAGE_NAME" &>/dev/null; then
        echo "Image '$IMAGE_NAME' already exists locally."
        read -r -p "Do you want to rebuild it? [y/N] " answer
        case "$answer" in
            [Yy]* )
                build_image
                ;;
            * )
                echo "Skipping rebuild."
                ;;
        esac
    else
        echo "Image '$IMAGE_NAME' not found locally. Building it now..."
        build_image
    fi
}

main
exit 0
