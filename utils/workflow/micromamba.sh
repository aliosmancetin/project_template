#!/bin/bash


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


