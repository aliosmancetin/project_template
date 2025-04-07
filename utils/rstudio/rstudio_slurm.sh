#!/bin/bash
#SBATCH --job-name=rstudio_main_profile
#SBATCH --mem-per-cpu=50G
#SBATCH --time=12:00:00
#SBATCH --mail-type=END,FAIL

# Source environment variables
. ../../workflow/00_env/env_vars.sh

# Activate main_profile
activate_guix_profile "main_profile"

# Load SLURM environment
source /etc/profile.d/slurm.sh

# Notify user of RStudio instance
echo "Your RStudio instance awaits you at http://$(hostname -f):${SLURM_INTERACT_PORT}"
echo "Your RStudio instance awaits you at http://$(hostname -f):${SLURM_INTERACT_PORT}" | \
    mail -s "RStudio instance started for Job ${SLURM_JOB_ID} (${SLURM_JOB_NAME})" "${USER}"

# Start RStudio server
rserver \
    --database-config-file=<(echo -e "provider=sqlite\ndirectory=${HOME}/rstudio-server-db") \
    --auth-none=1 \
    --www-address="${HOSTNAME}" \
    --www-port="${SLURM_INTERACT_PORT}" \
    --server-user="$(whoami)" \
    --server-data-dir="${TMPDIR}" \
    --secure-cookie-key-file="${TMPDIR}"/secure-cookie-key
