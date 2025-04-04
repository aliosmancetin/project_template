library(tidyverse)


out_dir <- file.path(
  "output",
  "____"
)

dir.create(
  out_dir,
  showWarnings = FALSE,
  recursive = TRUE
)




.libPaths()

sessionInfo()
