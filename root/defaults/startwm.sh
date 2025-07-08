#!/bin/bash

# Set route if defined
if [ ! -z ${HOST_IP+x} ]; then
  sudo ip route delete default
  sudo ip route add ${HOST_IP} dev eth0
  sudo ip route add default via ${HOST_IP}
fi

# Copy default files
if [ ! -d $HOME/.config/sunshine ]; then
  mkdir -p $HOME/.config/sunshine
  cp /defaults/apps.json $HOME/.config/sunshine/
  if [ -z ${DRINODE+x} ]; then
    DRINODE="/dev/dri/renderD128"
  fi
  echo "adapter_name = ${DRINODE}" > $HOME/.config/sunshine/sunshine.conf
fi

# Start sunshine in background
sunshine &

# Runtime deps
mkdir -p $HOME/.XDG
export XDG_RUNTIME_DIR=$HOME/.XDG

export $(dbus-launch)
gamescope -e -f -- steam -steamos3 -steamdeck -steampal -gamepadui
