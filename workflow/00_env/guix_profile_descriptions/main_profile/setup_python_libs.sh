#!/bin/bash

pip3 install \
    -r python_requirements.txt \
    --target "${TARGET_DIR}" \
    --cache-dir="${PROJ_CACHE_DIR}/pip"
