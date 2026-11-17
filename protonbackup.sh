#!/usr/bin/env bash
set -euo pipefail

source /home/proton-drive/protonbackup.conf

local_dirs=("${LOCAL_DIRS[@]}")
remote_dir=("${REMOTE_DIR[@]}")
local_log_file="${LOG_FILE_LOCATION}"
environmental_variables=("${ENVIRONMENTAL_VARIABLES[@]}")

log( message ) {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$local_log_file"
}

backup( DIR ){
    log "Starting backup to proton drive for directory: $DIR"
    
}