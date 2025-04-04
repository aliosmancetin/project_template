#!/bin/bash
#SBATCH -e logs/%x.error.log
#SBATCH -o logs/%x.output.log
#SBATCH --mem-per-cpu=4G
#SBATCH --time=30
#SBATCH --mail-type=END,FAIL

# Source environment variables
. env_vars.sh

# Setup env
setup_env "$@"
