#!/bin/bash


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

        # Set other environment variables
        if [ -n "${JUPYTER_PATH}" ]; then
            export JUPYTER_PATH="${PROJ_JUPYTER_PATH}:${JUPYTER_PATH}"
        fi
    }
    then log_info "[activate_mamba_env] Mamba env ${mamba_env} activated successfully!"; return 0
    else log_error "[activate_mamba_env] Failed to activate Mamba env ${mamba_env} !"; return 1
    fi
}

export -f activate_mamba_env

