#!/usr/bin/env Rscript
# Generate system requirements for all test packages using pkgdepends.
#
# Excludes packages already provided by ghcr.io/hypertidy/gdal-r-full:
#   - GDAL, GEOS, PROJ (built from source in gdal-system)
#   - HDF5, NetCDF, Arrow, SpatiaLite, PostgreSQL (in gdal-system)
#   - libcurl, libssl, libxml2, libpng, libjpeg, libtiff (in gdal-system)
#   - libudunits2, libabsl (in gdal-r)
#   - libharfbuzz, libfribidi, libfontconfig, libfreetype (in gdal-r)

library(pkgdepends)

args <- commandArgs(trailingOnly = TRUE)
output_file <- if (length(args) >= 1) args[1] else "config/sysreqs.txt"
platform    <- if (length(args) >= 2) args[2] else "ubuntu-24.04"

cat("=== Generating system requirements ===\n")
cat(sprintf("Platform: %s\n", platform))

seed_pkgs <- readLines("config/seed_packages.txt")
seed_pkgs <- seed_pkgs[nzchar(trimws(seed_pkgs))]
cat(sprintf("Seed packages: %s\n", paste(seed_pkgs, collapse = ", ")))

db <- tools::CRAN_package_db()
revdeps <- tools::package_dependencies(
  seed_pkgs, db = db,
  reverse = TRUE,
  which = c("Depends", "Imports", "LinkingTo"),
  recursive = FALSE
)
test_pkgs <- unique(c(seed_pkgs, unlist(revdeps)))
cat(sprintf("Resolving sysreqs for %d packages...\n", length(test_pkgs)))

pd <- new_pkg_deps(test_pkgs, config = list(sysreqs_platform = platform))
pd$resolve()
res <- pd$get_resolution()

sysreqs  <- unique(res$sysreqs_install[nzchar(res$sysreqs_install)])
apt_pkgs <- unlist(strsplit(
  gsub("apt-get -y install\\s*", "", sysreqs), "\\s+"
))
apt_pkgs <- unique(apt_pkgs[nzchar(apt_pkgs)])
cat(sprintf("Found %d system packages\n", length(apt_pkgs)))

# Packages provided by gdal-r-full (gdal-system + gdal-r layers)
already_provided <- c(
  # gdal-system: geo libraries built from source
  "libgdal-dev", "gdal-bin",
  "libgeos-dev", "libgeos++-dev",
  "libproj-dev",
  # gdal-system: format libraries
  "libhdf5-dev", "libnetcdf-dev", "netcdf-bin",
  "libarrow-dev", "libparquet-dev",
  "libspatialite-dev", "librasterlite2-dev",
  "libpq-dev", "libmysqlclient-dev",
  "libkml-dev", "libxerces-c-dev",
  "libpoppler-dev", "libpoppler-private-dev",
  "libcfitsio-dev", "libfreexl-dev",
  "libopenjp2-7-dev", "libwebp-dev",
  "libblosc-dev", "libzstd-dev", "liblz4-dev", "liblerc-dev",
  "libdeflate-dev", "liblzma-dev",
  "libsqlite3-dev", "sqlite3",
  "libcurl4-openssl-dev", "libssl-dev",
  "libxml2-dev", "libexpat1-dev",
  "libpng-dev", "libjpeg-turbo8-dev", "libjpeg-dev",
  "libgif-dev", "libtiff-dev",
  "libspdlog-dev",
  # gdal-r: R build and geo deps
  "libudunits2-dev",
  "libabsl-dev",
  "libharfbuzz-dev", "libfribidi-dev",
  "libfontconfig1-dev", "libfreetype6-dev",
  "pandoc", "qpdf",
  "build-essential", "cmake", "git", "wget", "curl",
  "pkg-config", "software-properties-common"
)

excluded <- intersect(apt_pkgs, already_provided)
apt_pkgs <- setdiff(apt_pkgs, already_provided)

if (length(excluded) > 0) {
  cat(sprintf("Excluded (already in gdal-r-full): %s\n",
              paste(sort(excluded), collapse = ", ")))
}
cat(sprintf("Final: %d additional system packages\n", length(apt_pkgs)))

install_cmd <- sprintf(
  "apt-get update -qq && apt-get install -y --no-install-recommends \\\n    %s",
  paste(sort(apt_pkgs), collapse = " \\\n    ")
)

writeLines(install_cmd, output_file)
writeLines(sort(apt_pkgs), sub("\\.txt$", "_list.txt", output_file))
cat(sprintf("Wrote: %s\n", output_file))
