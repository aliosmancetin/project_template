#!/bin/bash


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


