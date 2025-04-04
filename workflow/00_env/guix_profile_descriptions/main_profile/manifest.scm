;; This "manifest" file can be passed to 'guix package -m' to reproduce
;; the content of your profile.  This is "symbolic": it only specifies
;; package names.  To reproduce the exact same profile, you also need to
;; capture the channels being used, as returned by "guix describe".
;; See the "Replicating Guix" section in the manual.

(specifications->manifest
  (list
  	"r-biostrings"
	"r-biomart"
	"r-plyranges"
	"r-gsva"
	"r-complexheatmap"
	"r-ggrepel"
	"r-ggpubr"
	"r-ggpmisc"
	"r-summarizedexperiment"
	"r-biocmanager"
	"r-tidyverse"
	"rstudio-server"
	"r"
	"rstudio-server"
	"procps"
	"nss-certs"
	"wget"
	"curl"
	"gnutls"
	"grep"
	"sed"
	"gawk"
	"gzip"
	"tar"
	"diffutils"
	"findutils"
	"coreutils"
	"gcc-toolchain"
	"bash"
  )
)
