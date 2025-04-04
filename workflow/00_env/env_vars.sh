#!/bin/bash

# General TMP directory
export TMPDIR="/tmp" # Change this to a different location if you want to use a different tmp directory

# Project directory
export PROJDIR="___" # Full path to the project directory
. "${PROJDIR}/utils/utils.sh"

# Project specific cache, config, data locations
export PROJ_CACHE_DIR="${PROJDIR}/.proj/.cache"
export PROJ_CONFIG_DIR="${PROJDIR}/.proj/.config"
export PROJ_DATA_DIR="${PROJDIR}/.proj/.data"

# R cache, config, data locations
export R_USER_CACHE_DIR="${PROJ_CACHE_DIR}/R"
export R_USER_CONFIG_DIR="${PROJ_CONFIG_DIR}/R"
export R_USER_DATA_DIR="${PROJ_DATA_DIR}/R"

# Environment description directories
export PROJ_GUIX_PROFILE_DESC="${PROJDIR}/workflow/00_env/guix_profile_descriptions"
export PROJ_MAMBA_ENV_DESC="${PROJDIR}/workflow/00_env/mamba_env_descriptions"
export PROJ_MICROMAMBA_DEF="${PROJDIR}/workflow/00_env/micromamba_container_definitions"

# Environment library directories
export PROJ_GUIX_PROFILE_DIR="${PROJDIR}/lib/guix_profiles"
export PROJ_MAMBA_ENV_DIR="${PROJDIR}/lib/mamba_envs"
export PROJ_R_LIBS_DIR="${PROJDIR}/lib/Rlibs"
export PROJ_PYTHON_LIBS_DIR="${PROJDIR}/lib/python_libs"
export PROJ_GUIX_CONTAINER_DIR="${PROJDIR}/containers/guix"
export PROJ_MICROMAMBA_CONTAINER_DIR="${PROJDIR}/containers/micromamba"

export MINIFORGE3_PATH="${HOME}/miniforge3"

# Specific environment profile directories
export MAIN_PROFILE="${PROJ_GUIX_PROFILE_DESC}/main_profile"
