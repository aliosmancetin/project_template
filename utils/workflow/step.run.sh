#!/bin/bash


run_script () {
    local script_file="$1"
    shift  # Shift to process optional arguments
    # shellcheck disable=SC2190
    local additional_args=("$@")  # Capture any additional arguments (e.g., -f and its value)

    # Ensure the script file exists
    if [[ ! -f "${script_file}" ]]; then
        log_error "[run_script] Script file not found: ${script_file}"
        return 1
    fi

    # Identify the script type based on the file extension
    case "${script_file}" in
        *.R)
            log_info "[run_script] Running R script: ${script_file} with arguments: ${additional_args[*]}"
            Rscript "${script_file}" "${additional_args[@]}" >>"${STEP_OUTPUT_LOG}" 2>>"${STEP_ERROR_LOG}"
            ;;
        *.py)
            log_info "[run_script] Running Python script: ${script_file} with arguments: ${additional_args[*]}"
            PYTHONPATH="${GUIX_PYTHONPATH}" python3 "${script_file}" "${additional_args[@]}" >>"${STEP_OUTPUT_LOG}" 2>>"${STEP_ERROR_LOG}"
            ;;
        *.sh)
            log_info "[run_script] Running Bash script: ${script_file} with arguments: ${additional_args[*]}"
            bash "${script_file}" "${additional_args[@]}" >>"${STEP_OUTPUT_LOG}" 2>>"${STEP_ERROR_LOG}"
            ;;
        *)
            log_error "[run_script] Unsupported script type for file: ${script_file}"
            return 1
            ;;
    esac

    # Check the status of the last command
    local status=$?
    if [[ ${status} -eq 0 ]]; then
        log_info "[run_script] Script ${script_file} executed successfully."
    else
        log_error "[run_script] Script ${script_file} failed with status ${status}."
    fi

    return ${status}
}


export -f run_script


run_array_job () {
    local step_script="$1"
    local array_input_file="$2"
    shift 2
    # shellcheck disable=SC2190
    local additional_args=("$@")
    log_debug "[run_array_job] array_input_file: ${array_input_file}"

    # Define log files for completed and failed tasks
    local completed_log="${STEP_DIR}/logs/input_logs/completed.log"
    local failed_log="${STEP_DIR}/logs/input_logs/failed.log"
    mkdir -p "${STEP_DIR}/logs/input_logs"

    ###########################################################################
    # STANDALONE MODE
    ###########################################################################
    if [[ "${STANDALONE_MODE,,}" == "true" ]]; then
        log_info "[run_array_job] Running in standalone mode."

        local line_no=0
        local had_failure=0  # track if any sub-job fails

        while IFS= read -r input_line; do
            ((line_no++))
            if [[ -z "$input_line" ]]; then
                log_info "[run_array_job] Skipping empty line (line_no=$line_no) in file list ..."
                continue
            fi

            log_info "[run_array_job] Processing line_no=$line_no: $input_line"
            if run_script "${step_script}" -f "${input_line}" "${additional_args[@]}"; then
                printf "%s\n" "${input_line}" >> "${completed_log}"
                # Optionally echo the line if you capture it in the caller
                echo "${input_line}"
            else
                log_error "[run_array_job] Execution failed for line_no=$line_no: ${input_line}"
                printf "%s\n" "${input_line}" >> "${failed_log}"
                had_failure=1  # Mark that we had a failure
                # Do NOT return here, continue with next line
            fi
        done < "${array_input_file}"

        if (( had_failure == 0 )); then
            log_info "[run_array_job] All array tasks completed successfully in standalone mode."
            return 0
        else
            log_error "[run_array_job] Some tasks failed in standalone mode. See failed.log for details."
            return 1
        fi
    fi


    ###########################################################################
    # SLURM ARRAY JOB MODE
    ###########################################################################
    log_info "[run_array_job] Running in SLURM array job mode."

    # Ensure SLURM_ARRAY_TASK_ID is defined
    if [[ -z "${SLURM_ARRAY_TASK_ID}" ]]; then
        log_error "[run_array_job] SLURM_ARRAY_TASK_ID is not set. This function is intended for SLURM array jobs."
        return 1
    fi

    # Count the total number of lines in the array_input_file
    local total_tasks
    total_tasks=$(wc -l < "${array_input_file}")

    # Ensure SLURM_ARRAY_TASK_ID is within the valid range
    if (( SLURM_ARRAY_TASK_ID <= 0 || SLURM_ARRAY_TASK_ID > total_tasks )); then
        log_error "[run_array_job] SLURM_ARRAY_TASK_ID (${SLURM_ARRAY_TASK_ID}) is out of range (1-${total_tasks})."
        return 1
    fi

    # Get the corresponding input line for this SLURM task
    local input_line
    input_line=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "${array_input_file}")

    if [[ -z "${input_line}" ]]; then
        log_info "[run_array_job] No input line found for SLURM_ARRAY_TASK_ID=${SLURM_ARRAY_TASK_ID}. Skipping ..."
        return 0
    fi

    # Log and process the input line
    log_info "[run_array_job] Processing line for SLURM_ARRAY_TASK_ID=${SLURM_ARRAY_TASK_ID}: ${input_line}"
    if run_script "${step_script}" --input_line "${input_line}" "${additional_args[@]}"; then
        printf "%s\n" "${input_line}" >> "${completed_log}"
        # Echo the line for the caller to capture
        echo "$input_line"
        log_info "[run_array_job] Task for SLURM_ARRAY_TASK_ID=${SLURM_ARRAY_TASK_ID} completed successfully!"
        return 0
    else
        log_error "[run_array_job] Execution failed for input line: ${input_line}"
        printf "%s\n" "${input_line}" >> "${failed_log}"
        # Return a non-zero code to indicate failure
        return 1
    fi
}

export -f run_array_job


