#!/usr/bin/bash

# Set the storage configuration to the current working directory
export CONTAINERS_STORAGE_CONF=$(pwd)/storage.conf

echo "Podman storage location changed to current working directory"

# Create a history file if it doesn't exist
HISTORY_FILE="./podman_cwd_bash_history"
if [ ! -f "$HISTORY_FILE" ]; then
    touch "$HISTORY_FILE"
    echo "Created history file: $HISTORY_FILE"
fi

# Start a new bash session with the specified history file
env HISTFILE="$HISTORY_FILE" bash
