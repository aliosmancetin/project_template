#!/bin/bash

execute_step () {
    # Define STEP_DIR and JOB_NAME
    export STEP_DIR="${PWD}"
    STEP_DIR_BASE=$(basename "${STEP_DIR}")
    INTERACTIVE_MODE="${INTERACTIVE_MODE:-false}"

    # Check if the step name starts with a number
    if [[ "${STEP_DIR_BASE}" =~ ^[0-9]+_ ]]; then
        JOB_NAME="${STEP_DIR_BASE#*_}"  # Remove everything before (and including) the first underscore
    else
        JOB_NAME="${STEP_DIR_BASE}"  # Use the entire name
    fi

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


    if [[ "${#local_arg_mappings[@]}" -eq 0 && "${#step_args[@]}" -eq 0 ]]; then

        # Define argument mappings
        declare -A local_arg_mappings=(
            ["--type"]="type"
            ["-t"]="type"
            ["--config"]="config"
            ["-c"]="config"
            ["--mode"]="mode"
            ["-m"]="mode"
            ["--profile"]="profile"
            ["-p"]="profile"
            ["--directory"]="directory"
            ["-d"]="directory"
            ["--script"]="script"
            ["-s"]="script"
            ["--array-input-file"]="array-input-file"
            ["-f"]="array-input-file"
            ["--mamba-env"]="mamba-env"
            ["-e"]="mamba-env"
        )

        # Define accepted step arguments and their default values
        declare -A default_step_args=(
            ["type"]="task"               # task or pipeline
            ["config"]="guix"             # Relevant for tasks, guix, container, mamba
            ["mode"]="single"             # Relevant for tasks, single or array
            ["profile"]="main_profile"    # Relevant for tasks
            ["directory"]="${PROJDIR}"
            ["script"]=""
            ["array-input-file"]=""
            ["mamba-env"]=""
        )
    fi

    # Add a separator with timestamp and SLURM Job ID
    log_separator

    # Initialize script environment
    initialize_script_environment

    # Parse command-line arguments with mappings
    parse_cli_arguments local_arg_mappings "$@"

    # Merge CLI arguments with config file values
    log_debug "CLI Step Args Before Merge: $(for key in "${!cli_step_args[@]}"; do printf "\n%s=%s" "$key" "${cli_step_args[$key]}" ; done)"
    log_debug "CLI Script Args Before Merge: $(for key in "${!cli_script_args[@]}"; do printf "\n%s=%s" "$key" "${cli_script_args[$key]}" ; done)"
    log_debug "Config Step Args Before Merge: $(for key in "${!config_step_args[@]}"; do printf "\n%s=%s" "$key" "${config_step_args[$key]}" ; done)"
    log_debug "Config Script Args Before Merge: $(for key in "${!config_script_args[@]}"; do printf "\n%s=%s" "$key" "${config_script_args[$key]}" ; done)"

    log_debug "Default Step Args Before Merge: $(for key in "${!default_step_args[@]}"; do printf "\n%s=%s" "$key" "${default_step_args[$key]}" ; done)"

    merge_args_with_config \
        "cli_step_args cli_script_args" \
        "config_step_args config_script_args" \
        "default_step_args default_script_args" \
        "step_args script_args"
    
    log_info "step arguments: $(for key in "${!step_args[@]}"; do [[ -n "${step_args[$key]}" ]] && printf "\n%s=%s" "${key}" "${step_args[$key]}"; done)"
    log_info "script arguments: $(for key in "${!script_args[@]}"; do [[ -n "${script_args[$key]}" ]] && printf "\n%s=%s" "${key}" "${script_args[$key]}"; done)"

    # Paste script_args into --key=value format to forward to the scripts
    # Initialize an index array to hold the arguments
    add_args=()

    # Iterate over the associative array and construct arguments
    for key in "${!script_args[@]}"; do
        add_args+=("--${key}=${script_args[$key]}")
    done

    log_debug "add_args: $(for key in "${!add_args[@]}"; do printf "\n%s: %s" "$key" "${add_args[$key]}" ; done)"

    # Define STEP variables
    STEP_TYPE="${step_args["type"]}"
    STEP_MODE="${step_args["mode"]}"
    STEP_CONFIG="${step_args["config"]}"

    STEP_PROFILE="${step_args["profile"]}"
    STEP_RUN_DIR="${step_args["directory"]}"
    if ! STEP_SCRIPT=$(get_step_script); then
        log_error "Failed to resolve STEP_SCRIPT"
        return 1
    fi

    ARRAY_INPUT_FILE="${step_args["array-input-file"]}"
    MAMBA_ENV="${step_args["mamba-env"]}"

    ##### Main Execution Logic ####
    # Run based on configuration
    case "${STEP_TYPE}" in
        task)
            case "${STEP_CONFIG}" in
                guix)
                    log_info "Running with guix profile: ${STEP_PROFILE}"

                    # Activate profile
                    if ! activate_step_environment "${STEP_CONFIG}" "${STEP_PROFILE}"; then
                        log_error "Failed to activate ${STEP_PROFILE}"
                        return 1
                    fi

                    log_info "Running: $(basename "${STEP_SCRIPT}") ..."

                    if [[ "${STEP_MODE}" == "single" ]]; then
                        # Run STEP_SCRIPT with run_script (single mode)
                        if cd "${STEP_RUN_DIR}"; then
                            if run_script "${STEP_SCRIPT}" "${add_args[@]}"
                            then log_info "$(basename "${STEP_SCRIPT}") completed successfully!"
                            else log_error "$(basename "${STEP_SCRIPT}") failed!"; return 1
                            fi
                        else log_error "Failed to navigate to ${STEP_RUN_DIR}"; return 1
                        fi
                    elif [[ "${STEP_MODE}" == "array" ]]; then
                        # Run STEP_SCRIPT with run_array_job (array mode)
                        if cd "${STEP_RUN_DIR}"; then
                            # Capture returned line(s) from run_array_job, along with status
                            if input_line=$(run_array_job "${STEP_SCRIPT}" "${ARRAY_INPUT_FILE}" "${add_args[@]}"); then
                                # run_array_job may return multiple lines if you're in standalone mode
                                log_info "run_array_job completed successfully."
                                log_debug "Line(s) processed: ${input_line}"
                            else log_error "$(basename "${STEP_SCRIPT}") failed on line: ${input_line}"; return 1
                            fi
                        else log_error "Failed to navigate to ${STEP_RUN_DIR}"; return 1
                        fi
                    fi
                    ;;
                container)
                    log_info "Running with guix container: ${STEP_PROFILE}"

                    # Use container
                    if ! activate_step_environment "${STEP_CONFIG}" "${STEP_PROFILE}"; then
                        log_error "Failed to activate ${STEP_PROFILE}"
                        return 1
                    fi
                    log_info "Running: $(basename "${STEP_SCRIPT}") ..."

                    if [[ "${STEP_MODE}" == "single" ]]; then
                        # Run STEP_SCRIPT with run_script in container (single mode)
                        if {
                            apptainer shell --no-home --cleanenv \
                            --bind "${PROJDIR}" \
                            --bind "${STEP_DIR}" \
                            --bind "${TMPDIR}" \
                            "${GUIX_CONTAINER}" <<EOF
export PROFILE_PATH=\$(for path in \${PATH//:/ }; do case "\$path" in *-profile/bin) printf "%s\\n" "\${path%/bin}"; break ;; esac; done)
export CURL_CA_BUNDLE="\$PROFILE_PATH/etc/ssl/certs/ca-certificates.crt"
cd "${PROJDIR}"
. ./workflow/00_env/env_vars.sh

export STEP_DIR="${STEP_DIR}"
export STEP_SCRIPT="${STEP_SCRIPT}"
export STEP_ERROR_LOG="${STEP_ERROR_LOG}"
export STEP_OUTPUT_LOG="${STEP_OUTPUT_LOG}"
export R_LIBS_USER="${GUIX_CONTAINER_R_LIBS}"
export GUIX_PYTHONPATH="${GUIX_PYTHONPATH:+$GUIX_PYTHONPATH:}${GUIX_CONTAINER_PYTHON_LIBS}"
export PATH="\${PATH}:${GUIX_CONTAINER_PYTHON_LIBS}/bin"

if cd "${STEP_RUN_DIR}"; then
    if run_script "\${STEP_SCRIPT}" "${add_args[@]}"
    then log_info "$(basename "\${STEP_SCRIPT}") completed successfully!"
    else log_error "$(basename "\${STEP_SCRIPT}") failed!"; return 1
    fi
else log_error "Failed to navigate to ${STEP_RUN_DIR}"; return 1

EOF
                        }
                        then log_info "$(basename "${STEP_SCRIPT}") completed successfully!"
                        else log_error "$(basename "${STEP_SCRIPT}") failed!"; return 1
                        fi

                    elif [[ "${STEP_MODE}" == "array" ]]; then
                        # Run STEP_SCRIPT with run_array_job in container (array mode)
                        if {
                            apptainer shell --no-home --cleanenv \
                            --bind "${PROJDIR}" \
                            --bind "${STEP_DIR}" \
                            --bind "${TMPDIR}" \
                            "${GUIX_CONTAINER}" <<EOF
export PROFILE_PATH=\$(for path in \${PATH//:/ }; do case "\$path" in *-profile/bin) printf "%s\\n" "\${path%/bin}"; break ;; esac; done)
export CURL_CA_BUNDLE="\$PROFILE_PATH/etc/ssl/certs/ca-certificates.crt"
cd "${PROJDIR}"
. ./workflow/00_env/env_vars.sh

export STEP_DIR="${STEP_DIR}"
export SLURM_ARRAY_TASK_ID="${SLURM_ARRAY_TASK_ID}"
export STEP_SCRIPT="${STEP_SCRIPT}"
export STEP_ERROR_LOG="${STEP_ERROR_LOG}"
export STEP_OUTPUT_LOG="${STEP_OUTPUT_LOG}"
export ARRAY_INPUT_FILE="${ARRAY_INPUT_FILE}"
export R_LIBS_USER="${GUIX_CONTAINER_R_LIBS}"
export GUIX_PYTHONPATH="${GUIX_PYTHONPATH:+$GUIX_PYTHONPATH:}${GUIX_CONTAINER_PYTHON_LIBS}"
export PATH="\${PATH}:${GUIX_CONTAINER_PYTHON_LIBS}/bin"

if cd "${STEP_RUN_DIR}"; then
    # Capture returned line(s) from run_array_job, along with status
    if input_line=\$(run_array_job "\${STEP_SCRIPT}" "\${ARRAY_INPUT_FILE}" "${add_args[@]}")
        # run_array_job may return multiple lines if you're in standalone mode
        log_info "run_array_job completed successfully."
        log_debug "Line(s) processed: ${input_line}"
    else log_error "$(basename "${STEP_SCRIPT}") failed on line: ${input_line}"; return 1
    fi
else log_error "Failed to navigate to ${STEP_RUN_DIR}"; return 1
fi
EOF
                        }
                        then log_info "$(basename "${STEP_SCRIPT}") completed successfully!"
                        else log_error "$(basename "${STEP_SCRIPT}") failed!"; return 1
                        fi
                    fi
                    ;;
                mamba)
                    log_info "Running with mamba environment: ${MAMBA_ENV}"

                    # Activate mamba environment
                    if ! activate_step_environment "${STEP_CONFIG}" "${MAMBA_ENV}"; then
                        log_error "Failed to activate ${MAMBA_ENV}"
                        return 1
                    fi

                    log_info "Running: $(basename "${STEP_SCRIPT}") ..."

                    if [[ "${STEP_MODE}" == "single" ]]; then
                        # Run STEP_SCRIPT with run_script in mamba env (single mode)
                        if cd "${STEP_RUN_DIR}"; then
                            if run_script "${STEP_SCRIPT}" "${add_args[@]}"
                            then log_info "$(basename "${STEP_SCRIPT}") completed successfully!"
                            else log_error "$(basename "${STEP_SCRIPT}") failed!"; return 1
                            fi
                        else log_error "Failed to navigate to ${STEP_RUN_DIR}"; return 1
                        fi
                    elif [[ "${STEP_MODE}" == "array" ]]; then
                        # Run STEP_SCRIPT with run_array_job in mamba env (array mode)
                        if cd "${STEP_RUN_DIR}"; then
                            # Capture returned line(s) from run_array_job, along with status
                            if input_line=$(run_array_job "${STEP_SCRIPT}" "${ARRAY_INPUT_FILE}" "${add_args[@]}"); then
                                # run_array_job may return multiple lines if you're in standalone mode
                                log_info "run_array_job completed successfully."
                                log_debug "Line(s) processed: ${input_line}"
                            else log_error "$(basename "${STEP_SCRIPT}") failed on line: ${input_line}"; return 1
                            fi
                        else log_error "Failed to navigate to ${STEP_RUN_DIR}"; return 1
                        fi
                    fi
                    ;;
                *)
                    log_error "Invalid option to 'config' variable: ${STEP_CONFIG} | 'config' could be 'guix' (default), 'container' or 'mamba'"
                    return 1
                    ;;
            esac
            ;;
        pipeline)
            log_info "Running as a pipeline step!"

            # Run STEP_SCRIPT with run_script (single mode)
            log_info "Running: $(basename "${STEP_SCRIPT}") ..."
            if cd "${STEP_DIR}/pipeline"; then
                if run_script "${STEP_SCRIPT}" "${add_args[@]}"
                then log_info "$(basename "${STEP_SCRIPT}") completed successfully!"
                else log_error "$(basename "${STEP_SCRIPT}") failed!"; return 1
                fi
            else log_error "Failed to navigate to ${STEP_DIR}/pipeline"; return 1
            fi
            ;;
        *)
            log_error "Invalid option to 'type' variable: ${STEP_TYPE} | 'type' could be 'task' (default) or 'pipeline'"
            return 1
            ;;
    esac

    log_info "Step completed successfully!"
}

