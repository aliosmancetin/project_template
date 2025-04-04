library(tidyverse)

# Take the file paths as command line arguments. This is --input_line option
args <- R.utils::commandArgs(trailingOnly = TRUE, asValues = TRUE)

input_file_path <- args[["input_line"]]



.libPaths()

sessionInfo()
