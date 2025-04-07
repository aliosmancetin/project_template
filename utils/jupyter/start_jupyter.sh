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
# NOTEBOOK_DIR="/fast/AG_Gargiulo/AC/projects/mouse_embryo"
# WORKSPACE="mouse_embryo_workspace"
PORT="${JUPYTER_PORT:-8888}"  # default, can be overridden via env

# -------------------- Execute Based on Engine --------------------
if [[ "${ENGINE}" == "slurm" ]]; then

    PROJDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    SLURM_SCRIPT=$(cat <<EOF
#!/bin/bash
#SBATCH --job-name=jupyter_${PROFILE}
#SBATCH --mem-per-cpu=50G
#SBATCH --time=12:00:00
#SBATCH --mail-type=END,FAIL
#SBATCH --output="${TMPDIR:-/tmp}/jupyter_%j.out"

. ${PROJDIR}/workflow/00_env/env_vars.sh
activate_guix_profile "${PROFILE}"
source /etc/profile.d/slurm.sh

echo "Your JupyterLab instance awaits you at: http://\$(hostname -f):\${SLURM_INTERACT_PORT}"

cd "${PROJDIR}" || exit 1

jupyter lab \\
    --ip=\$(hostname -f) \\
    --port=\${SLURM_INTERACT_PORT} \\
    --no-browser |& tee /dev/stderr | {
        grep -qP '\\s{2}http://.*' && \\
        echo "Your Jupyter server is running at: \$(grep -oP '\\s{2}http://\\S+' <<< "\$(cat ${SLURM_JOB_STDERR:-/dev/null} 2>/dev/null || cat)")" | \\
        mail -s "Jupyter started for job \${SLURM_JOB_ID} (\${SLURM_JOB_NAME})" "\${USER}"
        cat >/dev/null
    }
EOF
)

    echo "Submitting SLURM job for JupyterLab..."
    sbatch <<< "${SLURM_SCRIPT}"

elif [[ "${ENGINE}" == "wsl" ]]; then
    PROJDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    . "${PROJDIR}/workflow/00_env/env_vars.sh"
    activate_guix_profile "${PROFILE}"

    WSL_IP=$(hostname -I | awk '{print $1}')
    echo "Launching JupyterLab in WSL"
    echo "Open in your browser: http://${WSL_IP}:${PORT}"

    cd "${PROJDIR}" || exit 1

    jupyter lab \
        --ip=0.0.0.0 \
        --port="${PORT}" \
        --no-browser

else
    echo "Unknown engine: ${ENGINE}"
    exit 1
fi
