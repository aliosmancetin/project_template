#!/bin/bash
#SBATCH -e logs/%x.error.log
#SBATCH -o logs/%x.output.log
#SBATCH --mem-per-cpu=16G
#SBATCH --time=1500
#SBATCH --mail-type=END,FAIL

# Source environment variables
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/00_env/env_vars.sh"     #. ../00_env/env_vars.sh

# Execute step
execute_step "$@"
