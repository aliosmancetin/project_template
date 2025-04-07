#!/bin/bash
#SBATCH --job-name=rstudio
#SBATCH --mem-per-cpu=50G
#SBATCH --time=12:00:00
#SBATCH --mail-type=END,FAIL

# -------------------- Parse Arguments --------------------
PROFILE="main_profile"
ENGINE=""

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

# -------------------- Engine Detection --------------------
if [[ -z "${ENGINE}" ]]; then
  if command -v sbatch &> /dev/null; then
    ENGINE="slurm"
  else
    ENGINE="wsl"
  fi
fi

# -------------------- Source Environment --------------------
. ../../workflow/00_env/env_vars.sh
activate_guix_profile "${PROFILE}"

# -------------------- SLURM Engine --------------------
if [[ "${ENGINE}" == "slurm" ]]; then
    source /etc/profile.d/slurm.sh
    
    echo "Your RStudio instance awaits you at: http://$(hostname -f):${SLURM_INTERACT_PORT}"
    echo "Your RStudio instance awaits you at: http://$(hostname -f):${SLURM_INTERACT_PORT}" | \
        mail -s "RStudio instance started for Job ${SLURM_JOB_ID} (${SLURM_JOB_NAME})" "${USER}"

    rserver \
        --database-config-file=<(echo -e "provider=sqlite\ndirectory=${HOME}/rstudio-server-db") \
        --secure-cookie-key-file="${TMPDIR}/secure-cookie-key" \
        --server-data-dir="${TMPDIR}" \
        --auth-none=1 \
        --server-user="$(whoami)" \
        --www-address="${HOSTNAME}" \
        --www-port="${SLURM_INTERACT_PORT}"        
        
# -------------------- WSL Engine --------------------
elif [[ "$ENGINE" == "wsl" ]]; then
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
