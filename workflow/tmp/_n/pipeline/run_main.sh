#!/bin/bash

# Run Nextflow
nextflow -C "nextflow.config" -log logs/nextflow.log \
    run "main.nf" \
        -profile apptainer \
        -resume \
        -with-report \
        -with-timeline \
        -with-dag \
        #-stub

