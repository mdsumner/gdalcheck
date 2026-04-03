#!/usr/bin/env Rscript
# scripts/R/summary_cache_build.R
# Quick status check for gdalcheck image

cat("=== gdalcheck image status ===\n\n")

# Build info
if (file.exists("/opt/build_summary.json")) {
  summary <- jsonlite::fromJSON("/opt/build_summary.json")
  cat(sprintf("Built: %s\n", summary$built_at))
  cat(sprintf("Seeds: %s\n", paste(summary$seed_packages, collapse = ", ")))
  cat(sprintf("Cached: %d packages\n", summary$cached_packages))
  cat(sprintf("Test manifest: %d packages\n", summary$test_packages))
  cat(sprintf("Layers: %d (%.2f GB)\n", summary$num_layers, summary$total_size_gb))
} else {
  cat("WARNING: /opt/build_summary.json not found\n")
}

# Actual packages
site_lib <- "/usr/local/lib/R/site-library"
installed <- length(list.dirs(site_lib, recursive = FALSE))
cat(sprintf("\nInstalled in site-library: %d\n", installed))

# Key packages
key_pkgs <- c("sf", "terra", "stars", "gdalraster", "vapour", "gdalcubes", "raster")
cat("\nKey packages:\n")
for (pkg in key_pkgs) {
  status <- if (dir.exists(file.path(site_lib, pkg))) "✓" else "✗"
  cat(sprintf("  %s %s\n", status, pkg))
}

# Versions
cat("\nVersions:\n")
cat(sprintf("  R: %s\n", R.version.string))
gdal_ver <- tryCatch(
  terra::gdal_version(),
  error = function(e) tryCatch(
    sf::sf_extSoftVersion()["GDAL"],
    error = function(e) "unknown"
  )
)
cat(sprintf("  GDAL: %s\n", gdal_ver))
