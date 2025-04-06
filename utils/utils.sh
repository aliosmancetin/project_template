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


# Determine the script's directory and derive script-specific details
initialize_script_environment () {
    if [[ "${STANDALONE_MODE,,}" == "true" ]]; then
        script_dir=$(dirname "$(readlink -f "$0")")
        log_info "[initialize_script_environment] Standalone execution detected: ${script_dir}"
    elif [[ -n "${SLURM_SUBMIT_DIR}" ]]; then
        script_dir="${SLURM_SUBMIT_DIR}"
        log_info "[initialize_script_environment] SLURM submission directory detected: ${script_dir}"        
    fi

    # Extract the base name of the directory (e.g., "00_env")
    # step_base=$(basename "$script_dir")
    # script_suffix=$(echo "$step_base" | cut -d'_' -f2-)

    # Dynamically derive the config file name
    config_file="${script_dir}/step.config" # ${script_suffix}.config"
    log_info "[initialize_script_environment] Derived configuration file: ${config_file}"

    # Parse the configuration file
    parse_config_file "${config_file}"
}

export -f initialize_script_environment


# Parse configuration file into an associative array
parse_config_file () {
    local config_file=$1
    declare -gA config_values  # Global associative array

    if [[ -f "${config_file}" ]]; then
        log_info "[parse_config_file] Parsing configuration file: ${config_file}"
        while IFS="=" read -r key value; do
            [[ -z "${key}" || "${key}" == "#"* ]] && continue
            config_values["$key"]="${value}"

            # Check if the step name starts with $
            if [[ "${value}" =~ ^\$ ]]; then
                var_name="${value:1}"  # Remove the leading $
                if [[ -n "${!var_name}" ]]; then  # Check if the variable exists
                    value="${!var_name}"  # Expand the variable
                    config_values["$key"]="${value}"
                fi
            else
                config_values["$key"]="${value}"
            fi
        done < "${config_file}"
    else
        log_info "[parse_config_file] No configuration file found: ${config_file}"
    fi

    # Debug: Confirm parsed config values
    log_debug "[parse_cli_arguments] Parsed Config Values: $(for key in "${!config_values[@]}"; do printf "\n%s=%s" "$key" "${config_values[$key]}" ; done)"
}

export -f parse_config_file


parse_cli_arguments () {
    local -n arg_mappings=$1
    shift
    declare -gA cli_args  # Global associative array

    if [[ -z "${arg_mappings[*]}" ]]; then
        log_info "[parse_cli_arguments] No argument mappings defined. Using raw keys."
    else
        log_debug "[parse_cli_arguments] Argument mappings passed: $(for key in "${!arg_mappings[@]}"; do printf "\n%s=%s" "$key" "${arg_mappings[$key]}" ; done)"
    fi

    # Parse remaining arguments
    while [[ $# -gt 0 ]]; do
    
        # Skip empty arguments
        if [[ -z $1 ]]; then
            shift
            continue
        fi

        case $1 in
            --*=*|-*=*)
                key="${1%%=*}"
                value="${1#*=}"
                normalized_key="${arg_mappings[$key]:-$key}"
                cli_args["$normalized_key"]="$value"
                shift
                ;;
            *)
                log_error "[parse_cli_arguments] Unknown option format: $1"
                exit 1
                ;;
        esac
    done

    # Debug: Confirm parsed CLI arguments
    log_debug "[parse_cli_arguments] Parsed CLI Args: $(for key in "${!cli_args[@]}"; do printf "\n%s=%s" "$key" "${cli_args[$key]}" ; done)"
}

export -f parse_cli_arguments




