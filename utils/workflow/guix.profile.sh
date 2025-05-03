#!/bin/bash


create_guix_profile () {
    local PROFILE_NAME=$1

    local config
    config="${accepted_args["--config"]}"

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

    # Remove container if config == both and guix_env_built == true
    if [[ "${config}" == "both" && "${guix_env_built}" == true ]]; then
        CONTAINER_OUTPUT="${PROJ_GUIX_CONTAINER_DIR}/${PROFILE_NAME}"/container.squashfs
        log_info "[create_guix_profile] Cleaning up container directory because cache is no longer valid: ${CONTAINER_OUTPUT}"
        
        if [[ -f "${CONTAINER_OUTPUT}" ]]; then
            rm -rf "${CONTAINER_OUTPUT}"
        else
            log_info "[create_guix_profile] No container found to remove."
        fi
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

    if [ -n "${JUPYTER_PATH}" ]; then
        export JUPYTER_PATH="${PROJ_JUPYTER_PATH}:${JUPYTER_PATH}"
        export JUPYTER_DATA_DIR="${PROJ_JUPYTER_PATH}"
    fi

    if [ -f "${PROFILE_DESC}/setup_rlibs.R" ]; then
        export R_LIBS_USER="${PROJ_R_LIBS_DIR}/${PROFILE_NAME}"
    fi

    if [ -f "${PROFILE_DESC}/setup_python_libs.sh" ]; then
        export GUIX_PYTHONPATH="${GUIX_PYTHONPATH:+$GUIX_PYTHONPATH:}${PROJ_PYTHON_LIBS_DIR}/${PROFILE_NAME}"
        export PATH="${PATH}:${PROJ_PYTHON_LIBS_DIR}/${PROFILE_NAME}/bin"
    fi
}

export -f activate_guix_profile

