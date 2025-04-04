#!/bin/bash

# Set Trap for ERR signal
trap 'log_error "[run_main.sh] Failed!"; exit 1' ERR

# Run Nextflow
nextflow -C "nextflow.config" -log logs/nextflow.log \
    run "main.nf" \
        -profile apptainer \
        -resume \
        -with-report \
        -with-timeline \
        -with-dag \
        #-stub \

# If Nextflow succeeds, log success
log_info "[run_main.sh] Completed successfully."