# Merge command-line arguments with configuration file values
# Command-line arguments take precedence
merge_args_with_config () {
    local -n merge_array=$1     # Name reference for the array to update
    local -n cli_args_values=$2    # Parsed command-line arguments (associative array)
    local -n config_file_values=$3 # Parsed configuration file values (associative array)

    for key in "${!merge_array[@]}"; do
        # Command-line arguments take precedence
        if [[ -n "${cli_args_values[$key]}" ]]; then
            merge_array["$key"]="${cli_args_values[$key]}"
            log_info "[merge_args_with_config] Using command-line argument for: ${key}=${cli_args_values[$key]}"
        # Config file values come next
        elif [[ -n "${config_file_values[$key]}" ]]; then
            merge_array["$key"]="${config_file_values[$key]}"
            log_info "[merge_args_with_config] Using configuration file value for: ${key}=${config_file_values[$key]}"
        # Fallback to default value if non-zero
        elif [[ -n "${merge_array[$key]}" ]]; then
            log_info "[merge_args_with_config] Using default value for: ${key}=${merge_array[$key]}"
        fi
    done

    declare -gA additional_args
    # Populate additional_args with keys in cli_args but not in merge_array
    for key in "${!cli_args[@]}"; do
        if [[ -z "${merge_array[$key]}" ]]; then
            additional_args["$key"]="${cli_args[$key]}"
        fi
    done

    # Initialize an index array to hold the arguments
    add_args=()

    # Iterate over the associative array and construct arguments
    for key in "${!additional_args[@]}"; do
        add_args+=("${key}=${additional_args[$key]}")
    done

    log_debug "[merge_args_with_config] Additional arguments in associative array: $(for key in "${!additional_args[@]}"; do printf "\n%s=%s" "$key" "${additional_args[$key]}" ; done)"
    log_debug "[merge_args_with_config] Additional arguments in indexed array: $(for key in "${!add_args[@]}"; do printf "\n%s: %s" "$key" "${add_args[$key]}" ; done)"
}

export -f merge_args_with_config




# Function to execute setup scripts
setup_guix_profile () {
    local profile_dir=$1
    export profile_dir
    profile_name=$(basename "${profile_dir}")
    log_info "Entering profile directory: ${profile_dir}"

    # Navigate to the profile directory
    pushd "${profile_dir}" > /dev/null || {
        log_error "Failed to navigate to directory: ${profile_dir}"
        return 1
    }

    # Retrieve configuration from accepted_args
    local config
    config="${accepted_args["--config"]}"

    # Run setup scripts based on configuration
    case "${config}" in
        guix)
            log_info "Running create_guix_profile in profile directory..."
            if create_guix_profile "${profile_name}" >>"${STEP_OUTPUT_LOG}" 2>>"${STEP_ERROR_LOG}"; then
                # Add to processed profiles summary
                processed_profiles+=("$profile_dir:$config")
            else log_error "create_guix_profile failed: ${profile_dir}"; return 1
            fi   
            ;;
        container)
            log_info "Running setup_container.sh in profile directory..."
            log_info "Provided config option is 'container'. This means guix is not available in your machine and you want to skip env step and instead you want to use pre-created containers."
            log_info "Please check if you have required containers for the pipeline."
            # create_guix_container "${profile_name}" >>"${STEP_OUTPUT_LOG}" 2>>"${STEP_ERROR_LOG}"
            ;;
        both)
            log_info "Running create_guix_profile and create_guix_container in profile directory..."
            if create_guix_profile "${profile_name}" >>"${STEP_OUTPUT_LOG}" 2>>"${STEP_ERROR_LOG}" && create_guix_container "${profile_name}" >>"${STEP_OUTPUT_LOG}" 2>>"${STEP_ERROR_LOG}"; then
                # Add to processed profiles summary
                processed_profiles+=("$profile_dir:$config")
            else log_error "create_guix_profile or create_guix_container failed: ${profile_dir}"; return 1
            fi   
            ;;
        *)
            log_error "Invalid option to --config variable: ${config} | --config could be 'guix', 'container' or 'both' (default)"
            return 1
            ;;
    esac

    # Return to the original directory
    popd > /dev/null || {
        log_error "Failed to return to the original directory from: ${profile_dir}"
        return 1
    }

    return 0
}

export -f setup_guix_profile


# Normalize function (optimized from your version)
normalize_scm() {
  local input_file="$1"
  local output_file="${2:-/dev/stdout}"

  if [[ ! -f "$input_file" ]]; then
    echo "Error: File '$input_file' not found." >&2
    return 1
  fi

  sed -e 's/;.*//' \
      -e 's/^[[:space:]]*//' \
      -e 's/[[:space:]]*$//' \
      -e '/^$/d' "$input_file" | tr -s '[:space:]' ' ' > "$output_file"
}

export -f normalize_scm

