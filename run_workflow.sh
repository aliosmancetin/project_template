#!/bin/bash

# Define variables
PROJDIR="$(cd "$(dirname "$0")" && pwd)"
WORKFLOW_DIR="${PROJDIR}/workflow"
LOG_FILE="${PROJDIR}/workflow.log"

declare -A STEP_JOB_IDS         # Associative array to track step names and their SLURM job IDs
declare -A STEP_DEPENDENCIES    # Associative array to track step dependencies
declare -a STEP_ORDER           # Indexed array to maintain the order of steps
declare -A JOB_IDS_BY_STEP_NUMBER  # To track job IDs by step number
STANDALONE_MODE=false           # Default to SLURM-based execution

# Save original command-line arguments
ORIGINAL_ARGS=("$@")

# Logging functions
log_action() {
    local level=$1
    shift

    if [[ "${level}" == "DEBUG" && "${DEBUG_MODE}" != "true" ]]; then
        # If level is DEBUG and DEBUG_MODE is not true, do not log
        return
    fi

    printf "%s [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "${level}" "$*" >> "${LOG_FILE}"
}

# Log the headline for the run
log_run_start() {

    {
        printf "%s\n" "---------------------------------------------------------------------------------------"
        printf "Run started at %s (Command: %s %s)\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$0" "${ORIGINAL_ARGS[*]}"
        printf "%s\n" "---------------------------------------------------------------------------------------"
    } >> "${LOG_FILE}"
    
}

# parse_workflow_config_file: read workflow.config (if present) and store in an assoc array
parse_workflow_config_file() {
    declare -gA workflow_config_values  # global assoc array to store parsed step.config
    workflow_config_values=( )          # reset/clear each time

    local workflow_config_file
    workflow_config_file="${WORKFLOW_DIR}/workflow.config"
    if [[ -f "${workflow_config_file}" ]]; then
        # Read the file line by line
        while IFS="=" read -r key value; do
            [[ -z "${key}" || "${key}" == "#"* ]] && continue
            
            # Check for aliases and map them to their canonical forms
            case "${key}" in
                "-e")
                    key="--engine"
                    ;;
            esac

            workflow_config_values["$key"]="${value}"
        done < "${workflow_config_file}"

        log_action "DEBUG" "[parse_workflow_config_file] Found workflow.config in ${WORKFLOW_DIR}"
    else
        log_action "DEBUG" "[parse_workflow_config_file] No workflow.config found in ${WORKFLOW_DIR}; using defaults."
    fi

    # Provide defaults if not specified
    if [[ -z "${workflow_config_values["--engine"]}" ]]; then
        workflow_config_values["--engine"]="slurm"
    fi
    
    # Expand this in future if we add more step.config parameters

    # Log
    log_action "DEBUG" "workflow.config options in associative array: $(for key in "${!workflow_config_values[@]}"; do printf "\n%s=%s" "${key}" "${workflow_config_values[$key]}" ; done)"

}

# Parse and list workflow steps, sorted numerically
list_steps() {
    find "${WORKFLOW_DIR}" -maxdepth 1 -mindepth 1 -type d -printf "%P\n" | \
    grep -E '^[0-9]+_' | \
    sort -t'_' -k1,1n -k2 | \
    awk -v dir="${WORKFLOW_DIR}" '{print dir "/" $0}'
}

# Validate a step number against available workflow steps
validate_step() {
    local step=$1
    local available_steps
    available_steps=$(list_steps | awk -F '/' '{print $NF}' | cut -d'_' -f1 | sort -u)
    echo "$available_steps" | grep -xq "$step"
    return $?
}

# Construct the job submission script name from the step directory
get_submit_script() {
    local step_dir=$1
    # local script_name
    # script_name=$(basename "$step_dir" | cut -d'_' -f2-)
    # echo "$script_name.sh"
    echo "submit_script.sh"
}


get_step_config() {
    local step_dir=$1
    # local config_name
    # config_name=$(basename "$step_dir" | cut -d'_' -f2-)
    # echo "$config_name.config"
    echo "${step_dir}/step.config"
}


