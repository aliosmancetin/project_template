#!/bin/bash

# Source environment variables
. ../../workflow/00_env/env_vars.sh

# Activate main_profile
activate_guix_profile "main_profile"

# Define port
RSTUDIO_PORT=8787

# Get WSL IP (for Windows browser access) or fallback to localhost
WSL_IP=$(hostname -I | awk '{print $1}')

# Notify user where to connect
echo "RStudio Server is launching..."
echo "Access it in your browser: http://${WSL_IP}:${RSTUDIO_PORT}"

# Start RStudio Server
rserver \
    --www-port="${RSTUDIO_PORT}" \
    --www-address="0.0.0.0" \
    --auth-none=1 \
    --server-user="$(whoami)" \
    --server-data-dir="/tmp/rstudio-server" \
    --secure-cookie-key-file="/tmp/secure-cookie-key" \
    --database-config-file=<(echo -e "provider=sqlite\ndirectory=${HOME}/rstudio-server-db")
