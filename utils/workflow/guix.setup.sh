#!/bin/bash


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

