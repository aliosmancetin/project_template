#!/bin/bash

# Parse arguments:
# --input_line is the input_line from array_input_file
while [[ $# -gt 0 ]]; do
    case $1 in
        --input_line)
            INPUT_LINE="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# If INPUT_LINE is environment variable, get the value of it
INPUT_LINE_VAL=$(printenv "${INPUT_LINE}")
