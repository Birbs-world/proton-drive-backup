#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source proton_backup.conf

#local var setup
parent=$(echo "$ENVIRONMENTAL_VARIABLES" | jq -r .parent)
remote_dir="/my-files/$parent/$HOSTNAME"
TIMESTAMP=$(date +%Y/%m/%d-%H:%M:%S)
bad_requirements=false

#terminal color function for log levels
color() {
    local color="$1"
    local text="$2"
    case "$color" in
        ("red") echo -e "\033[31m$text\033[0m" ;;
        ("green") echo -e "\033[32m$text\033[0m" ;;
        ("yellow") echo -e "\033[33m$text\033[0m" ;;
    esac
}


#log Handler
mkdir -p "$LOG_FILE_LOCATION"
log() {
    level=$1
    message=$2
    #determine the log level and format the message for stout accordingly
    if [[ "$level" == "ERROR" ]]; then
        log_msg="$TIMESTAMP - Level:$LOG_LEVEL - $(color "red" "ERROR"): $message"
    elif [[ "$level" == "INFO" ]]; then
        log_msg="$TIMESTAMP - Log_Level:$LOG_LEVEL - $(color "green" "INFO"): $message"
    elif [[ "$level" == "WARNING" ]]; then
        log_msg="$TIMESTAMP - Level:$LOG_LEVEL - $(color "yellow" "WARNING"): $message"
    elif [[ "$level" == "DEBUG" ]]; then
        log_msg="$TIMESTAMP - Log_Level:$LOG_LEVEL - $(color "yellow" "DEBUG"): $message"
    fi

    #check the log level and write the message to the log file and stdout if it meets the criteria
    if [[ "$LOG_LEVEL" == "INFO" ]]; then
        if [[ "$level" == "INFO" || "$level" == "ERROR" || "$level" == "WARNING" ]]; then
            echo "$TIMESTAMP - $level : $message" >> "$LOG_FILE_LOCATION/protonbackup.log"
        fi

    elif [[ "$LOG_LEVEL" == "ERROR" ]]; then
        if [[ "$level" == "ERROR" ]]; then
            echo "TESTERROR $log_msg" && echo "$TIMESTAMP - $level : $message" >> "$LOG_FILE_LOCATION/protonbackup.log"
        fi

    elif [[ "$LOG_LEVEL" == "WARNING" ]]; then
        if [[ "$level" == "WARNING" || "$level" == "ERROR" ]]; then
            echo "TESTWARNING $log_msg" && echo "$TIMESTAMP - $level : $message" >> "$LOG_FILE_LOCATION/protonbackup.log"
        fi

    elif [[ "$LOG_LEVEL" == "DEBUG" ]]; then
        if [[ "$level" == "DEBUG" || "$level" == "INFO" || "$level" == "WARNING" || "$level" == "ERROR" ]]; then
            echo "TESTDEBUG $log_msg" && echo "$TIMESTAMP - $level : $message" >> "$LOG_FILE_LOCATION/protonbackup.log"
        fi
    fi
}

#backup function to perform the backup of a given directory to proton drive
backup(){
    BACKUP=$1
    log "INFO" "Starting backup to proton drive for directory $DIR on $HOSTNAME"

    #check if the directory exists before proceeding with the backup
    if [[ ! -d "$BACKUP" ]]; then
        log "ERROR" "Directory $BACKUP does not exist. Skipping backup for this directory."
        return 1
    fi

    
    log "INFO" "Backing up directory $BACKUP to remote directory $remote_dir"
    ##initate backup using protondrive-cli and report json output
    proton-drive filesystem upload "$BACKUP" "$remote_dir" \
        --folder-conflict-strategy merge \
        --file-conflict-strategy create-new-revision \
        --json > /tmp/protonbackupstatus.json 
    log "DEBUG" "Backup completed for directory $BACKUP. Status: $(cat /tmp/protonbackupstatus.json)"

    #check for Failed Items
    if [[ "$(jq '.failedItems' /tmp/protonbackupstatus.json)" -gt 0 ]]; then
        log "ERROR" "Files/directories failed for directory $BACKUP. Files Failed: $(jq '.failedItems' /tmp/protonbackupstatus.json)"
        log "ERROR" "The following files has failed to upload\n$(jq '.failures[].name' /tmp/protonbackupstatus.json)"
    
    fi
    log "INFO" "Backup Finished for directory $BACKUP."
    
}

#Start of the script execution
credential_store=$(echo "$ENVIRONMENTAL_VARIABLES" | jq -r .cred_store)
log "INFO" Credential store = "${credential_store}"
export PROTON_DRIVE_CREDENTIALS_STORE="${credential_store}"

#peforming Initial checks for required packages and proton-drive-cli installation
log "INFO" "Starting Backup Script. Checking for required packages."
requirements=$(cat requirements.txt)

#cycle through the requirements and check if they are installed, if not log an error but keep checking for the rest of the requirements
for requirement in $requirements; do
    if ! which "$requirement" > /dev/null; then
        log "ERROR" "Requirement $requirement is not installed. Please install it before running the backup script."
        bad_requirements=true
        missing_requirements+=("$requirement")
    else
        log "DEBUG" "Requirement $requirement is installed."
    fi
done
#list any Failed dependencies and exit the script if any are found
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
log "INFO" "Check if folder for host: $HOSTNAME exists on Proton Drive. If not, it will be created."
while [ $host_folder_check = false ]; do
    if ! [[ "$(proton-drive fs list /my-files/"$parent"/ -j | jq --arg hostname "$HOSTNAME" '.[] | select(.name.value==$hostname)| .name.ok')" == "true" ]]; then
        log "WARNING" "host folder does not exist."
        if ! [[ "$(proton-drive fs list /my-files/ -j | jq --arg parent "$parent" '.[] | select(.name.value==$parent)| .name.ok')" == "true" ]]; then
            log "WARNING" "Parent folder: $parent does not exist, creating"
            log "INFO" "Parent folder creation status: $(proton-drive fs create-folder /my-files/ "$parent" -j | jq -r .name)"
        else
            log "DEBUG" "proton-drive-backup folder exists on Proton Drive."
        fi
        log "INFO" "Creating host folder on Proton Drive."
        log "INFO" "Host folder creation status: $(proton-drive fs create-folder /my-files/"$parent"/ "${HOSTNAME}" -j | jq -r .name)"
    else
        log "INFO" "host folder exists on Proton Drive. Proceeding with the backup."
        host_folder_check=true
    fi
done

# process backup for each directory specified in LOCAL_DIRS
log "DEBUG" "Starting backup for directories: $LOCAL_DIRS"
for DIR in "${LOCAL_DIRS[@]}"; do
    log "INFO" "Backing up directory: $DIR"
    backup "$DIR"
done