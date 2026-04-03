#!/usr/bin/env Rscript
# Build binary cache for GDAL revdep checking
# Partitions packages into layers to stay under Docker layer size limits

library(jsonlite)

args <- commandArgs(trailingOnly = TRUE)
output_dir <- if (length(args) >= 1) args[1] else "/output"
max_layer_gb <- if (length(args) >= 2) as.numeric(args[2]) else 6

cat("=== GDAL Revdep Binary Cache Builder ===\n")
cat(sprintf("Output: %s\n", output_dir))
cat(sprintf("Max layer size: %d GB\n", max_layer_gb))

# Load config
seed_pkgs <- readLines("/config/seed_packages.txt")
seed_pkgs <- seed_pkgs[nzchar(trimws(seed_pkgs))]

cat(sprintf("Seed packages: %s\n", paste(seed_pkgs, collapse = ", ")))

# Use available.packages() for dependency resolution
ap <- available.packages(repos = "https://cloud.r-project.org")

# 1. Get reverse deps (what we'll TEST)
cat("\n--- Finding reverse dependencies ---\n")
revdeps <- tools::package_dependencies(
  seed_pkgs, db = ap,
  reverse = TRUE,
  which = c("Depends", "Imports", "LinkingTo"),
  recursive = FALSE
)
test_pkgs <- unique(unlist(revdeps))
cat(sprintf("Packages to test: %d\n", length(test_pkgs)))

# 2. Get forward deps of test packages (what we need to CACHE)
cat("\n--- Finding install dependencies ---\n")
install_deps <- tools::package_dependencies(
  c(seed_pkgs, test_pkgs), db = ap,
  reverse = FALSE,
  which = c("Depends", "Imports", "LinkingTo"),
  recursive = TRUE
)
cache_pkgs <- unique(c(seed_pkgs, unlist(install_deps)))

# Filter to packages actually on CRAN
cache_pkgs <- intersect(cache_pkgs, rownames(ap))
cat(sprintf("Packages to cache: %d\n", length(cache_pkgs)))

# 3. Install all packages
cat("\n--- Installing packages ---\n")
lib_dir <- file.path(output_dir, "lib_all")
dir.create(lib_dir, recursive = TRUE, showWarnings = FALSE)

# Track failures
failed <- character()
succeeded <- character()

for (i in seq_along(cache_pkgs)) {
  pkg <- cache_pkgs[i]
  cat(sprintf("[%d/%d] %s... ", i, length(cache_pkgs), pkg))

  tryCatch({
    # Skip if already installed
    if (pkg %in% rownames(installed.packages(lib.loc = lib_dir))) {
      cat("already installed\n")
      succeeded <- c(succeeded, pkg)
    } else {
      install.packages(
        pkg,
        lib = lib_dir,
        repos = "https://cloud.r-project.org",
        dependencies = FALSE,
        INSTALL_opts = "--no-multiarch",
        quiet = TRUE
      )
      # Verify it actually installed
      if (dir.exists(file.path(lib_dir, pkg))) {
        cat("OK\n")
        succeeded <- c(succeeded, pkg)
      } else {
        cat("FAILED (no directory created)\n")
        failed <- c(failed, pkg)
      }
    }
  }, error = function(e) {
    cat(sprintf("FAILED: %s\n", conditionMessage(e)))
    failed <<- c(failed, pkg)
  })
}

cat(sprintf("\n--- Install complete: %d succeeded, %d failed ---\n",
            length(succeeded), length(failed)))

if (length(failed) > 0) {
  cat("Failed packages:\n")
  cat(paste(" ", failed, collapse = "\n"), "\n")
  writeLines(failed, file.path(output_dir, "failed_packages.txt"))
}

# 4. Calculate sizes and partition into layers
cat("\n--- Partitioning into layers ---\n")

installed <- list.dirs(lib_dir, recursive = FALSE, full.names = FALSE)
cat(sprintf("Directories in lib_all: %d\n", length(installed)))

pkg_sizes <- sapply(installed, function(p) {
  files <- list.files(file.path(lib_dir, p), recursive = TRUE, full.names = TRUE)
  if (length(files) == 0) return(1)  # Minimum size to ensure inclusion
  sum(file.info(files)$size, na.rm = TRUE)
})

cat(sprintf("Packages with sizes calculated: %d\n", length(pkg_sizes)))

# Sort by size descending (helps pack layers more evenly)
pkg_sizes <- sort(pkg_sizes, decreasing = TRUE)

cat(sprintf("Total size: %.2f GB\n", sum(pkg_sizes) / 1024^3))

# Greedy bin-packing into layers
max_layer_bytes <- max_layer_gb * 1024^3
layers <- list()
layer_sizes <- numeric()

for (pkg in names(pkg_sizes)) {
  size <- pkg_sizes[pkg]
  placed <- FALSE

  # Try to fit in existing layer
  for (i in seq_along(layers)) {
    if (layer_sizes[i] + size <= max_layer_bytes) {
      layers[[i]] <- c(layers[[i]], pkg)
      layer_sizes[i] <- layer_sizes[i] + size
      placed <- TRUE
      break
    }
  }

  # Create new layer if needed
  if (!placed) {
    layers[[length(layers) + 1]] <- pkg
    layer_sizes <- c(layer_sizes, size)
  }
}

