#!/usr/bin/env Rscript
# summary_cache_build.R - Quick status check for gdalcheck image

cat("=== gdalcheck image status ===\n\n")

# Build info
if (file.exists("/opt/build_summary.json")) {
  summary <- jsonlite::fromJSON("/opt/build_summary.json")
  cat(sprintf("Built: %s\n", summary$built_at))
  cat(sprintf("Seeds: %s\n", paste(summary$seed_packages, collapse = ", ")))
  cat(sprintf("Test packages: %d\n", summary$test_packages))
  cat(sprintf("Cached packages: %d\n", summary$cached_packages))
  if (!is.null(summary$bonus_packages)) {
    cat(sprintf("Bonus deps: %d\n", summary$bonus_packages))
  }
  cat(sprintf("Total installed: %d\n", summary$total_installed))
  cat(sprintf("Failed: %d\n", summary$failed_packages))
  cat(sprintf("Layers: %d (%.2f GB)\n", summary$num_layers, summary$total_size_gb))
} else {
  cat("WARNING: /opt/build_summary.json not found\n")
}

# Actual packages
site_lib <- "/usr/local/lib/R/site-library"
installed <- length(list.dirs(site_lib, recursive = FALSE))
cat(sprintf("\nActual in site-library: %d\n", installed))

# Key packages - gdalraster first as canonical
key_pkgs <- c("gdalraster", "vapour", "sf", "terra", "stars", "gdalcubes",
              "raster", "tmap", "mapview", "wk")
cat("\nSeed packages:\n")
for (pkg in key_pkgs) {
  if (dir.exists(file.path(site_lib, pkg))) {
    ver <- tryCatch(
      as.character(packageVersion(pkg, lib.loc = site_lib)),
      error = function(e) "?"
    )
    cat(sprintf("  ✓ %s %s\n", pkg, ver))
  } else {
    cat(sprintf("  ✗ %s (not installed)\n", pkg))
  }
}

# Versions
cat("\nSystem:\n")
cat(sprintf("  R: %s\n", R.version.string))

# Use gdalraster as canonical source
tryCatch({
  suppressMessages(library(gdalraster, lib.loc = site_lib, quietly = TRUE))
  cat(sprintf("  GDAL: %s\n", gdal_version()[[4]]))
  cat(sprintf("  PROJ: %s\n", proj_version()$name))
  cat(sprintf("  GEOS: %s\n", geos_version()$name))
}, error = function(e) {
  # Fallback to gdal-config
  cat(sprintf("  GDAL: %s\n", system("gdal-config --version", intern = TRUE)))
  cat(sprintf("  PROJ: %s\n", system("pkg-config --modversion proj", intern = TRUE)))
  cat(sprintf("  GEOS: %s\n", system("geos-config --version", intern = TRUE)))
})