export -f execute_step



get_step_script () {
    local STEP_SCRIPT

    # If STEP_SCRIPT is not provided, look for a script in the STEP_RUN_DIR
    if [[ -z "${step_args["script"]}" ]]; then
        mapfile -t matching_scripts < <(
            find "${STEP_DIR}" -maxdepth 1 -type f \( -iname "*.R" -o -iname "*.py" -o -iname "*.sh" \) \
                ! -iname "config.yaml" ! -iname "submit_script.sh"
        )

        if [[ ${#matching_scripts[@]} -eq 0 ]]; then
            log_error "No executable script found in ${STEP_DIR} (expecting a .R, .py, or .sh file excluding 'config.yaml' and 'submit_script.sh')."
            return 1
        elif [[ ${#matching_scripts[@]} -gt 1 ]]; then
            log_error "Multiple candidate scripts found in ${STEP_DIR}: ${matching_scripts[*]}"
            return 1
        else
            STEP_SCRIPT="${matching_scripts[0]}"
            log_debug "Identified step script: ${STEP_SCRIPT}"
        fi
    else
        STEP_SCRIPT="${STEP_DIR}"/"${step_args["script"]}"
    fi

    # Check if STEP_SCRIPT is available
    if [ -f "${STEP_SCRIPT}" ]; then
        log_debug "STEP_SCRIPT: ${STEP_SCRIPT}"
        echo "${STEP_SCRIPT}"
    else
        log_error "STEP_SCRIPT ( ${STEP_SCRIPT} ) not found!"
        return 1
    fi
}

export -f get_step_script
