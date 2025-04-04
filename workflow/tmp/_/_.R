library(tidyverse)


out_dir <- file.path(
  "output",
  "intermediate",
  "____"
)

dir.create(
  out_dir,
  showWarnings = FALSE,
  recursive = TRUE
)




.libPaths()

sessionInfo()
