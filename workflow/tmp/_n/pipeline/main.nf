#!/bin/env nextflow

nextflow.enable.dsl = 2



process bam_to_fastq {
    tag "${Sample_ID}"
	publishDir "${params.outdir}/fastq/${File_ID}/", pattern: "*.fastq", mode:'copy'
	publishDir "${params.logdir}/fastq/${File_ID}/", pattern: '.command*', mode:'copy'

    input:
    tuple val(Case_ID), val(Sample_ID), val(File_ID), val(File_Name)
	val bam_dir

    output:
    tuple val(Case_ID), val(Sample_ID), val(File_ID), val(File_Name), emit: metadata
	tuple path("*.R1.fastq"), path("*.R2.fastq"), path("*.S.fastq"), emit: fastq_files
	path ".command*", emit: logs

    script:
	"""
	echo "Case_ID: ${Case_ID}"
	echo "Sample_ID: ${Sample_ID}"
	echo "File_ID: ${File_ID}"
	echo "File_Name: ${File_Name}"

	samtools collate -@ 8 -u -O ${bam_dir}/${File_ID}/${File_Name} tmp |
	samtools fastq -@ 8 \
				   -1 ${File_Name}.R1.fastq \
				   -2 ${File_Name}.R2.fastq \
				   -s ${File_Name}.S.fastq \
				   -0 /dev/null
				   -c 6

	"""


	stub:
	"""
	echo "Case_ID: ${Case_ID}"
	echo "Sample_ID: ${Sample_ID}"
	echo "File_ID: ${File_ID}"
	echo "File_Name: ${File_Name}"

	samtools view -@ 16 \
				  --bam \
				  --with-header \
				  --subsample 0.00001 \
				  --subsample-seed 10 \
				  --output "${File_Name}" \
				  ${bam_dir}/${File_ID}/${File_Name}


	samtools collate -@ 8 -u -O "${File_Name}" tmp |
	samtools fastq -@ 16 \
				   -1 ${File_Name}.R1.fastq \
				   -2 ${File_Name}.R2.fastq \
				   -s ${File_Name}.S.fastq \
				   -0 /dev/null
				   -c 6

	"""
}


process perform_fastqc {
    tag "${Sample_ID}"
	publishDir "${params.outdir}/fastqc/${File_ID}/", pattern: "*fastqc.{html,zip}", mode:'copy'
	publishDir "${params.logdir}/fastqc/${File_ID}/", pattern: '.command*', mode:'copy'

    input:
	tuple val(Case_ID), val(Sample_ID), val(File_ID), val(File_Name)
	path fastq_files

    output:
	tuple val(Case_ID), val(Sample_ID), val(File_ID), val(File_Name), emit: metadata
	path "*fastqc.{html,zip}", emit: fastqc_results
	path ".command*", emit: logs

    script:
	"""
	echo "Case_ID: ${Case_ID}"
	echo "Sample_ID: ${Sample_ID}"
	echo "File_ID: ${File_ID}"
	echo "File_Name: ${File_Name}"

    fastqc -t 16 ${fastq_files}

	"""
}



process perform_multiqc {
    tag "multiqc"
	publishDir "${params.outdir}/multiqc/", pattern: "multiqc**", mode:'copy'
	publishDir "${params.logdir}/multiqc/", pattern: '.command*', mode:'copy'

    input:
	path fastqc_results

    output:
	path "multiqc**", emit: multiqc_result
	path ".command*", emit: logs

    script:
	"""
    multiqc --fullnames .

	"""
}



process perform_STAR {
    tag "${Sample_ID}"
    publishDir "${params.outdir}/STAR/${File_ID}", pattern: "${File_ID}**", mode:'copy'
	publishDir "${params.logdir}/STAR/${File_ID}", pattern: '.command*', mode:'copy'

    input:
	tuple val(Case_ID), val(Sample_ID), val(File_ID), val(File_Name)
	tuple path(R1), path(R2)
	val STAR_index_dir

    output:
	tuple val(Case_ID), val(Sample_ID), val(File_ID), val(File_Name), emit: metadata
	path "${File_ID}.Aligned.toTranscriptome.out.bam", emit: STAR_aligned_to_transcriptome
	path "${File_ID}**", emit: STAR_results
	path ".command*", emit: logs

    script:
	"""
	echo "Case_ID: ${Case_ID}"
	echo "Sample_ID: ${Sample_ID}"
	echo "File_ID: ${File_ID}"
	echo "File_Name: ${File_Name}"

    STAR \
		--readFilesIn ${R1} ${R2} \
		--outSAMattrRGline 'ID:${File_ID}' \
		--genomeDir ${STAR_index_dir} \
		--readFilesCommand zcat \
		--runThreadN 16 \
		--twopassMode Basic \
		--outFilterMultimapNmax 20 \
		--alignSJoverhangMin 8 \
		--alignSJDBoverhangMin 1 \
		--outFilterMismatchNmax 999 \
		--outFilterMismatchNoverLmax 0.1 \
		--alignIntronMin 20 \
		--alignIntronMax 1000000 \
		--alignMatesGapMax 1000000 \
		--outFilterType BySJout \
		--outFilterScoreMinOverLread 0.33 \
		--outFilterMatchNminOverLread 0.33 \
		--limitSjdbInsertNsj 1200000 \
		--outFileNamePrefix ${File_ID}. \
		--outSAMstrandField intronMotif \
		--outFilterIntronMotifs None \
		--alignSoftClipAtReferenceEnds Yes \
		--quantMode TranscriptomeSAM GeneCounts \
		--outSAMtype BAM Unsorted SortedByCoordinate \
		--outWigType wiggle \
		--outSAMunmapped Within \
		--genomeLoad NoSharedMemory \
		--chimSegmentMin 15 \
		--chimJunctionOverhangMin 15 \
		--chimOutType Junctions SeparateSAMold WithinBAM SoftClip \
		--chimOutJunctionFormat 1 \
		--chimMainSegmentMultNmax 1 \
		--outSAMattributes NH HI AS nM NM ch

	"""
}



