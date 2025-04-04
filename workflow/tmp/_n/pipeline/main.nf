#!/bin/env nextflow

nextflow.enable.dsl = 2


process perform_fastqc {
    tag "${Pool}"
	publishDir "${params.outdir}/fastqc/${Pool}/", pattern: "*fastqc.{html,zip}", mode:'symlink'
	publishDir "${params.logdir}/fastqc/${Pool}/", pattern: '.command*', mode:'symlink'

    input:
	tuple val(Pool), path(Barcodes), path(Read1), path(Read2)

    output:
	tuple val(Pool), path(Barcodes), path(Read1), path(Read2), emit: fastq_files
	path "*fastqc.{html,zip}", emit: fastqc_results
	path ".command*", emit: logs

    script:
	"""
	echo "Pool: ${Pool}"

    fastqc -t 80 "${Read1}" "${Read2}"

	"""
}



process perform_STAR {
    tag "${Pool}"
    publishDir "${params.outdir}/STAR/${Pool}", pattern: "${Pool}**", mode:'symlink'
	publishDir "${params.logdir}/STAR/${Pool}", pattern: '.command*', mode:'symlink'

    input:
	tuple val(Pool), path(Barcodes), path(Read1), path(Read2)
	val STAR_index_dir

    output:
	tuple val(Pool), path(Barcodes), emit: Pool_Barcodes
	path "${Pool}.Aligned.toTranscriptome.out.bam", emit: STAR_aligned_to_transcriptome
	path "${Pool}.Aligned.sortedByCoord.out.bam", emit: STAR_aligned_sorted
	path "${Pool}.Aligned.out.bam", emit: STAR_aligned
	path "${Pool}**", emit: STAR_results
	path ".command*", emit: logs

// Read2 Read1 is not a mistake, this is the correct configuration for STARsolo
    script:
	"""
	echo "Pool: ${Pool}"

	STAR \
		--readFilesIn "${Read2}" "${Read1}" \
		--genomeDir "${STAR_index_dir}" \
		--readFilesCommand zcat \
		--outFileNamePrefix "${Pool}." \
		--twopassMode Basic \
		--quantMode TranscriptomeSAM \
		--outSAMtype BAM Unsorted SortedByCoordinate \
		--outSAMunmapped Within \
		--outReadsUnmapped Fastx \
		--outSAMattributes NH HI nM AS CR UR CB GX GN sS sQ sM cN \
		--outFilterScoreMinOverLread 0.33 \
		--outFilterMatchNminOverLread 0.33 \
		--clip3pAdapterSeq polyA \
		--clip3pAdapterMMp 0.1 \
		--soloType CB_samTagOut \
		--soloStrand Forward \
		--soloCBwhitelist "${Barcodes}" \
		--soloUMIdedup NoDedup \
		--soloCBmatchWLtype 1MM \
		--soloCBstart 10 \
		--soloCBlen 11 \
		--soloUMIstart 1 \
		--soloUMIlen 9 \
		--soloBarcodeReadLength 28 \
		--soloCellFilter None \
		--soloFeatures Gene \
		--runThreadN 80

	"""
}


process split_bam {
    tag "${Pool}"
	publishDir "${params.outdir}/split_bam/${Pool}", pattern: "${Pool}*", mode:'symlink'
	publishDir "${params.outdir}/split_bam/${Pool}", pattern: "bam_named", mode:'symlink' // "bam_named/${Pool}.Aligned.sortedByCoord.out*"
	publishDir "${params.outdir}/split_bam/${Pool}", pattern: "flagstats", mode:'symlink'
	publishDir "${params.logdir}/split_bam/${Pool}", pattern: '.command*', mode:'symlink'

    input:
	tuple val(Pool), path(Barcodes)
	path STAR_aligned_to_transcriptome
	path STAR_aligned_sorted
	//path STAR_aligned

    output:
	tuple val(Pool), path(Barcodes), emit: Pool_Barcodes
	path "${Pool}.Aligned.toTranscriptome.out_[ACGT][ACGT][ACGT][ACGT][ACGT][ACGT][ACGT][ACGT][ACGT][ACGT][ACGT].bam", emit: transcriptome_alignment
	path "${Pool}.Aligned.toTranscriptome.out.no_barcode_assignment.bam", emit: unassigned_reads
	path "bam_named", emit: bam_named, type: 'dir' // path "bam_named/${Pool}.Aligned.sortedByCoord.out*", emit: bams_named
	path "flagstats", emit: flagstats, type: 'dir'
	path ".command*", emit: logs

    script:
    """
	echo "Pool: ${Pool}"
	threads=80

	bam_file_array=("${STAR_aligned_to_transcriptome}" "${STAR_aligned_sorted}")
	bam_folder_array=(".Aligned.toTranscriptome.out." ".Aligned.sortedByCoord.out.")
	
	# Index transcriptome aligned bam file
	samtools index -@ "\${threads}" ${STAR_aligned_sorted}
	

	for index in "\${!bam_file_array[@]}"; do
		samtools split -d CB -v -@ "\${threads}" -M -1 -u "${Pool}\${bam_folder_array[\${index}]}no_barcode_assignment.bam" "\${bam_file_array[\${index}]}"
	done
	
	
	# Index all the sorted bam files
	sorted_bam_array=(\$(ls "${Pool}".Aligned.sortedByCoord.out[._]*.bam))
	
	for sorted_bam in "\${sorted_bam_array[@]}"; do
		samtools index -@ "\${threads}" \${sorted_bam}
	done


	# Create flagstats for each bam file
	mkdir flagstats

	for bam in *Aligned.sortedByCoord.out*.bam; do
    	samtools flagstat -@ "\${threads}" -O tsv "\${bam}" > "flagstats/\${bam%.bam}.flagstat.tsv"
		unique=\$(samtools view -@ "\${threads}" -c -q 255 "\${bam}")
		echo -e "\${unique}\t0\tuniquely mapped" >> "flagstats/\${bam%.bam}.flagstat.tsv"
	done
	

	# Create a named bam file for each barcode as a symlink
	mkdir -p bam_named
	
	while IFS=\$',' read -r sample barcode pool; do
		if [ "\${pool}" == "${Pool}" ]; then
			cp -s "\${PWD}"/"${Pool}".Aligned.sortedByCoord.out_"\${barcode}".bam* bam_named
			mv -T bam_named/"${Pool}".Aligned.sortedByCoord.out_"\${barcode}".bam bam_named/"${Pool}".Aligned.sortedByCoord.out."\${sample}".bam
			mv -T bam_named/"${Pool}".Aligned.sortedByCoord.out_"\${barcode}".bam.bai bam_named/"${Pool}".Aligned.sortedByCoord.out."\${sample}".bam.bai
		else continue
		fi
	done < "${params.barcode_table}"
	
    """
}


