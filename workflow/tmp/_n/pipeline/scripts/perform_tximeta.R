library(tidyverse)
library(tximeta)

args <- commandArgs(trailingOnly = TRUE)

pipeline_dir <- args[1]
workdir <- args[2]
col_data_path <- args[3]

file_ids <- args[!args %in% c(pipeline_dir, workdir, col_data_path)]
files <- paste0(workdir, "/", file_ids, "/quant.sf")

print(file_ids)

file_df <- data.frame(
  files = files,
  names = file_ids,
  row.names = NULL
)

col_data <- read_csv(
  file = col_data_path,
  col_names = TRUE
)

col_data <- col_data %>%
  dplyr::right_join(file_df, by = join_by(Barcode == names), keep = TRUE) %>%
  dplyr::relocate(files, names)


se <- tximeta(
  col_data,
  customMetaInfo = "aux_info/meta_info_with_seq_hash.json",
  useHub = TRUE
)

se_gene <- summarizeToGene(
  se,
  assignRanges = "abundant",
  countsFromAbundance = "no"
)

saveRDS(
  se,
  file = "summarized_experiment_object.rds"
)

saveRDS(
  se_gene,
  file = "gene_summarized_experiment_object.rds"
)

sessionInfo()
