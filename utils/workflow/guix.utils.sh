#!/bin/bash


parse_options_file() {
    local file_path="$1"
    local -n out_array="$2"

    if [[ ! -f "${file_path}" || ! -s "${file_path}" ]]; then
        log_info "[parse_options_file] File not found or is empty: ${file_path}"
        out_array=()
        return 0
    fi

    out_array=()  # Clear output array first
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines or comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        out_array+=("$line")
    done < "${file_path}"

    log_info "[parse_options_file] Parsed ${#out_array[@]} options from: ${file_path}"
}

export -f parse_options_file


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
  local profile_file
  profile_file="${PROJ_GUIX_PROFILE_DIR}/${profile_name}/${profile_name}/etc/profile"

  if [[ ! -f "${cache_dir}/channels.hash" || ! -f "${cache_dir}/manifest.hash" || ! -f "${profile_file}" ]]; then
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

  rm -rf "${temp_dir}"

  if [[ "${current_channels_hash}" == "${cached_channels_hash}" && "${current_manifest_hash}" == "${cached_manifest_hash}" ]]; then
    log_info "[check_guix_cache] Cache valid for profile: ${profile_name}. Skipping rebuild."
    return 0
  else
    log_info "[check_guix_cache] Cache mismatch for profile: ${profile_name}. Rebuild required."
    return 1
  fi
}

export -f cache_guix_profile