process perform_salmon {
    tag "${Pool}_${Barcode}"
	publishDir "${params.outdir}/salmon/${Pool}/", pattern: "${Barcode}", mode:'copy'
	publishDir "${params.logdir}/salmon/${Pool}/${Barcode}", pattern: '.command*', mode:'copy'

    input:
	tuple path(transcriptome_alignment), val(Pool), val(Barcode)

    output:
	tuple val(Pool), val(Barcode), path("${Barcode}", type: 'dir'), emit: salmon_results
	// path "${Barcode}", emit: salmon_results, type: 'dir'
	path ".command*", emit: logs

    script:
    """
	echo "Pool: ${Pool}"
	echo "Barcode: ${Barcode}"

	salmon quant \
				--targets "${params.transcriptome_fasta}" \
				--geneMap "${params.gtf_file}" \
				--gencode \
				--threads 16 \
				--libType SF \
				--noLengthCorrection \
				--alignments "${transcriptome_alignment}" \
				--output "${Barcode}"
	
    """
}


process perform_tximeta {
    tag "${pool}"
	publishDir "${params.outdir}/tximeta/${pool}", pattern: "*summarized_experiment_object.rds", mode:'copy'
	publishDir "${params.logdir}/tximeta/${pool}", pattern: '.command*', mode:'symlink'
	publishDir "${params.outdir}/salmon/${pool}", pattern: "**meta_info_with_seq_hash.json", mode:'symlink'

    input:
	tuple val(pool), val(barcodes), path(salmon_results), val(seq_hash)
	
    output:
	path "*summarized_experiment_object.rds", emit: se_objects
	path ".command*", emit: logs
	path "**meta_info_with_seq_hash.json", emit: meta_info_with_seq_hash

    script:
    """
	export R_USER_CACHE_DIR=${params.R_USER_CACHE_DIR}
	export R_USER_CONFIG_DIR=${params.R_USER_CONFIG_DIR}
	export R_USER_DATA_DIR=${params.R_USER_DATA_DIR}

	echo "Pool: ${pool}"
	echo "Barcodes: ${barcodes}"

	barcodes_="${barcodes}"
	barcodes_list="\${barcodes_%]}"
	barcodes_list="\${barcodes_list#[}"
	
	IFS=, read -ra barcodes_array <<< "\${barcodes_list}"
	barcodes_array=("\${barcodes_array[@]# }")

	python3 "${params.scriptdir}/update_meta_info.py" \
			"\${PWD}" \
			\${barcodes_array[@]} \
			--new_index_seq_hash "${seq_hash["value"]}" \
			--update_json_dir "${params.scriptdir}"

	Rscript "${params.scriptdir}/perform_tximeta.R" \
			"${workflow.projectDir}" \
			"\${PWD}" \
			"${params.barcode_table}" \
			\${barcodes_array[@]}

    """
}



/* 
 * main script flow
 */
 
workflow {

	// Read input
	fastq_files = Channel
        .fromPath(params.file_table, checkIfExists: true)
        .splitCsv( header: true )
        .map { item ->
            tuple(
				item.Pool,
				item.Barcodes,
				item.Read1,
                item.Read2
            )
        }

	// Perform fastqc
	perform_fastqc(fastq_files)
  
	// Perform STAR
	perform_STAR(
		perform_fastqc.out.fastq_files,
		params.star_index_dir
	)

	// Perform split_bam
	split_bam(
		perform_STAR.out.Pool_Barcodes,
		perform_STAR.out.STAR_aligned_to_transcriptome,
		perform_STAR.out.STAR_aligned_sorted
	)


	// Flatten trans_align_bams output from split_bam
  	transcriptome_alignment = split_bam.out.transcriptome_alignment
		.flatten()
		.map { it ->
			tuple(
				it,
				it.name.replaceAll(~/\.Aligned\.toTranscriptome\.out_[ACGT]{11}\.bam/, ""), // Pool
				it.name.replaceAll(~/\.bam/, "").replaceAll(~/.*\.Aligned\.toTranscriptome\.out_/, "") // Barcode
			)
		}
		//.view()
	

	// Perform salmon alignment mode quantification
	perform_salmon(
		transcriptome_alignment
	)
  
	// Perform tximeta to import from salmon output
	salmon_results = perform_salmon.out.salmon_results
		.groupTuple()

	seq_hash = Channel
		.fromPath(params.transcriptome_fasta_digest, checkIfExists: true)
		.splitJson()
		.filter { it.key == 'seq_hash' }

	perform_tximeta(
		salmon_results.combine(seq_hash)
	)
  
}