# Cache Guix profile (after successful creation)
cache_guix_profile() {
  local profile_name="$1"
  local profile_desc="${PROJ_GUIX_PROFILE_DESC}/${profile_name}"
  local cache_dir="${PROJDIR}/.proj/.cache/guix_profile_descriptions/${profile_name}"
  mkdir -p "$cache_dir"

  normalize_scm "${profile_desc}/channels.scm" "${cache_dir}/channels.scm"
  normalize_scm "${profile_desc}/manifest.scm" "${cache_dir}/manifest.scm"

  sha256sum "${cache_dir}/channels.scm" | awk '{print $1}' > "${cache_dir}/channels.hash"
  sha256sum "${cache_dir}/manifest.scm" | awk '{print $1}' > "${cache_dir}/manifest.hash"

  log_info "[cache_guix_profile] Cached normalized and hashed files for profile: ${profile_name}"
}

export -f cache_guix_profile

# Check Guix cache: returns 0 if cache is valid (unchanged), 1 otherwise
check_guix_cache() {
  local profile_name="$1"
  local profile_desc="${PROJ_GUIX_PROFILE_DESC}/${profile_name}"
  local cache_dir="${PROJDIR}/.proj/.cache/guix_profile_descriptions/${profile_name}"

  if [[ ! -f "${cache_dir}/channels.hash" || ! -f "${cache_dir}/manifest.hash" ]]; then
    log_info "[check_guix_cache] No cache found for profile: ${profile_name}"
    return 1
  fi

  local temp_dir
  temp_dir=$(mktemp -d)
  normalize_scm "${profile_desc}/channels.scm" "${temp_dir}/channels.scm"
  normalize_scm "${profile_desc}/manifest.scm" "${temp_dir}/manifest.scm"

  local current_channels_hash current_manifest_hash
  current_channels_hash=$(sha256sum "${temp_dir}/channels.scm" | awk '{print $1}')
  current_manifest_hash=$(sha256sum "${temp_dir}/manifest.scm" | awk '{print $1}')

  local cached_channels_hash cached_manifest_hash
  cached_channels_hash=$(cat "${cache_dir}/channels.hash")
  cached_manifest_hash=$(cat "${cache_dir}/manifest.hash")

  rm -rf "$temp_dir"

  if [[ "$current_channels_hash" == "$cached_channels_hash" && "$current_manifest_hash" == "$cached_manifest_hash" ]]; then
    log_info "[check_guix_cache] Cache valid for profile: ${profile_name}. Skipping rebuild."
    return 0
  else
    log_info "[check_guix_cache] Cache mismatch for profile: ${profile_name}. Rebuild required."
    return 1
  fi
}

export -f cache_guix_profile