# parse_step_config_file: read step.config (if present) and store in an assoc array
parse_step_config_file() {
    local step_dir="$1"
    declare -gA step_config_values  # global assoc array to store parsed step.config
    step_config_values=( )          # reset/clear each time

    local step_config_file
    step_config_file=$(get_step_config "${step_dir}")
    if [[ -f "${step_config_file}" ]]; then
        # Read the file line by line
        while IFS="=" read -r key value; do
            [[ -z "${key}" || "${key}" == "#"* ]] && continue
            
            # Check for aliases and map them to their canonical forms
            case "${key}" in
                "-m")
                    key="--mode"
                    ;;
                "-f")
                    key="--array-input-file"
                    ;;
                "-t")
                    key="--type"
                    ;;
            esac

            step_config_values["$key"]="${value}"
        done < "${step_config_file}"

        log_action "DEBUG" "[parse_step_config_file] Found step.config in ${step_dir}"
    else
        log_action "DEBUG" "[parse_step_config_file] No step.config found in ${step_dir}; using defaults."
    fi

    # Provide defaults if not specified
    if [[ -z "${step_config_values["--type"]}" ]]; then
        step_config_values["--type"]="task"
    fi

    if [[ -z "${step_config_values["--mode"]}" ]]; then
        step_config_values["--mode"]="single"
    fi
    
    # Expand this in future if we add more step.config parameters

    # Log
    log_action "DEBUG" "${step_dir} step.config options related to workflow in associative array: $(for key in "${!step_config_values[@]}"; do printf "\n%s=%s" "${key}" "${step_config_values[$key]}" ; done)"

}



