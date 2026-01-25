#!/usr/bin/env Rscript
# Generate system requirements for all test packages using pkgdepends
# Excludes GDAL/GEOS/PROJ since we supply bleeding edge versions

library(pkgdepends)

args <- commandArgs(trailingOnly = TRUE)
output_file <- if (length(args) >= 1) args[1] else "config/sysreqs.txt"
platform <- if (length(args) >= 2) args[2] else "ubuntu-24.04"

cat("=== Generating system requirements ===\n")
cat(sprintf("Platform: %s\n", platform))

# Load seed packages
seed_pkgs <- readLines("config/seed_packages.txt")
seed_pkgs <- seed_pkgs[nzchar(trimws(seed_pkgs))]

cat(sprintf("Seed packages: %s\n", paste(seed_pkgs, collapse = ", ")))

# Get reverse deps (what we'll test)
db <- tools::CRAN_package_db()
revdeps <- tools::package_dependencies(
  seed_pkgs, db = db,
  reverse = TRUE,
  which = c("Depends", "Imports", "LinkingTo"),
  recursive = FALSE
)
test_pkgs <- unique(c(seed_pkgs, unlist(revdeps)))

cat(sprintf("Resolving sysreqs for %d packages...\n", length(test_pkgs)))

# Resolve with pkgdepends
pd <- new_pkg_deps(test_pkgs, config = list(sysreqs_platform = platform))
pd$resolve()
res <- pd$get_resolution()

# Extract unique install commands
sysreqs <- unique(res$sysreqs_install[nzchar(res$sysreqs_install)])

# Parse out individual packages
apt_pkgs <- unlist(strsplit(
  gsub("apt-get -y install\\s*", "", sysreqs),
  "\\s+"
))
apt_pkgs <- unique(apt_pkgs[nzchar(apt_pkgs)])

cat(sprintf("Found %d system packages\n", length(apt_pkgs)))

# Exclude packages we supply via GDAL image (bleeding edge)
exclude <- c(
  "libgdal-dev", "gdal-bin",      # GDAL
  "libgeos-dev", "libgeos++-dev", # GEOS

  "libproj-dev",                  # PROJ
  "libsqlite3-dev"                # often bundled, but check if needed
)

excluded <- intersect(apt_pkgs, exclude)
apt_pkgs <- setdiff(apt_pkgs, exclude)

if (length(excluded) > 0) {
  cat(sprintf("Excluded (supplied by GDAL image): %s\n", paste(excluded, collapse = ", ")))
}

cat(sprintf("Final: %d system packages\n", length(apt_pkgs)))

# Write install script
install_cmd <- sprintf(
  "apt-get update && apt-get install -y --no-install-recommends \\\n    %s",
  paste(sort(apt_pkgs), collapse = " \\\n    ")
)

writeLines(install_cmd, output_file)
cat(sprintf("Wrote: %s\n", output_file))

# Also write a simple list for reference
writeLines(sort(apt_pkgs), sub("\\.txt$", "_list.txt", output_file))
