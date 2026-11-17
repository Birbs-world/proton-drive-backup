#!/usr/bin/env bash
set -euo pipefail

source proton_backup.conf

local_dirs="/home/"
remote_dir="/my-files/test/testfolder"
local_log_file="${LOG_FILE_LOCATION}"
environmental_variables=("${ENVIRONMENTAL_VARIABLES[@]}")
host=$(echo "$HOSTNAME")
TIMESTAMP=$(date +%Y/%m/%d-%H:%M:%S)
bad_requirements=false

color() {
    local color="$1"
    local text="$2"
    case "$color" in
        ("red") echo -e "\033[31m$text\033[0m" ;;
        ("green") echo -e "\033[32m$text\033[0m" ;;
        ("yellow") echo -e "\033[33m$text\033[0m" ;;
    esac
}

log() {
    level=$1
    message=$2
    #determine the log level and format the message accordingly
    if [[ "$level" == "ERROR" ]]; then
        log_msg="$TIMESTAMP - Level:$LOG_LEVEL - $(color "red" "ERROR"): $message"
    elif [[ "$level" == "INFO" ]]; then
        log_msg="$TIMESTAMP - Log_Level:$LOG_LEVEL - $(color "green" "INFO"): $message"
    elif [[ "$level" == "WARNING" ]]; then
        log_msg="$TIMESTAMP - Level:$LOG_LEVEL - $(color "yellow" "WARNING"): $message"
    elif [[ "$level" == "DEBUG" ]]; then
        log_msg="$TIMESTAMP - Level:$LOG_LEVEL - $(color "yellow" "DEBUG"): $message"
    else
        log_msg="$TIMESTAMP - UNKNOWN LEVEL: $message"
    fi

    #check the log level and write the message to the log file and stdout if it meets the criteria
    if [[ "$LOG_LEVEL" == "INFO" ]]; then
        if [[ "$level" == "INFO" || "$level" == "ERROR" ]]; then
            echo "TESTINFO $log_msg"
        fi

    elif [[ "$LOG_LEVEL" == "ERROR" ]]; then
        if [[ "$level" == "ERROR" ]]; then
            echo "TESTERROR $log_msg"
        fi

    elif [[ "$LOG_LEVEL" == "WARNING" ]]; then
        if [[ "$level" == "WARNING" || "$level" == "ERROR" ]]; then
            echo "TEST $log_msg"
        fi

    elif [[ "$LOG_LEVEL" == "DEBUG" ]]; then
        if [[ "$level" == "DEBUG" || "$level" == "INFO" || "$level" == "WARNING" || "$level" == "ERROR" ]]; then
            echo "TESTDEBUG $log_msg"
        fi
    fi
}

backup(){
    DIR=$1
    log "INFO" "Starting backup to proton drive for directory $DIR on $host"

    #check if the directory exists before proceeding with the backup
    if [[ ! -d "$DIR" ]]; then
        log "ERROR" "Directory $DIR does not exist. Skipping backup for this directory."
        return 1
    fi

        if [[ ! -d "$remote_dir" ]]; then
            log "ERROR" "Remote directory $remote_dir does not exist. Skipping backup for this directory."
            return 1
        fi

    if [[ $LOG_LEVEL == "DEBUG" ]]; then
        log "INFO" "Backing up directory $DIR to remote directory $remote_dir"
        
        ##initate backup using protondrive-cli and report json output
        proton-drive filesystem upload "$LOCAL_DIR" "$REMOTE_DIR" \
            --folder-conflict-strategy merge \
            --file-conflict-strategy create-new-revision \
            --json > /tmp/protonbackup.json
        log "DEBUG" "Backup completed for directory $DIR. Output: $(cat /tmp/protonbackup.json)"
    else
        ##initate backup using protondrive-cli and dont report output
        proton-drive filesystem upload "$LOCAL_DIR" "$REMOTE_DIR" \
            --folder-conflict-strategy merge \
            --file-conflict-strategy create-new-revision
        
        log "INFO" "Backup completed for directory $DIR."
    fi

}


#Start of the script execution


#peforming Initial checks for required packages and proton-drive-cli installation
log "INFO" "Starting Backup Script. Checking for required packages."
requirements=$(cat requirements.txt)

for requirement in $requirements; do
    if ! which "$requirement" > /dev/null; then
        log "ERROR" "Requirement $requirement is not installed. Please install it before running the backup script."
        bad_requirements=true
        missing_requirements+=("$requirement")
    else
        log "DEBUG" "Requirement $requirement is installed."
    fi
done

if [ "$bad_requirements" = true ]; then
    log "ERROR" "Some required packages are missing. Please install them before running the backup script."
    log "ERROR" "Missing requirements: ${missing_requirements[*]}"
    exit 1
fi

#check if proton-drive-cli is installed and available in the PATH
if ! command -v proton-drive &> /dev/null; then
    log "ERROR" "proton-drive-cli is not installed or not available in the PATH. Please install and add it to the PATH before running the backup script."
    exit 1
fi
#check if logged in to proton drive before proceeding with the backup
if ! [[ "$(proton-drive fs list /my-files/ -j | jq '.[0] | .name.ok')" == "true" ]]; then
    log "ERROR" "Not logged in to Proton Drive. Please log in before running the backup script."
    exit 1
else 
    log "INFO" "Logged in to Proton Drive. Proceeding with the backup."
fi

#check that host folder exists on proton drive before proceeding with the backup
host_folder_check=false
log "INFO" "Check if folder for host $host exists on Proton Drive. If not, it will be created."
while [ $host_folder_check = false ]; do
    if ! [[ "$(proton-drive fs list /my-files/proton-drive-backup/ -j | jq --arg hostname "$host" '.[] | select(.name.value==$hostname)| .name.ok')" == "true" ]]; then
        log "WARNING" "host folder does not exist."
        if ! [[ "$(proton-drive fs list /my-files/ -j | jq '.[] | select(.name.value=="proton-drive-backup")| .name.ok')" == "true" ]]; then
            log "WARNING" "proton-drive-backup folder does not exist, creating"
            log "INFO" "$(proton-drive fs create-folder /my-files/ proton-drive-backup -j | jq -S)"
        else
            log "DEBUG" "proton-drive-backup folder exists on Proton Drive."
        fi
        log "INFO" "Creating host folder on Proton Drive."
        log "INFO" "$(proton-drive fs create-folder /my-files/proton-drive-backup "${host}" -j | jq -S)"
    else
        log "INFO" "host folder exists on Proton Drive. Proceeding with the backup."
        host_folder_check=true
    fi
done
