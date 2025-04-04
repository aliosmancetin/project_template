#!/bin/bash

DATASET_ID=GG_PS5_20241220
INPUT_DIR="${PROJDIR}/data/avatar_rna_seq/${DATASET_ID}"

# Output file to store the JSON and CSV output
OUTPUT_DIR="output/intermediate/04_create_avatar_metadata/${DATASET_ID}"
OUTPUT_FILE_JSON="${OUTPUT_DIR}/metadata.json"
OUTPUT_FILE_CSV="${OUTPUT_DIR}/metadata.csv"

mkdir -p "${OUTPUT_DIR}"

# Clear the output file if it exists
> "${OUTPUT_FILE_JSON}"
> "${OUTPUT_FILE_CSV}"

# Initialize a temporary JSON array
json_array="[]"

# Create an array of unique base names
sample_names=($(find "${INPUT_DIR}" -type f -name "*.fq.gz" \
    | sed -E 's|.*/||' | sed -E 's/_[12]\.fq\.gz$//' | sort -u))

# Iterate over the unique base names and check for pairs
for sample_name in "${sample_names[@]}"; do
    read1="${sample_name}_1.fq.gz"
    read2="${sample_name}_2.fq.gz"

    if [[ -f "${INPUT_DIR}/${read1}" && -f "${INPUT_DIR}/${read2}" ]]; then
        # Create a JSON object for this pair
        json_object=$(jq -n \
            --arg sample_name "${sample_name}" \
            --arg read1 "${read1}" \
            --arg read2 "${read2}" \
            '{sample_name: $sample_name, read1: $read1, read2: $read2}')
        
        # Append the JSON object to the array
        json_array=$(echo "${json_array}" | jq --argjson obj "${json_object}" '. += [$obj]')
    fi
done

# Write the JSON array to the output file
echo "${json_array}" > "${OUTPUT_FILE_JSON}"

# Make CSV from JSON
in2csv "${OUTPUT_FILE_JSON}" > "${OUTPUT_FILE_CSV}"

# Log the end
printf "%s [INFO] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "[${DATASET_ID}] JSON results saved in ${OUTPUT_FILE_JSON} | CSV results saved in ${OUTPUT_FILE_CSV}"
