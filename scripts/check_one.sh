#!/bin/bash
# check_one.sh - Run R CMD check on a single CRAN package
# Usage: check_one.sh <package> <results_dir>

set -euo pipefail

PKG="$1"
RESULTS_DIR="${2:-/results}"

mkdir -p "$RESULTS_DIR"

# Get GDAL version for metadata
GDAL_VERSION=$(gdal-config --version 2>/dev/null || echo "unknown")

# Run check via rcmdcheck and output JSON
Rscript --vanilla -e "
library(rcmdcheck)
library(jsonlite)

pkg <- '${PKG}'
results_dir <- '${RESULTS_DIR}'
gdal_version <- '${GDAL_VERSION}'

# Download and check
tryCatch({
  # Create temp dir for check
  check_dir <- tempdir()
  
  # Download package
  url <- paste0('https://cran.r-project.org/src/contrib/', pkg, '_', 
                available.packages()[pkg, 'Version'], '.tar.gz')
  destfile <- file.path(check_dir, basename(url))
  
  download.file(url, destfile, quiet = TRUE)
  
  # Run check
  start_time <- Sys.time()
  res <- rcmdcheck(destfile, quiet = TRUE, args = '--no-manual')
  end_time <- Sys.time()
  
  # Determine status
  status <- if (length(res\$errors) > 0) {
    'ERROR'
  } else if (length(res\$warnings) > 0) {
    'WARNING'
  } else {
    'OK'
  }
  
  # Build result
  result <- list(
    package = pkg,
    version = res\$version,
    status = status,
    errors = length(res\$errors),
    warnings = length(res\$warnings),
    notes = length(res\$notes),
    error_messages = if (length(res\$errors) > 0) res\$errors else NULL,
    warning_messages = if (length(res\$warnings) > 0) res\$warnings else NULL,
    check_time_secs = as.numeric(difftime(end_time, start_time, units = 'secs')),
    gdal_version = gdal_version,
    r_version = paste(R.version\$major, R.version\$minor, sep = '.'),
    timestamp = format(Sys.time(), '%Y-%m-%dT%H:%M:%SZ', tz = 'UTC')
  )
  
  # Write JSON
  outfile <- file.path(results_dir, paste0(pkg, '.json'))
  write_json(result, outfile, pretty = TRUE, auto_unbox = TRUE)
  
  cat(sprintf('%s: %s (%d errors, %d warnings, %d notes)\n', 
              pkg, status, length(res\$errors), length(res\$warnings), length(res\$notes)))
  
}, error = function(e) {
  result <- list(
    package = pkg,
    version = NA,
    status = 'FAIL',
    errors = 1,
    warnings = 0,
    notes = 0,
    error_messages = list(conditionMessage(e)),
    gdal_version = gdal_version,
    r_version = paste(R.version\$major, R.version\$minor, sep = '.'),
    timestamp = format(Sys.time(), '%Y-%m-%dT%H:%M:%SZ', tz = 'UTC')
  )
  
  outfile <- file.path(results_dir, paste0(pkg, '.json'))
  write_json(result, outfile, pretty = TRUE, auto_unbox = TRUE)
  
  cat(sprintf('%s: FAIL (%s)\n', pkg, conditionMessage(e)))
})
"
