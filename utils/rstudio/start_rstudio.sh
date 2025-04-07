#!/bin/bash

# -------------------- Defaults --------------------
PROFILE="main_profile"
ENGINE=""

# -------------------- Parse Arguments --------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        --profile)
        PROFILE="$2"
        shift 2
        ;;
        --engine)
        ENGINE="$2"
        shift 2
        ;;
        *)
        echo "Unknown argument: $1"
        echo "Usage: $0 [--profile <profile>] [--engine <slurm|wsl>]"
        exit 1
        ;;
    esac
done


# -------------------- Detect Engine --------------------
if [[ -z "${ENGINE}" ]]; then
    if command -v sbatch &> /dev/null; then
        ENGINE="slurm"
    else
        ENGINE="wsl"
    fi
fi

echo "Using profile: ${PROFILE}"
echo "Using engine: ${ENGINE}"

# -------------------- Execute Based on Engine --------------------
if [[ "${ENGINE}" == "slurm" ]]; then

    PROJDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    SLURM_SCRIPT=$(cat <<EOF
#!/bin/bash
#SBATCH --job-name="rstudio_${PROFILE}"
#SBATCH --mem-per-cpu=50G
#SBATCH --time=12:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --output="${PROJDIR}/utils/rstudio/logs/%x.%j.out"

source /etc/profile.d/slurm.sh

# Load environment
. ${PROJDIR}/workflow/00_env/env_vars.sh
activate_guix_profile "${PROFILE}"

echo "Your RStudio instance awaits you at: http://\$(hostname -f):\${SLURM_INTERACT_PORT}"
echo "Your RStudio instance awaits you at: http://\$(hostname -f):\${SLURM_INTERACT_PORT}" | \
    mail -s "RStudio instance started for Job \${SLURM_JOB_ID} (\${SLURM_JOB_NAME})" "\${USER}"

rserver \
  --database-config-file=<(echo -e "provider=sqlite\ndirectory=\${HOME}/rstudio-server-db") \
  --secure-cookie-key-file="\${TMPDIR}/secure-cookie-key" \
  --server-data-dir="\${TMPDIR}" \
  --auth-none=1 \
  --server-user="\$(whoami)" \
  --www-address="\${HOSTNAME}" \
  --www-port="\${SLURM_INTERACT_PORT}"
EOF
)

  echo "Submitting SLURM job for RStudio Server..."
  sbatch <<< "${SLURM_SCRIPT}"

elif [[ "${ENGINE}" == "wsl" ]]; then
  # Source environment
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/00_env/env_vars.sh"   #. ../../workflow/00_env/env_vars.sh
  activate_guix_profile "${PROFILE}"

  RSTUDIO_PORT=8787
  WSL_IP=$(hostname -I | awk '{print $1}')

  echo "Launching RStudio Server in WSL"
  echo "Access it in your browser: http://${WSL_IP}:${RSTUDIO_PORT}"

  rserver \
    --database-config-file=<(echo -e "provider=sqlite\ndirectory=${HOME}/rstudio-server-db") \
    --secure-cookie-key-file="/tmp/secure-cookie-key" \
    --server-data-dir="/tmp/rstudio-server" \
    --auth-none=1 \
    --server-user="$(whoami)" \
    --www-address="0.0.0.0" \
    --www-port="${RSTUDIO_PORT}"

else
  echo "Unknown engine: ${ENGINE}"
  exit 1
fi