create_guix_profile () {
    local PROFILE_NAME=$1

    log_info "[create_guix_profile] Setting up: ${PROFILE_NAME}"

    PROFILE_DIR="${PROJ_GUIX_PROFILE_DIR}/${PROFILE_NAME}/${PROFILE_NAME}"
    GUIX_PROFILE="${PROFILE_DIR}"

    # Check cache for guix
    local guix_env_built=false
    if check_guix_cache "${PROFILE_NAME}"; then
        log_info "[create_guix_profile] Skipping Guix profile build for ${PROFILE_NAME}, cache is valid."
    else
        # Build Guix profile (channels + manifest)
        log_info "[create_guix_profile] Cleaning up and creating Guix profile directory: ${PROFILE_DIR}"
        rm -rf "$(dirname "${PROFILE_DIR}")"
        mkdir -p "$(dirname "${PROFILE_DIR}")"

        log_info "[create_guix_profile] Pulling Guix channels and creating profile..."
        if guix pull --channels="channels.scm" --profile="${PROFILE_DIR}"
        then log_info "[create_guix_profile] guix pull executed successfully."
        else log_error "[create_guix_profile] guix pull failed!"; return 1
        fi

        . "${GUIX_PROFILE}/etc/profile"

        if [[ "${DEBUG_MODE,,}" == "true" ]]; then
            guix describe --format=channels -p "${GUIX_PROFILE}" > profile_channels_used.scm
        fi

        log_info "[create_guix_profile] Installing packages from manifest..."
        if guix package --manifest="manifest.scm" --profile="${PROFILE_DIR}"
        then log_info "[create_guix_profile] guix package executed successfully."
        else log_error "[create_guix_profile] guix package failed!"; return 1
        fi

        # Mark Guix env built
        guix_env_built=true
    fi

    # Activate profile
    . "${GUIX_PROFILE}/etc/profile"

    # Cache Guix profile if it was freshly built
    if [[ "${guix_env_built}" == true ]]; then
        cache_guix_profile "${PROFILE_NAME}"
    fi

    # Setup additional Rlibs
    if [ -f "setup_rlibs.R" ]; then
        log_info "[create_guix_profile] Setting up additional R libraries..."
        log_info "[create_guix_profile] Cleaning up and creating additional Rlib directory: ${PROJ_R_LIBS_DIR}/${PROFILE_NAME}"
        rm -rf "${PROJ_R_LIBS_DIR:?}/${PROFILE_NAME}"
        mkdir -p "${PROJ_R_LIBS_DIR}/${PROFILE_NAME}"

        export R_LIBS_USER="${PROJ_R_LIBS_DIR}/${PROFILE_NAME}"

        # Run setup_rlibs.R and handle success or failure
        if Rscript setup_rlibs.R
        then log_info "[create_guix_profile] Additional R libraries installed successfully to: ${R_LIBS_USER}"
        else log_error "[create_guix_profile] Failed to set up additional R libraries."; return 1
        fi
    else log_info "[create_guix_profile] No setup_rlibs.R found. Skipping additional R libraries setup."
    fi


    # Install additional Python libraries with pip install
    if [ -f "setup_python_libs.sh" ]; then
        log_info "[create_guix_profile] Setting up additional Python libraries..."

        export TARGET_DIR="${PROJ_PYTHON_LIBS_DIR}/${PROFILE_NAME}"

        log_info "[create_guix_profile] Cleaning up and creating additional python_libs directory: ${TARGET_DIR}"
        rm -rf "${TARGET_DIR}"
        mkdir -p "${TARGET_DIR}"

        export PYTHONPATH="${PYTHONPATH:+$PYTHONPATH:}${TARGET_DIR}"

        # Run setup_rlibs.R and handle success or failure
        if . setup_python_libs.sh
        then log_info "[create_guix_profile] Additional Python libraries installed successfully to: ${TARGET_DIR}"
        else log_error "[create_guix_profile] Failed to set up additional Python libraries."; return 1
        fi
    else log_info "[create_guix_profile] No setup_python_libs.sh found. Skipping additional Python libraries setup."
    fi

    log_info "[create_guix_profile] Setup completed successfully: ${PROFILE_NAME}"
}

export -f create_guix_profile



activate_guix_profile () {
    local PROFILE_NAME=$1

    # Unset desired variables otherwise they are appended in front of default GUIX_PROFILE
    unset R_LIBS_SITE
    unset R_LIBS_USER
    unset GUIX_PYTHONPATH
    unset JUPYTER_PATH
    unset JUPYTER_CONFIG_PATH

    PROFILE_DESC="${PROJ_GUIX_PROFILE_DESC}/${PROFILE_NAME}"

    export GUIX_PROFILE="${PROJ_GUIX_PROFILE_DIR}/${PROFILE_NAME}/${PROFILE_NAME}"
    . "${GUIX_PROFILE}/etc/profile"

    if [ -f "${PROFILE_DESC}/setup_rlibs.R" ]; then
        export R_LIBS_USER="${PROJ_R_LIBS_DIR}/${PROFILE_NAME}"
    fi

    if [ -f "${PROFILE_DESC}/setup_python_libs.sh" ]; then
        export GUIX_PYTHONPATH="${GUIX_PYTHONPATH:+$GUIX_PYTHONPATH:}${PROJ_PYTHON_LIBS_DIR}/${PROFILE_NAME}"
        export PATH="${PATH}:${PROJ_PYTHON_LIBS_DIR}/${PROFILE_NAME}/bin"
    fi
}

export -f activate_guix_profile



