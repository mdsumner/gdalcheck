#!/bin/bash
# Check a single R package against bleeding-edge GDAL
# Usage: check_one.sh <package_name> <results_dir>

set -euo pipefail

PKG="${1:?Package name required}"
RESULTS_DIR="${2:-/results}"

mkdir -p "$RESULTS_DIR"

echo "=== Checking $PKG ==="

# Run the check
Rscript --vanilla << EOF
pkg <- "$PKG"
results_dir <- "$RESULTS_DIR"

library(jsonlite)

# Get GDAL version
gdal_version <- tryCatch(
  terra::gdal_version(),
  error = function(e) tryCatch(
    sf::sf_extSoftVersion()["GDAL"],
    error = function(e) "unknown"
  )
)

result <- list(
  package = pkg,
  status = "OK",
  gdal_version = as.character(gdal_version),
  timestamp = as.character(Sys.time()),
  error = NULL
)

tryCatch({
  # Download package
  url <- available.packages(repos = "https://cloud.r-project.org")[pkg, "Repository"]
  tarball <- download.packages(pkg, destdir = tempdir(), repos = "https://cloud.r-project.org")[1, 2]
  
  # Check it
  check_dir <- file.path(tempdir(), paste0(pkg, ".Rcheck"))
  
  check_result <- tools::R_CMD_check(
    tarball,
    check_dir = tempdir(),
    args = c("--no-manual", "--no-vignettes", "--no-build-vignettes")
  )
  
  # Look for failures
  log_file <- file.path(check_dir, "00check.log")
  if (file.exists(log_file)) {
    log_content <- readLines(log_file, warn = FALSE)
    
    # Check for ERROR or FAIL
    if (any(grepl("^Status:.*ERROR", log_content)) || 
        any(grepl("^Status:.*FAIL", log_content))) {
      result\$status <- "FAIL"
      # Capture last 50 lines as context
      result\$error <- paste(tail(log_content, 50), collapse = "\n")
    } else if (any(grepl("^Status:.*WARNING", log_content))) {
      result\$status <- "WARN"
    }
  }
  
}, error = function(e) {
  result\$status <<- "ERROR"
  result\$error <<- conditionMessage(e)
})

# Write result
outfile <- file.path(results_dir, paste0(pkg, ".json"))
write_json(result, outfile, pretty = TRUE, auto_unbox = TRUE)

cat(sprintf("Result: %s\n", result\$status))
EOF

echo "=== Done $PKG ==="
