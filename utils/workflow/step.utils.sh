#!/bin/bash


# Determine the script's directory and derive script-specific details
initialize_script_environment () {

    if [[ "${STANDALONE_MODE,,}" == "true" ]]; then
        script_dir=$(dirname "$(readlink -f "$0")")
        log_debug "[${FUNCNAME[0]}] Standalone execution detected: ${script_dir}"
    elif [[ -n "${SLURM_SUBMIT_DIR}" ]]; then
        script_dir="${SLURM_SUBMIT_DIR}"
        log_debug "[${FUNCNAME[0]}] SLURM submission directory detected: ${script_dir}"        
    fi

    # Derive the config file name
    config_file="${script_dir}/config.yaml" # ${script_suffix}.config"
    log_debug "[${FUNCNAME[0]}] Derived configuration file: ${config_file}"

    # Parse the configuration file
    parse_config_yaml "${config_file}"
}

export -f initialize_script_environment



parse_config_yaml () {
    local config_file=$1

    if [[ ! -f "${config_file}" ]]; then
        log_debug "[${FUNCNAME[0]}] No configuration file found: ${config_file}"
        return 1
    fi
    log_debug "[${FUNCNAME[0]}] Parsing: ${config_file}"

    # 1) Find all top-level map keys
    mapfile -t top_keys < <(
      yq eval -r '
        to_entries[]
        | select(.value|tag=="!!map")
        | .key
      ' "${config_file}"
    )

    for key in "${top_keys[@]}"; do
        local map_name="config_${key}_args"

        # Validate identifier
        if [[ ! "${map_name}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
            log_warn "[${FUNCNAME[0]}] Skipping invalid map key: ${key}"
            continue
        fi

        # Declare the assoc array
        eval "declare -gA ${map_name}"

        # 2) Pull out all scalar children of ."$key"
        mapfile -t entries < <(
          yq eval -r '
            .["'"$key"'"]
            // {}
            | to_entries[]
            | select(.value|tag!="!!map" and .value|tag!="!!seq")
            | "\(.key)=\(.value)"
          ' "$config_file"
        )

        # 3) Populate
        for entry in "${entries[@]}"; do
            IFS="=" read -r subk val <<< "${entry}"
            [[ -z $subk || "$subk" == "null" ]] && continue
            eval "$map_name[\"\$subk\"]=\"\$val\""
        done

        # debug
        log_debug "[${FUNCNAME[0]}] ${map_name} → ${entries[*]}"
    done
    
    # Handle special case: 'script.positional' as a list
    if yq eval '.script.positional | tag' "${config_file}" | grep -q '!!seq'; then
        mapfile -t _script_positional_items < <(yq eval '.script.positional[]' "${config_file}")

        # Flatten to a single space-separated string (preserving token order)
        flattened_positional=$(printf "%s " "${_script_positional_items[@]}")
        config_script_args["positional"]="${flattened_positional% }"  # Trim trailing space

        log_debug "[${FUNCNAME[0]}] Parsed script.positional as: ${config_script_args["positional"]}"
    fi

}

export -f parse_config_yaml





parse_cli_arguments () {
    local -n arg_mappings=$1
    shift
    declare -gA cli_step_args
    declare -gA cli_script_args

    if [[ -z "${arg_mappings[*]}" ]]; then
        log_debug "[${FUNCNAME[0]}] No argument mappings defined. Using raw keys."
    else
        log_debug "[${FUNCNAME[0]}] Argument mappings passed: $(for key in "${!arg_mappings[@]}"; do printf "\n%s=%s" "$key" "${arg_mappings[$key]}" ; done)"
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
                if [[ -n "$normalized_key" ]]; then
                    cli_step_args["$normalized_key"]="$value"
                else
                    # custom arguments clearly stored in cli_script_args
                    cleaned_key="${key#--}"
                    cli_script_args["$cleaned_key"]="$value"
                fi
                shift
                ;;
            *)
                log_error "[${FUNCNAME[0]}] Unknown option format: $1"
                exit 1
                ;;
        esac
    done

    # Debug: Confirm parsed CLI arguments
    #log_debug "[${FUNCNAME[0]}] Parsed CLI Args: $(for key in "${!cli_args[@]}"; do printf "\n%s=%s" "$key" "${cli_args[$key]}" ; done)"
    log_debug "[${FUNCNAME[0]}] Parsed cli_step_args: $(for key in "${!cli_step_args[@]}"; do printf "\n%s=%s" "$key" "${cli_step_args[$key]}"; done)"
    log_debug "[${FUNCNAME[0]}] Parsed cli_script_args (custom): $(for key in "${!cli_script_args[@]}"; do printf "\n%s=%s" "$key" "${cli_script_args[$key]}"; done)"
}

export -f parse_cli_arguments



# Merge command-line arguments with configuration file values
# Command-line arguments take precedence
merge_args_with_config () {
    local cli_array_names=($1)     # Names of CLI associative arrays (space-separated)
    local config_array_names=($2)  # Names of config associative arrays (space-separated)
    local default_array_names=($3) # Names of default associative arrays (space-separated)
    local merged_array_names=($4)

    for i in "${!merged_array_names[@]}"; do
        local cli_array_name="${cli_array_names[$i]}"
        local config_array_name="${config_array_names[$i]}"
        local default_array_name="${default_array_names[$i]}"
        local merged_array_name="${merged_array_names[$i]}"

        log_debug "[${FUNCNAME[0]}] Merging arrays: CLI='${cli_array_name}' with Config='${config_array_name}'"

        # Access global arrays by their names
        eval "local -n cli_array_ref=$cli_array_name"
        eval "local -n config_array_ref=$config_array_name"
        eval "local -n default_array_ref=$default_array_name"
        eval "declare -gA $merged_array_name"
        eval "local -n merged_array_ref=$merged_array_name"

        # Create an indexed array to collect all keys
        all_keys=()

        # Collect keys from each associative array
        for key in "${!cli_array_ref[@]}"; do all_keys+=("$key"); done
        for key in "${!config_array_ref[@]}"; do all_keys+=("$key"); done
        for key in "${!default_array_ref[@]}"; do all_keys+=("$key"); done

        # Create a unique set of keys using an associative array
        declare -A seen_keys
        for key in "${all_keys[@]}"; do
            seen_keys["$key"]=1
        done

        for key in "${!seen_keys[@]}"; do
            # Command-line arguments take precedence
            if [[ -n "${cli_array_ref[$key]}" ]]; then
                merged_array_ref["$key"]="${cli_array_ref[$key]}"
                log_debug "[${FUNCNAME[0]}] Using command-line argument for: ${key}=${cli_array_ref[$key]}"
            # Config file values come next
            elif [[ -n "${config_array_ref[$key]}" ]]; then
                merged_array_ref["$key"]="${config_array_ref[$key]}"
                log_debug "[${FUNCNAME[0]}] Using configuration file value for: ${key}=${config_array_ref[$key]}"
            # Fallback to default value if non-zero
            elif [[ -n "${default_array_ref[$key]}" ]]; then
                merged_array_ref["$key"]="${default_array_ref[$key]}"
                log_debug "[${FUNCNAME[0]}] Using default value for: ${key}=${default_array_ref[$key]}"
            fi
        done

    done

}

export -f merge_args_with_config



activate_step_environment () {
    local env_type=$1
    local env_name=$2

    case "${env_type}" in
        guix)
            log_debug "[${FUNCNAME[0]}] Activating guix profile: ${env_name}"
            activate_guix_profile "${env_name}"
            log_debug "[${FUNCNAME[0]}] Activated: ${env_name}"
            return 0
            ;;
        container)
            log_debug "[${FUNCNAME[0]}] Using guix container: ${env_name}"
            activate_guix_container "${env_name}"
            log_debug "[${FUNCNAME[0]}] GUIX_CONTAINER will be used: ${GUIX_CONTAINER}"
            return 0
            ;;
        mamba)
            log_debug "[${FUNCNAME[0]}] Activating mamba environment: ${env_name}"
            activate_mamba_env "${env_name}"
            log_debug "[${FUNCNAME[0]}] Activated: ${env_name}"
            return 0
            ;;
        *)
            log_error "[${FUNCNAME[0]}] Unknown environment type: ${env_type}"
            return 1
            ;;
    esac
}