cat(sprintf("Created %d layers:\n", length(layers)))
total_in_layers <- 0
for (i in seq_along(layers)) {
  cat(sprintf("  Layer %d: %d packages, %.2f GB\n",
              i, length(layers[[i]]), layer_sizes[i] / 1024^3))
  total_in_layers <- total_in_layers + length(layers[[i]])
}
cat(sprintf("Total packages in layers: %d\n", total_in_layers))

# 5. Move packages into layer directories
cat("\n--- Organizing layer directories ---\n")

copy_failed <- character()
copy_succeeded <- 0

for (i in seq_along(layers)) {
  layer_dir <- file.path(output_dir, sprintf("layer%02d", i))
  dir.create(layer_dir, recursive = TRUE, showWarnings = FALSE)

  for (pkg in layers[[i]]) {
    src <- file.path(lib_dir, pkg)
    dst <- file.path(layer_dir, pkg)

    if (dir.exists(src)) {
      # Use system cp for reliability
      ret <- system2("cp", args = c("-r", src, layer_dir), stdout = FALSE, stderr = FALSE)
      if (ret == 0 && dir.exists(dst)) {
        unlink(src, recursive = TRUE)
        copy_succeeded <- copy_succeeded + 1
      } else {
        cat(sprintf("WARNING: Failed to copy %s (ret=%d, exists=%s)\n", pkg, ret, dir.exists(dst)))
        copy_failed <- c(copy_failed, pkg)
      }
    } else {
      cat(sprintf("WARNING: Source missing for %s\n", pkg))
      copy_failed <- c(copy_failed, pkg)
    }
  }
}

cat(sprintf("Copy results: %d succeeded, %d failed\n", copy_succeeded, length(copy_failed)))

# Verify layer contents
cat("\n--- Verifying layer contents ---\n")
total_verified <- 0
for (i in seq_along(layers)) {
  layer_dir <- file.path(output_dir, sprintf("layer%02d", i))
  actual <- length(list.dirs(layer_dir, recursive = FALSE))
  expected <- length(layers[[i]])
  cat(sprintf("  Layer %d: expected %d, actual %d\n", i, expected, actual))
  total_verified <- total_verified + actual
}
cat(sprintf("Total verified in layers: %d\n", total_verified))

# Check what's left in lib_all
remaining <- list.dirs(lib_dir, recursive = FALSE, full.names = FALSE)
if (length(remaining) > 0) {
  cat(sprintf("\nWARNING: %d packages still in lib_all:\n", length(remaining)))
  cat(paste(head(remaining, 20), collapse = ", "), "\n")
}

# Remove empty lib_all
unlink(lib_dir, recursive = TRUE)

# 6. Write manifests
cat("\n--- Writing manifests ---\n")

# Layer manifest (for Dockerfile generation)
layer_manifest <- data.frame(
  layer = seq_along(layers),
  packages = sapply(layers, length),
  size_gb = round(layer_sizes / 1024^3, 2)
)
write.csv(layer_manifest, file.path(output_dir, "layer_manifest.csv"), row.names = FALSE)

# Full package manifest
pkg_manifest <- data.frame(
  package = names(pkg_sizes),
  size_bytes = unname(pkg_sizes),
  layer = NA_integer_
)
for (i in seq_along(layers)) {
  pkg_manifest$layer[pkg_manifest$package %in% layers[[i]]] <- i
}
write.csv(pkg_manifest, file.path(output_dir, "package_manifest.csv"), row.names = FALSE)

# Test manifest (what we'll actually check)
write.csv(
  data.frame(package = sort(test_pkgs)),
  file.path(output_dir, "test_manifest.csv"),
  row.names = FALSE
)

# Layer list for Dockerfile generator
writeLines(
  sprintf("layer%02d", seq_along(layers)),
  file.path(output_dir, "layers.txt")
)

# Summary JSON
summary_data <- list(
  built_at = as.character(Sys.time()),
  seed_packages = seed_pkgs,
  test_packages = length(test_pkgs),
  cached_packages = length(succeeded),
  failed_packages = length(failed),
  num_layers = length(layers),
  total_size_gb = round(sum(pkg_sizes) / 1024^3, 2),
  copy_succeeded = copy_succeeded,
  copy_failed = length(copy_failed),
  verified_total = total_verified
)
write_json(summary_data, file.path(output_dir, "build_summary.json"), pretty = TRUE, auto_unbox = TRUE)

cat("\n=== Done ===\n")
cat(sprintf("Layers: %d\n", length(layers)))
cat(sprintf("Total cached: %d packages\n", length(succeeded)))
cat(sprintf("Test manifest: %d packages\n", length(test_pkgs)))
cat(sprintf("Verified in layers: %d packages\n", total_verified))