# parse_array_job: decide the --array spec based on array_input_file, completed.log, failed.log
parse_array_job() {
    local step_dir="$1"
    
    # Identify the step name for logging
    local step_name
    step_name="$(basename "${step_dir}")"

    # 1) Retrieve array_input_file from step.config
    local array_input_file="${step_config_values["--array-input-file"]}"

    # If array_input_file is empty, abort
    if [[ -z "${array_input_file}" ]]; then
        log_action "ERROR" "[parse_array_job | ${step_name}] No array_input_file specified for array job in ${step_dir}"
        echo ""
        return 1
    else
        # If the array_input_file is relative, interpret it relative to $PROJDIR
        [[ "${array_input_file}" != /* ]] && array_input_file="${PROJDIR}/${array_input_file}"
        if [[ ! -f "${array_input_file}" ]]; then
            log_action "ERROR" "[parse_array_job | ${step_name}] array_input_file '${array_input_file}' does not exist"
            echo ""
            return 1
        fi
    fi

    # 2) Check logs: completed.log, failed.log
    local completed_log="${step_dir}/logs/input_logs/completed.log"
    local failed_log="${step_dir}/logs/input_logs/failed.log"

    # 3) FIRST RUN if logs do not exist at all
    if [[ ! -f "${completed_log}" && ! -f "${failed_log}" ]]; then
        local total_lines
        total_lines=$(wc -l < "${array_input_file}")
        if (( total_lines == 0 )); then
            log_action "ERROR" "[parse_array_job | ${step_name}] array_input_file is empty, aborting."
            echo ""
            return 1
        fi
        log_action "INFO" "[parse_array_job | ${step_name}] First run: array=1-${total_lines}"
        echo "1-${total_lines}"
        return 0
    fi

    # 4) PARTIAL logs exist
    local lines_file_list
    lines_file_list=$(wc -l < "${array_input_file}")
    if (( lines_file_list == 0 )); then
        log_action "ERROR" "[parse_array_job | ${step_name}] array_input_file is empty, aborting."
        echo ""
        return 1
    fi

    # read them as zero if missing
    local lines_completed=0
    local lines_failed=0

    # If only failed.log exists => create a new completed.log from lines not in failed.log
    if [[ ! -f "${completed_log}" && -f "${failed_log}" ]]; then
        lines_failed=$(wc -l < "${failed_log}")
        if (( lines_failed == 0 )); then
            log_action "ERROR" "[parse_array_job | ${step_name}] failed.log is empty but we are re-running, abort."
            echo ""
            return 1
        fi

        log_action "INFO" "[parse_array_job | ${step_name}] Only failed.log present. Creating a new completed.log with all other lines."

        mkdir -p "$(dirname "${completed_log}")"
        : > "${completed_log}"  # empty out (or create) completed.log

        while IFS="" read -r line_original; do
            [[ -z "${line_original}" ]] && continue
            # If line_original isn't in failed.log, we treat it as completed
            if ! grep -xFq "${line_original}" "${failed_log}"; then
                echo "${line_original}" >> "${completed_log}"
            fi
        done < "${array_input_file}"

        log_action "INFO" "[parse_array_job | ${step_name}] completed.log created. Now proceeding as if both logs exist."
    fi

    # Re-check lines_completed, lines_failed if we just created completed.log
    if [[ -f "${completed_log}" ]]; then
        lines_completed=$(wc -l < "${completed_log}")
    fi
    if [[ -f "${failed_log}" ]]; then
        lines_failed=$(wc -l < "${failed_log}")
    fi

    # sum check
    local sum_logs=$((lines_completed + lines_failed))
    if (( sum_logs < lines_file_list )); then
        log_action "INFO" "[parse_array_job | ${step_name}] n_completed + n_failed < n_array_input_file, so also run incomplete lines"
    elif (( sum_logs > lines_file_list )); then
        log_action "ERROR" "[parse_array_job | ${step_name}] Sum of completed + failed logs exceeds lines in array_input_file -> mismatch, aborting."
        echo ""
        return 1
    fi

    # 4.2 If only completed.log exists now (and no failed.log)
    if [[ -f "${completed_log}" && ! -f "${failed_log}" ]]; then
        if (( lines_completed == lines_file_list )); then
            log_action "INFO" "[parse_array_job | ${step_name}] All lines completed but re-run triggered => skipping step."
            echo ""  # Return empty array spec
            return 0
        fi
        local array_indices=()
        local line_no=0
        while IFS="" read -r line_original; do
            ((line_no++))
            if ! grep -xFq "${line_original}" "${completed_log}"; then
                array_indices+=("${line_no}")
            fi
        done < "${array_input_file}"

        if ((${#array_indices[@]} == 0)); then
            log_action "ERROR" "[parse_array_job | ${step_name}] No incomplete lines found, possibly mismatch. Aborting."
            echo ""
            return 1
        fi
        local array_spec
        array_spec=$(IFS=','; echo "${array_indices[*]}")
        log_action "INFO" "[parse_array_job | ${step_name}] Re-run for incomplete lines: ${array_spec}"
        echo "${array_spec}"
        return 0
    fi

    # 4.3 If both logs exist
    if [[ -f "${completed_log}" && -f "${failed_log}" ]]; then
        if (( lines_failed == 0 && lines_completed == lines_file_list )); then
            log_action "INFO" "[parse_array_job | ${step_name}] All lines completed, no failures => skipping step."
            echo ""  # Return empty array spec
            return 0
        fi

        if (( sum_logs < lines_file_list )); then
            log_action "INFO" "[parse_array_job | ${step_name}] Some lines never got run, including them as well."
        fi

        local array_indices=()

        # A) handle lines in failed.log
        while IFS="" read -r line_failed; do
            [[ -z "${line_failed}" ]] && continue
            local grep_output
            grep_output=$(grep -n -xF "${line_failed}" "${array_input_file}")
            if [[ -z "$grep_output" ]]; then
                log_action "ERROR" "[parse_array_job | ${step_name}] failed line '${line_failed}' not found in array_input_file"
                echo ""
                return 1
            fi
            local line_index
            line_index=$(echo "${grep_output}" | head -n1 | cut -d: -f1)
            array_indices+=("${line_index}")
        done < "${failed_log}"

        # B) handle incomplete lines (not in completed.log or failed.log)
        if (( sum_logs < lines_file_list )); then
            local line_no=0
            while IFS="" read -r line_original; do
                ((line_no++))
                if ! grep -xFq "${line_original}" "${completed_log}" && \
                   ! grep -xFq "${line_original}" "${failed_log}"; then
                    array_indices+=("${line_no}")
                fi
            done < "${array_input_file}"
        fi

        if ((${#array_indices[@]} == 0)); then
            log_action "ERROR" "[parse_array_job | ${step_name}] No lines found to re-run. Possibly mismatch? Aborting."
            echo ""
            return 1
        fi

        readarray -t unique_sorted < <(printf "%s\n" "${array_indices[@]}" | sort -n | uniq)
        local array_spec
        array_spec=$(IFS=','; echo "${unique_sorted[*]}")

        log_action "INFO" "[parse_array_job | ${step_name}] Re-run lines: ${array_spec}"

        # Rename failed.log
        if [[ -s "${failed_log}" ]]; then
            local timestamp
            timestamp=$(date "+%Y%m%d%H%M%S")
            local backup_failed_log="${failed_log%.log}_${timestamp}.log"
            mv "${failed_log}" "${backup_failed_log}"
            log_action "INFO" "[parse_array_job | ${step_name}] Renamed old failed.log to: ${backup_failed_log}"
        fi

        echo "${array_spec}"
        return 0
    fi

    # If we somehow get here
    log_action "ERROR" "[parse_array_job | ${step_name}] Unhandled scenario for partial logs."
    echo ""
    return 1
}


# This function submits a short SLURM job that, after the original job completes,
# runs the 'seff' command to report on its efficiency. The seff job is submitted with
# dependency on the original job and writes its output to the step's logs directory.
query_job_metadata() {
    local job_id="$1"       # The original job ID
    local job_name="$2"     # The job's name (used to name the .eff file)
    local step_dir="$3"     # The step directory where logs are stored
    local log_dir="${step_dir}/logs"

    # Ensure that the logs directory exists
    # mkdir -p "${log_dir}"

    # Define the output file for seff's output
    local meta_log="${log_dir}/${job_name}.meta.log"

    # Submit the seff job.
    # It uses a dependency to run only after the original job completes successfully.
    # The job is given minimal resource requests since seff is very lightweight.
    meta_job_id=$(
        sbatch \
        --parsable --kill-on-invalid-dep=yes \
        --dependency=afterok:"${job_id}" \
        --mem=100M --time=00:01:00 \
        --job-name="${job_name}_seff" \
        --output="${meta_log}" \
        --wrap="{
            seff ${job_id};
            sacct --format=JobID,JobName,Submit,Start,Elapsed,End,AllocNodes,ReqTRES%100,ReqNodes,ReqCPUS,ReqMem,TRESUsageInTot%100,CPUTime,MaxRSS,MaxVMSize,MaxDiskRead,MaxDiskWrite --units=G --jobs ${job_id}
        }"
    )

    if [[ -n "${meta_job_id}" ]]; then
        log_action "INFO" "Submitted meta job for ${job_name} with job ID ${meta_job_id} (dependency on ${job_id})."
    else
        log_action "ERROR" "Failed to submit meta job for ${job_name} (dependency on ${job_id})."
    fi
}



# Submit jobs with SLURM dependency management
submit_job() {
    local step_dir=$1
    local dependency=$2
    shift 2
    local cli_args=("$@")
    local submit_script
    submit_script=$(get_submit_script "${step_dir}")
    local step_name
    step_name=$(basename "${step_dir}")
    local job_name
    job_name=$(echo "${step_name}" | cut -d'_' -f2-)

    if [[ ! -f "${step_dir}/${submit_script}" ]]; then
        log_action "ERROR" "Job submission script not found: ${step_dir}/${submit_script}"
        JOB_ID=""
        return 1
    fi

    # 1. Parse step.config, store in step_config_values
    parse_step_config_file "${step_dir}"

    # Extract the type and mode of the step
    local step_type="${step_config_values["--type"]}"
    local step_mode="${step_config_values["--mode"]}"

    STEP_TYPE="${step_type}"
    STEP_MODE="${step_mode}"

    # 2. Prepare dependency option
    local dependency_option=""
    if [[ -n "${dependency}" ]]; then
        dependency_option="--dependency=afterok:${dependency}"
    fi

    # Initialize sbatch command variables
    local sbatch_cmd
    local job_id=""

    pushd "${step_dir}" > /dev/null || exit 1

    # Handle different step types
    if [[ "${step_type}" == "pipeline" ]]; then
        # ##### Pipeline Step Handling #####

        # Construct sbatch command for pipeline
        sbatch_cmd="sbatch --parsable --kill-on-invalid-dep=yes ${dependency_option} --job-name=${job_name}"

        # Submit the pipeline job
        job_id=$($sbatch_cmd "${submit_script}" "${cli_args[@]}" 2>> "${LOG_FILE}")
        local sbatch_exit_code=$?

        popd > /dev/null || exit 1

        if [[ ${sbatch_exit_code} -ne 0 || -z "${job_id}" ]]; then
            log_action "ERROR" "Failed to submit pipeline job for step ${step_name}"
            JOB_ID=""
            return 1
        else
            STEP_JOB_IDS["${step_name}"]="${job_id}"
            if [[ -n "$dependency" ]]; then
                STEP_DEPENDENCIES["${step_name}"]="${dependency}"
            fi
            if [[ ! " ${STEP_ORDER[*]} " == *"${step_name}"* ]]; then
                STEP_ORDER+=("${step_name}")
            fi
            JOB_ID="${job_id}"

            if [[ -n "${dependency}" ]]; then
                log_action "INFO" "Pipeline step ${step_name} submitted with job ID ${job_id} (Dependency: Job ID(s) ${dependency})"
            else
                log_action "INFO" "Pipeline step ${step_name} submitted with job ID ${job_id}"
            fi

            # Submit a meta job to query job metadata
            query_job_metadata "${job_id}" "${job_name}" "${step_dir}"
        fi

    elif [[ "${step_type}" == "task" && "${step_mode}" == "array" ]]; then
        # ##### Task Step with Array Mode #####

        array_spec=$(parse_array_job "${step_dir}")
        if [[ $? -ne 0 ]]; then
            # parse_array_job encountered an error
            JOB_ID=""
            popd > /dev/null || exit 1
            return 1
        fi

        # If array_spec is empty => skip
        if [[ -z "${array_spec}" ]]; then
            log_action "INFO" "Step ${step_name} has no lines to run (already completed). Skipping submission."
            JOB_ID=""
            popd > /dev/null || exit 1
            return 0
        fi

        sbatch_cmd="sbatch --parsable --kill-on-invalid-dep=yes ${dependency_option} --job-name=${job_name} --array=${array_spec}"

        # Final submission
        job_id=$($sbatch_cmd "${submit_script}" "${cli_args[@]}" 2>> "${LOG_FILE}")
        local sbatch_exit_code=$?
        popd > /dev/null || exit 1

        if [[ ${sbatch_exit_code} -ne 0 || -z "${job_id}" ]]; then
            log_action "ERROR" "Failed to submit job for step ${step_name}"
            JOB_ID=""
            return 1
        else
            STEP_JOB_IDS["${step_name}"]="${job_id}"
            if [[ -n "$dependency" ]]; then
                STEP_DEPENDENCIES["${step_name}"]="${dependency}"
            fi
            if [[ ! " ${STEP_ORDER[*]} " == *"${step_name}"* ]]; then
                STEP_ORDER+=("${step_name}")
            fi
            JOB_ID="${job_id}"

            if [[ -n "${dependency}" ]]; then
                log_action "INFO" "Step ${step_name} submitted with job ID ${job_id} (Dependency: Job ID(s) ${dependency})"
            else
                log_action "INFO" "Step ${step_name} submitted with job ID ${job_id}"
            fi

            # Submit a meta job to query job metadata
            query_job_metadata "${job_id}" "${job_name}" "${step_dir}"
        fi

    elif [[ "${step_type}" == "task" && "${step_mode}" == "single" ]]; then
        # ##### Task Step with Single Mode #####

        sbatch_cmd="sbatch --parsable --kill-on-invalid-dep=yes ${dependency_option} --job-name=${job_name}"

        # Final submission
        job_id=$($sbatch_cmd "${submit_script}" "${cli_args[@]}" 2>> "${LOG_FILE}")
        local sbatch_exit_code=$?
        popd > /dev/null || exit 1

        if [[ ${sbatch_exit_code} -ne 0 || -z "${job_id}" ]]; then
            log_action "ERROR" "Failed to submit job for step ${step_name}"
            JOB_ID=""
            return 1
        else
            STEP_JOB_IDS["${step_name}"]="${job_id}"
            if [[ -n "$dependency" ]]; then
                STEP_DEPENDENCIES["${step_name}"]="${dependency}"
            fi
            if [[ ! " ${STEP_ORDER[*]} " == *"${step_name}"* ]]; then
                STEP_ORDER+=("${step_name}")
            fi
            JOB_ID="${job_id}"

            if [[ -n "${dependency}" ]]; then
                log_action "INFO" "Step ${step_name} submitted with job ID ${job_id} (Dependency: Job ID(s) ${dependency})"
            else
                log_action "INFO" "Step ${step_name} submitted with job ID ${job_id}"
            fi
            
            # Submit a meta job to query job metadata
            query_job_metadata "${job_id}" "${job_name}" "${step_dir}"
        fi
    fi
}




# Run jobs standalone (without SLURM)
run_standalone() {
    local step_dir="$1"
    local dependency="$2"
    shift 2
    local cli_args=("$@")
    local submit_script
    submit_script=$(get_submit_script "${step_dir}")
    local step_name
    step_name=$(basename "${step_dir}")

    # 1. Parse step.config, store in step_config_values
    parse_step_config_file "${step_dir}"

    # Extract the type and mode of the step
    local step_type="${step_config_values["--type"]}"
    local step_mode="${step_config_values["--mode"]}"

    if [[ ! -f "${step_dir}/${submit_script}" ]]; then
        log_action "ERROR" "Job script not found: ${step_dir}/${submit_script}"
        return 1
    fi

    # Run the script directly
    pushd "${step_dir}" > /dev/null || exit 1

    # Handle different step types
    if [[ "${step_type}" == "pipeline" ]]; then
        # ##### Pipeline Step Handling #####

        # For pipeline steps, assume the submit_script is designed to handle pipeline execution.
        log_action "INFO" "Running pipeline step for ${step_name}"

        (
            if [[ -n "${dependency}" ]]; then
                IFS=':' read -ra pid_array <<< "${dependency}"
                for pid in "${pid_array[@]}"; do
                    log_action "INFO" "Step ${step_name} waiting for PID: ${pid} (polling)"
                    while kill -0 "${pid}" 2>/dev/null; do
                        sleep 1
                    done
                done
            fi

            bash "${submit_script}" "${cli_args[@]}"
        ) &
        local pid=$!

        popd > /dev/null || exit 1

        STEP_JOB_IDS["$step_name"]="${pid}"
        [[ -n "$dependency" ]] && STEP_DEPENDENCIES["$step_name"]="$dependency"
        [[ ! " ${STEP_ORDER[*]} " == *"${step_name}"* ]] && STEP_ORDER+=("${step_name}")
        JOB_ID="${pid}"

        if [[ -n "${dependency}" ]]; then
            log_action "INFO" "Pipeline step ${step_name} launched in background with PID: ${pid} (Dependency: PID(s) ${dependency})"
        else
            log_action "INFO" "Pipeline step ${step_name} launched in background with PID: ${pid}"
        fi

    elif [[ "${step_type}" == "task" && "${step_mode}" == "array" ]]; then
        # ##### Task Step with Array Mode #####

        array_spec=$(parse_array_job "${step_dir}")
        if [[ $? -ne 0 ]]; then
            # parse_array_job encountered an error
            popd > /dev/null || exit 1
            return 1
        fi

        # If array_spec is empty => skip
        if [[ -z "${array_spec}" ]]; then
            log_action "INFO" "Step ${step_name} has no lines to run (already completed). Skipping submission."
            popd > /dev/null || exit 1
            return 0
        else
            log_action "INFO" "Running standalone script for step ${step_name} (step_mode=${step_mode})"
            (
                if [[ -n "${dependency}" ]]; then
                    IFS=':' read -ra pid_array <<< "${dependency}"
                    for pid in "${pid_array[@]}"; do
                        log_action "INFO" "Step ${step_name} waiting for PID: ${pid} (polling)"
                        while kill -0 "${pid}" 2>/dev/null; do
                            sleep 1
                        done
                    done
                fi

                bash "${submit_script}" "${cli_args[@]}"
            ) &
            local pid=$!

            popd > /dev/null || exit 1

            STEP_JOB_IDS["$step_name"]="${pid}"
            [[ -n "$dependency" ]] && STEP_DEPENDENCIES["$step_name"]="$dependency"
            [[ ! " ${STEP_ORDER[*]} " == *"${step_name}"* ]] && STEP_ORDER+=("${step_name}")
            JOB_ID="${pid}"

            if [[ -n "${dependency}" ]]; then
                log_action "INFO" "Step ${step_name} launched in background with PID: ${pid} (Dependency: PID(s) ${dependency})"
            else
                log_action "INFO" "Step ${step_name} launched in background with PID: ${pid}"
            fi
        fi
    elif [[ "${step_type}" == "task" && "${step_mode}" == "single" ]]; then
        # ##### Task Step with Single Mode #####

        log_action "INFO" "Running standalone script for step ${step_name}"
        (
            if [[ -n "${dependency}" ]]; then
                IFS=':' read -ra pid_array <<< "${dependency}"
                for pid in "${pid_array[@]}"; do
                    log_action "INFO" "Step ${step_name} waiting for PID: ${pid} (polling)"
                    while kill -0 "${pid}" 2>/dev/null; do
                        sleep 1
                    done
                done
            fi

            bash "${submit_script}" "${cli_args[@]}"
        ) &
        local pid=$!

        popd > /dev/null || exit 1

        STEP_JOB_IDS["$step_name"]="${pid}"
        [[ -n "$dependency" ]] && STEP_DEPENDENCIES["$step_name"]="$dependency"
        [[ ! " ${STEP_ORDER[*]} " == *"${step_name}"* ]] && STEP_ORDER+=("${step_name}")
        JOB_ID="${pid}"

        if [[ -n "${dependency}" ]]; then
            log_action "INFO" "Step ${step_name} launched in background with PID: ${pid} (Dependency: PID(s) ${dependency})"
        else
            log_action "INFO" "Step ${step_name} launched in background with PID: ${pid}"
        fi
    fi
}




# Log the command and run start
log_run_start

# Parse command-line arguments
START_STEP=""
END_STEP=""
SPECIFIC_STEPS=()
RUN_FULL_WORKFLOW=false
DEFAULT_RUN=true
declare -A cli_arguments
declare -A arg_mappings=(
    ["--config"]="--config"
    ["-c"]="--config"
)
parse_workflow_config_file

# Workflow config engine option, if engine is specified as standalone, STANDALONE_MODE should be true.
# This is overridden by the --standalone flag even if engine is slurm in the config
# To do: for now, submit_job only supports slurm, in future more engines can be added
# If more engines are added, logic should be arranged to check for the engine type, now it only checks for standalone
if [[ "${workflow_config_values["--engine"]}" == "standalone" ]]; then
    STANDALONE_MODE=true
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --run-full-workflow)
            RUN_FULL_WORKFLOW=true
            DEFAULT_RUN=false
            ;;
        --start)
            START_STEP="$2"
            DEFAULT_RUN=false
            shift
            ;;
        --end)
            END_STEP="$2"
            DEFAULT_RUN=false
            shift
            ;;
        --steps)
            IFS=',' read -ra SPECIFIC_STEPS <<< "$2"
            DEFAULT_RUN=false
            shift
            ;;
        --engine)
            workflow_config_values["--engine"]="$2"
            ;;
        --standalone)
            workflow_config_values["--engine"]="standalone"
            STANDALONE_MODE=true
            ;;
        [0-9]*)
            # Optionally check if the argument is all digits:
            if [[ $1 =~ ^[0-9]+$ ]]; then
                SPECIFIC_STEPS=("$1")
                DEFAULT_RUN=false
            else
                printf "Unknown option: %s\n" "$1"
                exit 1
            fi
            ;;
        --*=*|-*=*)
            key="${1%%=*}"
            value="${1#*=}"
            normalized_key="${arg_mappings[$key]:-$key}"
            cli_arguments["$normalized_key"]="$value"
            shift
            ;;
        *)
            printf "Unknown option: %s\n" "$1"
            exit 1
            ;;
    esac
    shift
done

# Initialize an index array to hold the arguments
cli_args=()

# Iterate over the associative array and construct arguments
for key in "${!cli_arguments[@]}"; do
    cli_args+=("${key}=${cli_arguments[$key]}")
done


# Convert START_STEP and END_STEP to decimal if set
if [[ -n "$START_STEP" ]]; then
    START_STEP_DEC=$((10#$START_STEP))
fi
if [[ -n "$END_STEP" ]]; then
    END_STEP_DEC=$((10#$END_STEP))
fi

export STANDALONE_MODE

# Log CLI arguments in DEBUG_MODE
log_action "DEBUG" "CLI arguments in associative array: $(for key in "${!cli_arguments[@]}"; do printf "\n%s=%s" "${key}" "${cli_arguments[$key]}" ; done)"
log_action "DEBUG" "CLI arguments in indexed array: $(for key in "${!cli_args[@]}"; do printf "\n%s: %s" "${key}" "${cli_args[$key]}" ; done)"

# Validate steps
if [[ -n "${START_STEP_DEC}" ]]; then
    validate_step "${START_STEP}" || {
        log_action "ERROR" "Specified start step ${START_STEP} does not exist in the workflow."
        exit 1
    }
fi

if [[ -n "${END_STEP_DEC}" ]]; then
    validate_step "${END_STEP}" || {
        log_action "ERROR" "Specified end step ${END_STEP} does not exist in the workflow."
        exit 1
    }
fi

# Workflow execution
if [[ "${DEFAULT_RUN}" == true ]]; then
    # Run the last steps (highest step numbers)
    max_step_number=$(list_steps | awk -F '/' '{print $NF}' | cut -d'_' -f1 | sort -nr | head -n1)
    max_step_number_dec=$((10#$max_step_number))

    for step_dir in $(list_steps); do
        step_number=$(basename "${step_dir}" | cut -d'_' -f1)
        step_number_dec=$((10#$step_number))
        
        if [[ "${step_number_dec}" -eq "${max_step_number_dec}" ]]; then
            if [[ "${STANDALONE_MODE}" == true ]]; then
                run_standalone "${step_dir}" "" "${cli_args[@]}"
            else
                submit_job "${step_dir}" "" "${cli_args[@]}"
            fi
            
            job_id="${JOB_ID}"
            step_type="${STEP_TYPE}"
            step_mode="${STEP_MODE}"
            if [[ -n "${job_id}" ]]; then
                JOB_IDS_BY_STEP_NUMBER["${step_number}"]+="${job_id}:"
            else
                log_action "ERROR" "Job submission failed for ${step_dir}"
            fi
        fi
    done
elif [[ "${RUN_FULL_WORKFLOW}" == true || -n "${START_STEP}" || -n "${END_STEP}" ]]; then
    declare -A JOB_IDS_BY_STEP_NUMBER
    prev_step_number=""
    dependency_str=""

    for step_dir in $(list_steps); do
        step_basename=$(basename "${step_dir}")
        step_name="${step_basename}"

        step_number=$(echo "${step_basename}" | cut -d'_' -f1)
        step_number_dec=$((10#$step_number))

        # Apply start and end step filters
        if [[ -n "${START_STEP_DEC}" && "${step_number_dec}" -lt "${START_STEP_DEC}" ]]; then
            continue
        fi
        if [[ -n "${END_STEP_DEC}" && "${step_number_dec}" -gt "${END_STEP_DEC}" ]]; then
            continue
        fi

        # Update dependency_str if step_number changes
        if [[ "${step_number}" != "${prev_step_number}" ]]; then
            if [[ -n "${prev_step_number}" ]]; then
                # Build dependency_str from previous step's job IDs
                dependencies="${JOB_IDS_BY_STEP_NUMBER[$prev_step_number]}"
                dependencies="${dependencies%:}"
                dependency_str="${dependencies//:/\:}"
            else
                # First step, no dependencies
                dependency_str=""
            fi
            prev_step_number="${step_number}"
        fi

        # Submit or run the job
        if [[ "${STANDALONE_MODE}" == true ]]; then
            run_standalone "${step_dir}" "${dependency_str}" "${cli_args[@]}"
        else
            submit_job "${step_dir}" "${dependency_str}" "${cli_args[@]}"
        fi

        job_id="${JOB_ID}"
        step_type="${STEP_TYPE}"
        step_mode="${STEP_MODE}"
        if [[ -n "${job_id}" ]]; then
            # Store job IDs by their step number
            JOB_IDS_BY_STEP_NUMBER["$step_number"]+="$job_id:"
        else
            log_action "ERROR" "Job submission failed for ${step_name}"
            break
        fi

    done
elif [[ ${#SPECIFIC_STEPS[@]} -gt 0 ]]; then
    # Handle dependencies for specific steps
    declare -A JOB_IDS_BY_STEP_NUMBER
    prev_step_number=""
    dependency_str=""

    # Sort and remove duplicates from SPECIFIC_STEPS
    mapfile -t sorted_steps < <(printf '%s\n' "${SPECIFIC_STEPS[@]}" | sort -n | uniq)

    for step_number in "${sorted_steps[@]}"; do
        # Validate the step
        validate_step "${step_number}" || {
            log_action "ERROR" "Step ${step_number} not found in the workflow."
            continue
        }

        # Update dependency_str if step_number changes
        if [[ "${step_number}" != "${prev_step_number}" ]]; then
            if [[ -n "${prev_step_number}" ]]; then
                # Build dependency_str from previous step's job IDs
                dependencies="${JOB_IDS_BY_STEP_NUMBER[$prev_step_number]}"
                dependencies="${dependencies%:}"
                dependency_str="${dependencies//:/\:}"
            else
                # First step, no dependencies
                dependency_str=""
            fi
            prev_step_number="${step_number}"
        fi

        # Get all step directories matching this step number
        matched_dirs=$(list_steps | grep "/${step_number}_")
        if [[ -z "$matched_dirs" ]]; then
            log_action "ERROR" "Step ${step_number} not found in the workflow."
            continue
        fi

        for step_dir in ${matched_dirs}; do
            step_basename=$(basename "${step_dir}")
            step_name="${step_basename}"

            # Submit or run the job
            if [[ "${STANDALONE_MODE}" == true ]]; then
                run_standalone "${step_dir}" "${dependency_str}" "${cli_args[@]}"
            else
                submit_job "${step_dir}" "${dependency_str}" "${cli_args[@]}"
            fi

            job_id="${JOB_ID}"
            step_type="${STEP_TYPE}"
            step_mode="${STEP_MODE}"
            if [[ -n "${job_id}" ]]; then
                # Store job IDs by their step number
                JOB_IDS_BY_STEP_NUMBER["$step_number"]+="$job_id:"
            else
                log_action "ERROR" "Job submission failed for ${step_name}"
                break
            fi
        done
    done
fi


# Final summary
log_action "INFO" "Workflow execution completed"

if ${STANDALONE_MODE}; then
    log_action "INFO" "Standalone steps summary:"
else
    log_action "INFO" "Submitted steps summary:"
fi

# Debug: Print contents of associative arrays
log_action "DEBUG" "STEP_JOB_IDS contents: ${!STEP_JOB_IDS[*]}"
log_action "DEBUG" "STEP_DEPENDENCIES contents: ${!STEP_DEPENDENCIES[*]}"
log_action "DEBUG" "STEP_ORDER contents: ${STEP_ORDER[*]}"

# Iterate over the STEP_ORDER array to preserve order
for step_name in "${STEP_ORDER[@]}"; do
    job_id="${STEP_JOB_IDS[${step_name}]}"
    dependency="${STEP_DEPENDENCIES[${step_name}]}"
    if [[ -n "${dependency}" ]]; then
        log_action "INFO" "  - ${step_name}: Job ID ${job_id} (Dependency: Job ID(s) ${dependency})"
    else
        log_action "INFO" "  - ${step_name}: Job ID ${job_id}"
    fi
done

# Correct the last log entry
printf "%s\n" "=======================================================================================" >> "$LOG_FILE"
