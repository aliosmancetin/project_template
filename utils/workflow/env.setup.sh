#!/bin/bash


setup_env () {
    # Define STEP_DIR and JOB_NAME
    STEP_DIR="${PWD}"
    JOB_NAME=$(basename "${STEP_DIR}" | cut -d'_' -f2-)
    INTERACTIVE_MODE="${INTERACTIVE_MODE:-false}"

    # Define log files
    # If STANDALONE_MODE is `true`, logs won't be automatically handled by SLURM.
    # We'll define custom error and output logs.
    if [[ "${STANDALONE_MODE,,}" == "true" ]]; then
        mkdir -p "${STEP_DIR}/logs"
        STEP_ERROR_LOG="${STEP_DIR}/logs/${JOB_NAME}.error.log"
        STEP_OUTPUT_LOG="${STEP_DIR}/logs/${JOB_NAME}.output.log"

        if [ -f "${STEP_ERROR_LOG}" ]; then
            rm "${STEP_ERROR_LOG}"
        fi
        touch "${STEP_ERROR_LOG}"

        if [ -f "${STEP_OUTPUT_LOG}" ]; then
            rm "${STEP_OUTPUT_LOG}"
        fi
        touch "${STEP_OUTPUT_LOG}"
    else
        if [ -z "${SLURM_ARRAY_TASK_ID}" ]; then
            STEP_ERROR_LOG="${STEP_DIR}/logs/${SLURM_JOB_NAME}.error.log"
            STEP_OUTPUT_LOG="${STEP_DIR}/logs/${SLURM_JOB_NAME}.output.log"
        else
            STEP_ERROR_LOG="${STEP_DIR}/logs/${SLURM_JOB_NAME}_${SLURM_ARRAY_TASK_ID}.error.log"
            STEP_OUTPUT_LOG="${STEP_DIR}/logs/${SLURM_JOB_NAME}_${SLURM_ARRAY_TASK_ID}.output.log"
        fi
    fi


    if [[ "${#local_arg_mappings[@]}" -eq 0 && "${#accepted_args[@]}" -eq 0 ]]; then
        # Define argument mappings
        declare -A local_arg_mappings=(
            ["--config"]="--config"
            ["-c"]="--config"
        )

        # Define accepted arguments and their default values
        declare -A accepted_args=(
            ["--config"]="both"
        )
    fi

    # Add a separator with timestamp and SLURM Job ID
    log_separator

    # Initialize script environment
    initialize_script_environment

    # Parse command-line arguments with mappings
    parse_cli_arguments local_arg_mappings "$@"

    # Merge CLI arguments with config file values
    log_debug "CLI Args Before Merge: $(for key in "${!cli_args[@]}"; do printf "\n%s=%s" "$key" "${cli_args[$key]}" ; done)"
    log_debug "Config File Values Before Merge: $(for key in "${!config_values[@]}"; do printf "\n%s=%s" "$key" "${config_values[$key]}" ; done)"
    log_debug "Accepted Args Before Merge: $(for key in "${!accepted_args[@]}"; do printf "\n%s=%s" "$key" "${accepted_args[$key]}" ; done)"

    merge_args_with_config accepted_args cli_args config_values
    # log_info "Final arguments: $(for key in "${!accepted_args[@]}"; do printf "\n%s=%s" "$key" "${accepted_args[$key]}" ; done)"
    log_info "Final arguments: $(for key in "${!accepted_args[@]}"; do [[ -n "${accepted_args[$key]}" ]] && printf "\n%s=%s" "${key}" "${accepted_args[$key]}"; done)"


    # Summary variables
    processed_profiles=()
    skipped_items=()



    # Main Execution Logic
    mkdir -p "${PROJ_GUIX_PROFILE_DIR}"


    # Start with `MAIN_PROFILE` if it exists
    if [[ -d "${MAIN_PROFILE}" ]]; then
        log_info "Starting with main profile: $(basename "${MAIN_PROFILE}")"
        if setup_guix_profile "${MAIN_PROFILE}"
        then log_info "Completed: $(basename "${MAIN_PROFILE}")"
        else log_error "Failed: $(basename "${MAIN_PROFILE}")"; return 1
        fi
    fi

    # Iterate over all other directories in `PROJ_GUIX_PROFILE_DESC`
    for profile in "${PROJ_GUIX_PROFILE_DESC}"/*; do
        if [[ "${profile}" == "${MAIN_PROFILE}" ]]; then
            continue
        fi

        if [[ -d "${profile}" ]]; then
            log_info "Processing profile: $(basename "${profile}")"
            if setup_guix_profile "${profile}"
            then log_info "Completed: $(basename "${profile}")"
            else log_error "Failed: $(basename "${profile}")"; return 1
            fi
        else
            log_error "Skipping non-directory: ${profile}"
            skipped_items+=("${profile}")
        fi
    done


    # Check if any mamba description is provided, if any, create mamba envs
    if [[ -d "${PROJ_MAMBA_ENV_DESC}" ]]; then
        for description in "${PROJ_MAMBA_ENV_DESC}"/*; do
            if [[ -d "${description}" ]]; then
                log_info "Processing mamba env: $(basename "${description}")"
                if create_mamba_env "${description}" >>"${STEP_OUTPUT_LOG}" 2>>"${STEP_ERROR_LOG}"
                then log_info "Completed: $(basename "${description}")"
                else log_error "Failed: $(basename "${description}")"; return 1
                fi
            else
                log_error "Skipping non-directory: ${description}"
                skipped_items+=("${description}")
            fi
        done
    fi


    # Check if any micromamba definition is provided, if any, create micromamba containers
    if [[ -d "${PROJ_MICROMAMBA_DEF}" ]]; then
        for definition in "${PROJ_MICROMAMBA_DEF}"/*; do
            if [[ -d "${definition}" ]]; then
                log_info "Processing micromamba definition: $(basename "${definition}")"
                if build_micromamba_container "${definition}" >>"${STEP_OUTPUT_LOG}" 2>>"${STEP_ERROR_LOG}"
                then log_info "Completed: $(basename "${definition}")"
                else log_error "Failed: $(basename "${definition}")"; return 1
                fi
            else
                log_error "Skipping non-directory: ${definition}"
                skipped_items+=("${definition}")
            fi
        done
    fi


    # Produce a summary at the end
    log_info " "
    log_info "Environment Setup Summary:"
    if [[ "${#processed_profiles[@]}" -gt 0 ]]; then
        log_info "Processed Profiles:"
        for profile in "${processed_profiles[@]}"; do
            profile_dir=$(echo "${profile}" | cut -d':' -f1)
            profile_config=$(echo "${profile}" | cut -d':' -f2)
            if [[ ${profile_config} == "mamba_env" || ${profile_config} == "micromamba_def" ]]
            then log_info "  - $(basename "${profile_dir}") (${profile_config}) (${profile_dir})"
            else log_info "  - $(basename "${profile_dir}") (--config=${profile_config}) (${profile_dir})"
            fi
        done
    else log_info "No profiles were processed."
    fi

    if [[ "${#skipped_items[@]}" -gt 0 ]]; then
        log_info "Skipped Items (non-directories):"
        for item in "${skipped_items[@]}"; do
            log_info "  - ${item}"
        done
    fi
    log_info " "
    log_info "Environment setup completed successfully!"



    # Copy necessary files to data folder if copy.sh specified
    if [ -f "copy.sh" ]; then
        log_info "Copying necessary files into data..."
        mkdir -p "${PROJDIR}/data"

        # Run copy.sh
        if bash copy.sh
        then log_info "Necessary files copied to: ${PROJDIR}/data"
        else log_error "Failed to copy necessary files!"; return 1
        fi
    else log_info "No copy.sh found. Skipping file copy."
    fi
    log_info "${JOB_NAME} completed successfully!"
}

export -f setup_env