create_guix_container () {
    local PROFILE_NAME=$1
    
    log_info "[create_guix_container] Creating container for: ${PROFILE_NAME}"

    PROFILE_DESC="${PROJ_GUIX_PROFILE_DESC}/${PROFILE_NAME}"
    PROFILE_DIR="${PROJ_GUIX_PROFILE_DIR}/${PROFILE_NAME}/${PROFILE_NAME}"
    CONTAINER_OUTPUT="${PROJ_GUIX_CONTAINER_DIR}/${PROFILE_NAME}"/container.squashfs
    local build_container=false

    # Check if container is already exists and cache is valid
    if [[ -f "${CONTAINER_OUTPUT}" ]]; then
        log_info "[create_guix_container] Container already exists: ${CONTAINER_OUTPUT}"
        if check_guix_cache "${PROFILE_NAME}"; then
            log_info "[create_guix_container] Guix cache is valid. Skipping container creation."
        else 
            log_info "[create_guix_container] Guix cache is invalid. Rebuilding container."
            build_container=true
        fi
    else
        log_info "[create_guix_container] Container does not exist. Building container."
        build_container=true
    fi

    if [[ "${build_container}" == true ]]; then
        
        # Activate profile for guix which specified channels were pulled
        GUIX_PROFILE="${PROFILE_DIR}-1-link"
        . "${GUIX_PROFILE}/etc/profile"

        if [[ "${DEBUG_MODE,,}" == "true" ]]; then
            guix describe --format=channels > container_channels_used.scm
        fi

        # Activate profile
        GUIX_PROFILE="${PROFILE_DIR}"
        . "${GUIX_PROFILE}/etc/profile"

        # Create the container
        log_info "[create_guix_container] Cleaning up and creating container directory: ${PROJ_GUIX_CONTAINER_DIR}/${PROFILE_NAME}"
        rm -rf "${PROJ_GUIX_CONTAINER_DIR:?}/${PROFILE_NAME}"
        mkdir -p "${PROJ_GUIX_CONTAINER_DIR}/${PROFILE_NAME}"
        

        log_info "[create_guix_container] Creating container with guix pack..."
        #-S /bin=bin -S /lib=lib -S /usr=share -S /opt/etc=etc \
        if generated_container=$(guix pack -f squashfs -RR --manifest="manifest.scm")
        then log_info "[create_guix_container] guix pack executed successfully."
        else log_error "[create_guix_container] guix pack failed!"; return 1
        fi


        # Safely copy the generated file
        if [ -f "${generated_container}" ]; then
            cp "${generated_container}" "${CONTAINER_OUTPUT}"
            log_info "[create_guix_container] Container created and copied to: ${CONTAINER_OUTPUT}"
        else
            log_error "[create_guix_container] Generated container file not found: ${generated_container}"
            exit 1
        fi
    fi



    # Use the container to set up Rlibs outside the container
    if [ -f "setup_rlibs.R" ]; then
        log_info "[create_guix_container] Setting up custom R libraries using the container..."
        GUIX_CONTAINER_R_LIBS="${PROJ_GUIX_CONTAINER_DIR}/${PROFILE_NAME}/lib/Rlibs"

        # Create the Rlibs directory in container directory
        log_info "[create_guix_container] Creating additional Rlib directory: ${GUIX_CONTAINER_R_LIBS}"
        rm -rf "${GUIX_CONTAINER_R_LIBS}"
        mkdir -p "${GUIX_CONTAINER_R_LIBS}"

        # Run setup_rlibs.R with the container
        if {
            apptainer shell --no-home --cleanenv \
                --bind "${PROJDIR}" \
                --bind "${TMPDIR}" \
                "${CONTAINER_OUTPUT}" <<EOF
export PROFILE_PATH=\$(for path in \${PATH//:/ }; do case "\$path" in *-profile/bin) printf "%s\\n" "\${path%/bin}"; break ;; esac; done)
export CURL_CA_BUNDLE="\$PROFILE_PATH/etc/ssl/certs/ca-certificates.crt"
cd "${PROJDIR}"
. ./workflow/00_env/env_vars.sh
export PROFILE_DESC="${PROFILE_DESC}"
export R_LIBS_USER="${GUIX_CONTAINER_R_LIBS}"
cd \${PROFILE_DESC}
Rscript setup_rlibs.R
EOF
        }
        then log_info "[create_guix_container] Additional R libraries installed successfully to: ${GUIX_CONTAINER_R_LIBS}"
        else log_error "[create_guix_container] Failed to set up additional R libraries using the container."; exit 1
        fi
    else log_info "[create_guix_container] No setup_rlibs.R found. Skipping additional R libraries setup using the container."
    fi


    # Use the container to set up Python libs outside the container
    if [ -f "setup_python_libs.sh" ]; then
        log_info "[create_guix_container] Setting up custom Python libraries using the container..."
        TARGET_DIR="${PROJ_GUIX_CONTAINER_DIR}/${PROFILE_NAME}/lib/python_libs"

        # Create the python_libs directory in container directory
        log_info "[create_guix_container] Creating additional Python library directory: ${TARGET_DIR}"
        rm -rf "${TARGET_DIR}"
        mkdir -p "${TARGET_DIR}"

        # Run setup_python_libs.sh with the container
        if {
            apptainer shell --no-home --cleanenv \
                --bind "${PROJDIR}" \
                --bind "${TMPDIR}" \
                "${CONTAINER_OUTPUT}" <<EOF
export PROFILE_PATH=\$(for path in \${PATH//:/ }; do case "\$path" in *-profile/bin) printf "%s\\n" "\${path%/bin}"; break ;; esac; done)
export CURL_CA_BUNDLE="\$PROFILE_PATH/etc/ssl/certs/ca-certificates.crt"
cd "${PROJDIR}"
. ./workflow/00_env/env_vars.sh
export PROFILE_DESC="${PROFILE_DESC}"
export TARGET_DIR=${TARGET_DIR}
export GUIX_PYTHONPATH="${GUIX_PYTHONPATH:+$GUIX_PYTHONPATH:}${TARGET_DIR}"
export PYTHONPATH=\${GUIX_PYTHONPATH}
cd \${PROFILE_DESC}
. setup_python_libs.sh
EOF
        }
        then log_info "[create_guix_container] Additional R libraries installed successfully to: ${GUIX_CONTAINER_R_LIBS}"
        else log_error "[create_guix_container] Failed to set up additional R libraries using the container."; exit 1
        fi
    else log_info "[create_guix_container] No setup_python_libs.sh found. Skipping additional Python libraries setup using the container."
    fi

    log_info "[create_guix_container] Container setup completed successfully: ${PROFILE_NAME}"


}

export -f create_guix_container


use_guix_container () {
    local PROFILE_NAME=$1

    PROFILE_DESC="${PROJ_GUIX_PROFILE_DESC}/${PROFILE_NAME}"

    export GUIX_CONTAINER="${PROJ_GUIX_CONTAINER_DIR}/${PROFILE_NAME}/container.squashfs"

    if [ -f "${PROFILE_DESC}/setup_rlibs.R" ]; then
        export GUIX_CONTAINER_R_LIBS="${PROJ_GUIX_CONTAINER_DIR}/${PROFILE_NAME}/lib/Rlibs"
    fi

    if [ -f "${PROFILE_DESC}/setup_python_libs.sh" ]; then
        export GUIX_CONTAINER_PYTHON_LIBS="${PROJ_GUIX_CONTAINER_DIR}/${PROFILE_NAME}/lib/python_libs"
    fi

}

export -f use_guix_container



create_mamba_env () {
    local mamba_env_dir=$1
    ENV_NAME=$(basename "${mamba_env_dir}")

    log_info "Entering mamba env description directory: ${mamba_env_dir}"

    # Navigate to the profile directory
    pushd "${mamba_env_dir}" > /dev/null || {
        log_error "Failed to navigate to directory: ${mamba_env_dir}"
        return 1
    }

    # Create env with mamba
    log_info "[create_mamba_env] Creating with mamba: ${ENV_NAME}"

    ENV_DIR="${PROJ_MAMBA_ENV_DIR}/${ENV_NAME}"

    # Cleanup and create Mamba env directory
    log_info "[create_mamba_env] Cleaning up and creating mamba env directory: ${ENV_DIR}"
    rm -rf "${ENV_DIR}"

    # Create env with mamba
    if mamba env create --file env.yaml --prefix "${ENV_DIR}"; then
        log_info "[create_mamba_env] Mamba env created successfully: ${ENV_NAME}"
        processed_profiles+=("$mamba_env_dir:mamba_env")
    else log_error "[create_mamba_env] Failed to create mamba env: ${ENV_NAME}"; return 1
    fi

    # Return to the original directory
    popd > /dev/null || {
        log_error "Failed to return to the original directory from: ${mamba_env_dir}"
        return 1
    }

    return 0
}

export -f create_mamba_env


activate_mamba_env () {
    local mamba_env=$1

    ENV_DIR="${PROJ_MAMBA_ENV_DIR}/${mamba_env}"

    log_info "[activate_mamba_env] Activating Mamba env: ${mamba_env} ..."
    if {
        # Source the conda.sh script from your miniforge installation
        source "${MINIFORGE3_PATH}/etc/profile.d/conda.sh"
        source "${MINIFORGE3_PATH}/etc/profile.d/mamba.sh"

        # Activate your desired environment using Mamba
        mamba activate "${ENV_DIR}"
    }
    then log_info "[activate_mamba_env] Mamba env ${mamba_env} activated successfully!"; return 0
    else log_error "[activate_mamba_env] Failed to activate Mamba env ${mamba_env} !"; return 1
    fi
}

export -f activate_mamba_env



build_micromamba_container () {
    local micromamba_def_dir=$1
    CONTAINER_NAME=$(basename "${micromamba_def_dir}")

    log_info "Entering micromamba container definition directory: ${micromamba_def_dir}"

    # Navigate to the profile directory
    pushd "${micromamba_def_dir}" > /dev/null || {
        log_error "Failed to navigate to directory: ${micromamba_def_dir}"
        return 1
    }

    # Build micromamba container with apptainer
    log_info "[build_micromamba_container] Creating micromamba container with apptainer build: ${CONTAINER_NAME}"
    CONTAINER_DIR="${PROJ_MICROMAMBA_CONTAINER_DIR}/${CONTAINER_NAME}"

    # Cleanup and create micromamba container directory
    log_info "[build_micromamba_container] Cleaning up and creating micromamba container directory: ${CONTAINER_DIR}"
    rm -rf "${CONTAINER_DIR}"
    mkdir -p "${CONTAINER_DIR}"

    # Build container with apptainer
    if apptainer build --fakeroot "${CONTAINER_DIR}/container.sif" container.def; then
        log_info "[build_micromamba_container] Build completed successfully."
        processed_profiles+=("$micromamba_def_dir:micromamba_def")
    else log_error "[build_micromamba_container] Build failed!"; exit 1
    fi

    # Return to the original directory
    popd > /dev/null || {
        log_error "Failed to return to the original directory from: ${micromamba_def_dir}"
        return 1
    }

    return 0
}

export -f build_micromamba_container



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




execute_step () {
    # Define STEP_DIR and JOB_NAME
    export STEP_DIR="${PWD}"
    STEP_DIR_BASE=$(basename "${STEP_DIR}")
    INTERACTIVE_MODE="${INTERACTIVE_MODE:-false}"

    # JOB_NAME=$(basename "${STEP_DIR}" | cut -d'_' -f2-)
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


    if [[ "${#local_arg_mappings[@]}" -eq 0 && "${#accepted_args[@]}" -eq 0 ]]; then
        # Define argument mappings
        declare -A local_arg_mappings=(
            ["--type"]="--type"
            ["-t"]="--type"
            ["--config"]="--config"
            ["-c"]="--config"
            ["--mode"]="--mode"
            ["-m"]="--mode"
            ["--profile"]="--profile"
            ["-p"]="--profile"
            ["--directory"]="--directory"
            ["-d"]="--directory"
            ["--script"]="--script"
            ["-s"]="--script"
            ["--array-input-file"]="--array-input-file"
            ["-f"]="--array-input-file"
            ["--mamba-env"]="--mamba-env"
            ["-e"]="--mamba-env"
        )

        # Define accepted arguments and their default values
        declare -A accepted_args=(
            ["--type"]="task"               # task or pipeline
            ["--config"]="guix"             # Relevant for tasks, guix, container, mamba
            ["--mode"]="single"             # Relevant for tasks, single or array
            ["--profile"]="main_profile"    # Relevant for tasks
            ["--directory"]="${PROJDIR}"
            ["--script"]=""
            ["--array-input-file"]=""
            ["--mamba-env"]=""
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
    log_info "Final arguments: $(for key in "${!accepted_args[@]}"; do [[ -n "${accepted_args[$key]}" ]] && printf "\n%s=%s" "${key}" "${accepted_args[$key]}"; done)"
    log_info "Additional arguments: $(for key in "${!additional_args[@]}"; do printf "\n%s=%s" "$key" "${additional_args[$key]}" ; done)"


    # Define STEP variables
    STEP_TYPE="${accepted_args["--type"]}"
    STEP_MODE="${accepted_args["--mode"]}"
    STEP_CONFIG="${accepted_args["--config"]}"

    STEP_PROFILE="${accepted_args["--profile"]}"
    STEP_RUN_DIR="${accepted_args["--directory"]}"
    STEP_SCRIPT="${STEP_DIR}"/"${accepted_args["--script"]}"
    
    ARRAY_INPUT_FILE="${accepted_args["--array-input-file"]}"
    MAMBA_ENV="${accepted_args["--mamba-env"]}"

    # Check if STEP_SCRIPT is available
    if [ -f "${STEP_SCRIPT}" ]; then
        log_info "STEP_SCRIPT is: ${STEP_SCRIPT}"
    else
        log_error "STEP_SCRIPT ( ${STEP_SCRIPT} ) not found!"
        return 1
    fi


    ##### Main Execution Logic ####
    # Run based on configuration
    case "${STEP_TYPE}" in
        task)
            case "${STEP_CONFIG}" in
                guix)
                    log_info "Running with guix profile: ${STEP_PROFILE}"

                    # Activate profile
                    log_info "Activating: ${STEP_PROFILE} ..."
                    #. "${STEP_PROFILE}/activate_profile.sh"
                    activate_guix_profile "${STEP_PROFILE}"
                    log_info "Activated: ${GUIX_PROFILE}"

                    if [[ "${STEP_MODE}" == "single" ]]; then
                        # Run STEP_SCRIPT with run_script (single mode)
                        log_info "Running: $(basename "${STEP_SCRIPT}") ..."

                        if cd "${STEP_RUN_DIR}"; then
                            if run_script "${STEP_SCRIPT}" "${add_args[@]}"
                            then log_info "$(basename "${STEP_SCRIPT}") completed successfully!"
                            else log_error "$(basename "${STEP_SCRIPT}") failed!"; return 1
                            fi
                        else log_error "Failed to navigate to ${STEP_RUN_DIR}"; return 1
                        fi
                    elif [[ "${STEP_MODE}" == "array" ]]; then
                        # Run STEP_SCRIPT with run_array_job (array mode)
                        log_info "Running: $(basename "${STEP_SCRIPT}") ..."
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
                    #. "${STEP_PROFILE}/use_container.sh"
                    activate_guix_container "${STEP_PROFILE}"
                    log_info "GUIX_CONTAINER will be used: ${GUIX_CONTAINER}"
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
                    log_info "Activating: ${MAMBA_ENV} ..."
                    activate_mamba_env "${MAMBA_ENV}"
                    log_info "Activated: ${MAMBA_ENV}"

                    if [[ "${STEP_MODE}" == "single" ]]; then
                        # Run STEP_SCRIPT with run_script in mamba env (single mode)
                        log_info "Running: $(basename "${STEP_SCRIPT}") ..."
                        if cd "${STEP_RUN_DIR}"; then
                            if run_script "${STEP_SCRIPT}" "${add_args[@]}"
                            then log_info "$(basename "${STEP_SCRIPT}") completed successfully!"
                            else log_error "$(basename "${STEP_SCRIPT}") failed!"; return 1
                            fi
                        else log_error "Failed to navigate to ${STEP_RUN_DIR}"; return 1
                        fi
                    elif [[ "${STEP_MODE}" == "array" ]]; then
                        # Run STEP_SCRIPT with run_array_job in mamba env (array mode)
                        log_info "Running: $(basename "${STEP_SCRIPT}") ..."
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
                    log_error "Invalid option to --config variable: ${STEP_CONFIG} | --config could be 'container' or 'guix' (default)"
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
            log_error "Invalid option to --type variable: ${STEP_TYPE} | --type could be 'pipeline' or 'task' (default)"
            return 1
            ;;
    esac

    log_info "Step completed successfully!"
}

export -f execute_step

