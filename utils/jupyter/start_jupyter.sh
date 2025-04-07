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

# -------------------- Common Parameters --------------------
# WORKSPACE="mouse_embryo_workspace"
PORT="${JUPYTER_PORT:-8888}"  # default, can be overridden via env
PROJDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. ${PROJDIR}/workflow/00_env/env_vars.sh

export JUPYTERLAB_WORKSPACES_DIR="${PROJ_JUPYTER_DIR}/lab/workspaces"
mkdir -p "${JUPYTERLAB_WORKSPACES_DIR}"

# -----------------------------
# Kernel Autoregistration
# -----------------------------
KERNEL_DIR="${PROJ_JUPYTER_PATH}/kernels"
echo "Cleaning previously registered kernels..."
rm -rf "${KERNEL_DIR:?}"
mkdir -p "${KERNEL_DIR}"

# -----------------------------
# Helper: Register a kernel in a subshell
# -----------------------------
register_kernel() {
  local env_type="$1"     # "guix" or "mamba"
  local env_name="$2"
  local display_name="${env_type^} - ${env_name}"  # Capitalize first letter

  (
    set -e  # Subshell should exit on error

    echo "Registering ${display_name}..."

    if [[ "${env_type}" == "guix" ]]; then
      activate_guix_profile "${env_name}"
    elif [[ "${env_type}" == "mamba" ]]; then
      activate_mamba_env "${env_name}"
    else
      echo "Unknown environment type: ${env_type}"
      exit 1
    fi

    # Register the kernel using ipython
    ipython kernel install \
      --name "${env_type}-${env_name}" \
      --display-name "${display_name}" \
      --prefix "${PROJDIR}/.proj"
  )
}

# -----------------------------
# Register Guix profiles
# -----------------------------
if [[ -d "${PROJ_GUIX_PROFILE_DESC}" ]]; then
  echo "Searching for Guix profiles in: ${PROJ_GUIX_PROFILE_DESC}"
  for profile_path in "${PROJ_GUIX_PROFILE_DESC}"/*; do
    [[ -d "${profile_path}" ]] || continue
    profile_name=$(basename "${profile_path}")
    register_kernel "guix" "${profile_name}"
  done
fi

# -----------------------------
# Register Mamba envs
# -----------------------------
if [[ -d "${PROJ_MAMBA_ENV_DESC}" ]]; then
  echo "Searching for Mamba envs in: ${PROJ_MAMBA_ENV_DESC}"
  for env_path in "${PROJ_MAMBA_ENV_DESC}"/*; do
    [[ -d "${env_path}" ]] || continue
    env_name=$(basename "${env_path}")
    register_kernel "mamba" "${env_name}"
  done
fi

echo "Kernel registration complete. Registered kernels:"
ls -1 "${KERNEL_DIR}"


# -------------------- Execute Based on Engine --------------------
if [[ "${ENGINE}" == "slurm" ]]; then

    SLURM_SCRIPT=$(cat <<EOF
#!/bin/bash
#SBATCH --job-name=jupyter_${PROFILE}
#SBATCH --mem-per-cpu=50G
#SBATCH --time=12:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --output="${PROJDIR}/utils/jupyter/logs/%x.%j.out"

source /etc/profile.d/slurm.sh

. ${PROJDIR}/workflow/00_env/env_vars.sh
activate_guix_profile "${PROFILE}"

jupyter kernelspec list > "${PROJDIR}/utils/jupyter/logs/kernelspec.out"

echo "Your JupyterLab instance awaits you at: http://\$(hostname -f):\${SLURM_INTERACT_PORT}"

jupyter lab \
    --notebook-dir="${PROJDIR}" \
    --ip=\$(hostname -f) \
    --port=\${SLURM_INTERACT_PORT} \
    --no-browser |& tee /dev/stderr | { grep -qP '\s{2}http://max' && \
	echo "Your jupyter server is running at: \$(grep -P "\s{2}http://\$(hostname -f)" "${PROJDIR}/utils/jupyter/logs/\${SLURM_JOB_NAME}.\${SLURM_JOB_ID}.out" | awk '{print \$1}')" | \
      mail -s "Jupyter started for job \${SLURM_JOB_ID} (\${SLURM_JOB_NAME})" \${USER}
      cat >/dev/null
    }
EOF
)

    echo "Submitting SLURM job for JupyterLab..."
    sbatch <<< "${SLURM_SCRIPT}"

elif [[ "${ENGINE}" == "wsl" ]]; then
    
    activate_guix_profile "${PROFILE}"

    WSL_IP=$(hostname -I | awk '{print $1}')
    echo "Launching JupyterLab in WSL"
    echo "Open in your browser: http://${WSL_IP}:${PORT}"

    jupyter lab \
        --notebook-dir="${PROJDIR}" \
        --ip="${WSL_IP}" \
        --port="${PORT}" \
        --no-browser

else
    echo "Unknown engine: ${ENGINE}"
    exit 1
fi