process perform_salmon {
    tag "${Sample_ID}"
	publishDir "${params.outdir}/salmon/", pattern: "${File_ID}**", mode:'copy'
	publishDir "${params.logdir}/salmon/${File_ID}", pattern: '.command*', mode:'copy'

    input:
	tuple val(Case_ID), val(Sample_ID), val(File_ID), val(File_Name)
	path transcriptome_alignment

    output:
	tuple val(Case_ID), val(Sample_ID), val(File_ID), val(File_Name), emit: metadata
	path "${File_ID}*", emit: salmon_results
	path ".command*", emit: logs

    script:
    """
	echo "Case_ID: ${Case_ID}"
	echo "Sample_ID: ${Sample_ID}"
	echo "File_ID: ${File_ID}"
	echo "File_Name: ${File_Name}"

	salmon quant \
				--targets "${params.transcriptome_fasta}" \
				--geneMap "${params.gtf_file}" \
				--gencode \
				--libType IU \
				--threads 16 \
				--alignments "${transcriptome_alignment}" \
				--output "${File_ID}"
	
    """
}


process perform_tximeta {
    tag "tximeta"
	publishDir "${params.outdir}/tximeta/", pattern: "*summarized_experiment_object.RDS", mode:'copy'
	publishDir "${params.logdir}/tximeta/", pattern: '.command*', mode:'copy'
	publishDir "${params.outdir}/salmon/", pattern: "**meta_info_with_seq_hash.json", mode:'copy'

    input:
	val File_IDs
	path salmon_results
	val seq_hash

    output:
	path "*summarized_experiment_object.RDS", emit: se_objects
	path ".command*", emit: logs
	path "**meta_info_with_seq_hash.json", emit: meta_info_with_seq_hash

    script:
    """
	export R_USER_CACHE_DIR=${params.R_USER_CACHE_DIR}
	export R_USER_CONFIG_DIR=${params.R_USER_CONFIG_DIR}
	export R_USER_DATA_DIR=${params.R_USER_DATA_DIR}

	file_ids="${File_IDs}"
	file_id_list="\${file_ids%]}"
	file_id_list="\${file_id_list#[}"
	
	IFS=, read -ra file_id_array <<< "\${file_id_list}"
	file_id_array=("\${file_id_array[@]# }")

	python3 "${params.scriptdir}/update_meta_info.py" "\${PWD}" \${file_id_array[@]} --new_index_seq_hash "${seq_hash["value"]}" --update_json_dir "${params.scriptdir}"
	Rscript "${params.scriptdir}/perform_tximeta.R" "${workflow.projectDir}" "\${PWD}" "${params.bam_metadata}" \${file_id_array[@]}

    """
}



/* 
 * main script flow
 */
 
workflow {

	// Read input
	bam_files = Channel
        .fromPath(params.bam_metadata, checkIfExists: true)
        .splitCsv( header: true )
        .map { item ->
            tuple(
				item.Case_ID,
				item.Sample_ID,
                item.File_ID,
                item.File_Name,
            )
        }


	// Perform conversion to fastq
	bam_to_fastq(bam_files, params.bam_dir)

	// Perform fastqc
	perform_fastqc(
		bam_to_fastq.out.metadata,
		bam_to_fastq.out.fastq_files
	)

	// Perform multiqc
	fastqc_results = perform_fastqc.out.fastqc_results.collect()
	perform_multiqc(fastqc_results)
  
	// Perform STAR
	fastq_pair = bam_to_fastq.out.fastq_files.map{
		R1, R2, _S -> tuple(R1, R2) 
	}

	perform_STAR(
		bam_to_fastq.out.metadata,
		fastq_pair,
		params.star_index_dir
	)

	// Perform salmon alignment mode quantification
	perform_salmon(
		perform_STAR.out.metadata,
		perform_STAR.out.STAR_aligned_to_transcriptome
	)
  
	// Perform tximeta to import from salmon output
	file_ids = perform_salmon.out.metadata
        .map { _Case_ID, _Sample_ID, File_ID, _File_Name -> File_ID }
        .collect()

	salmon_results = perform_salmon.out.salmon_results.collect()

	seq_hash = Channel
		.fromPath(params.transcriptome_fasta_digest, checkIfExists: true)
		.splitJson()
		.filter { it.key == 'seq_hash' }

	perform_tximeta(
		file_ids,
		salmon_results,
		seq_hash
	)
  
}
