#!/bin/bash
#SBATCH -e logs/%x_%a.error.log
#SBATCH -o logs/%x_%a.output.log
#SBATCH --mem-per-cpu=4G
#SBATCH --time=5
#SBATCH --mail-type=END,FAIL

# Source environment variables
. ../00_env/env_vars.sh

# Execute step
execute_step "$@"
