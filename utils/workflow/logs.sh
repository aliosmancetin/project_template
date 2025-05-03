#!/bin/bash


# Logging functions
log_info () {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="${timestamp} [INFO] $1"

    if [[ -z "${INTERACTIVE_MODE}" || "${INTERACTIVE_MODE,,}" == "true" ]]; then
        printf "%s\n" "${message}"
    else
        printf "%s\n" "${message}" >> "${STEP_OUTPUT_LOG}"
    fi
}

log_error () {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="${timestamp} [ERROR] $1"

    if [[ -z "${INTERACTIVE_MODE}" || "${INTERACTIVE_MODE,,}" == "true" ]]; then
        printf "%s\n" "${message}" >&2
    else
        printf "%s\n" "${message}" >> "${STEP_ERROR_LOG}"
    fi
}

log_debug () {
    if [[ "${DEBUG_MODE,,}" == "true" ]]; then
        local timestamp
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local message="${timestamp} [DEBUG] $1"

        if [[ -z "${INTERACTIVE_MODE}" || "${INTERACTIVE_MODE,,}" == "true" ]]; then
            printf "%s\n" "${message}"
        else
            printf "%s\n" "${message}" >> "${STEP_OUTPUT_LOG}"
        fi
    fi
}



# Add a separator with a timestamp and SLURM Job ID
log_separator () {
    local job_id=${SLURM_JOB_ID:-"UNKNOWN"}
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    {
        printf "%s\n" "----------------------------------------------------------------------"
        printf "Run started at %s (Job ID: %s)\n" "${timestamp}" "${job_id}"
        printf "%s\n" "----------------------------------------------------------------------"
    } >> "${STEP_OUTPUT_LOG}"

    # printf "%s\n" "----------------------------------------------------------------------" >> "${STEP_OUTPUT_LOG}"
    # printf "Run started at ${timestamp} (Job ID: ${job_id})\n" >> "${STEP_OUTPUT_LOG}"
    # printf "%s\n" "----------------------------------------------------------------------" >> "${STEP_OUTPUT_LOG}"
}

export -f log_info
export -f log_error
export -f log_debug
export -f log_separator