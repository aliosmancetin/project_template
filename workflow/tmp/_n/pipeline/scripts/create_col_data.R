.libPaths(unique(c("~/.guix-profile/site-library", .libPaths())))

library(tidyverse)

root <- "/fast/AG_Gargiulo/AC/projects/preprocessing_projects/GG_MS23_20240412_BRB_seq/pipeline"

pool1 <- readxl::read_xlsx(paste0(root, "/input/col_data/pool1.xlsx"), col_names = TRUE)

pool1 <- pool1 %>%
  dplyr::mutate(
    names = Index,
    pool_name = "A4304_brbseqMS_PS_1_S6",
    pool_id = "pool_1",
    sample_name = str_replace_all(.data$`Sample NAME`, " \\+ | \\- | ", "_")) %>%
  dplyr::relocate(names, sample_name, pool_name, pool_id)

write.table(
  pool1,
  file = paste0(root, "/input/col_data/A4304_brbseqMS_PS_1_S6_col_data.tsv"),
  col.names = TRUE, row.names = FALSE, quote = FALSE, sep = "\t"
)

pool1_barcode_name_table <- pool1 %>%
  dplyr::select(names, sample_name)

write.table(
  pool1_barcode_name_table,
  file = paste0(root, "/input/barcode_name_tables/A4304_brbseqMS_PS_1_S6_barcode_name_table.tsv"),
  col.names = FALSE, row.names = FALSE, quote = FALSE, sep = "\t"
)



pool2 <- readxl::read_xlsx(paste0(root, "/input/col_data/pool2.xlsx"), col_names = TRUE)

pool2 <- pool2 %>%
  dplyr::mutate(
    names = Index,
    pool_name = "A4304_brbseqMS_PS_2_S7",
    pool_id = "pool_2",
    sample_name = str_replace_all(.data$`Sample NAME`, " \\+ | \\- | ", "_")) %>%
  dplyr::relocate(names, sample_name, pool_name, pool_id)

write.table(
  pool2,
  file = paste0(root, "/input/col_data/A4304_brbseqMS_PS_2_S7_col_data.tsv"),
  col.names = TRUE, row.names = FALSE, quote = FALSE, sep = "\t"
)

pool2_barcode_name_table <- pool2 %>%
  dplyr::select(names, sample_name)

write.table(
  pool2_barcode_name_table,
  file = paste0(root, "/input/barcode_name_tables/A4304_brbseqMS_PS_2_S7_barcode_name_table.tsv"),
  col.names = FALSE, row.names = FALSE, quote = FALSE, sep = "\t"
)


