#!/usr/bin/env Rscript
# Check CRAN for package updates that should trigger a cache rebuild

library(jsonlite)

cat("=== Checking CRAN for updates ===\n")

# Load config
seed_pkgs <- readLines("config/seed_packages.txt")
seed_pkgs <- seed_pkgs[nzchar(trimws(seed_pkgs))]

cat(sprintf("Seed packages: %s\n", paste(seed_pkgs, collapse = ", ")))

# Get current CRAN state
db <- tools::CRAN_package_db()[, c("Package", "Version", "MD5sum")]

# Build watchlist: seeds + their reverse deps
revdeps <- unlist(tools::package_dependencies(
  seed_pkgs, db = db, reverse = TRUE, recursive = FALSE,
  which = c("Depends", "Imports", "LinkingTo")
))
watchlist <- unique(c(seed_pkgs, revdeps))

cat(sprintf("Watchlist: %d packages\n", length(watchlist)))

# Compare to cached state
cached <- tryCatch(
  fromJSON("config/cran_state.json"),
  error = function(e) data.frame(Package = character(), MD5sum = character())
)

current <- db[db$Package %in% watchlist, ]

# Find changes
if (nrow(cached) > 0) {
  changed <- current[!(current$MD5sum %in% cached$MD5sum), ]
} else {
  changed <- current  # First run, everything is "new"
}

# Categorize: seed package changes are "hot" and trigger cache rebuild
hot_changed <- changed[changed$Package %in% seed_pkgs, ]

cat(sprintf("Changed packages: %d\n", nrow(changed)))
cat(sprintf("Seed packages changed: %d\n", nrow(hot_changed)))

if (nrow(changed) > 0) {
  cat("Changed:\n")
  for (i in seq_len(min(nrow(changed), 20))) {
    cat(sprintf("  %s (%s)\n", changed$Package[i], changed$Version[i]))
  }
  if (nrow(changed) > 20) {
    cat(sprintf("  ... and %d more\n", nrow(changed) - 20))
  }
}

# Outputs for GitHub Actions
github_output <- Sys.getenv("GITHUB_OUTPUT", "")
if (nzchar(github_output)) {
  needs_rebuild <- nrow(hot_changed) > 0 || nrow(cached) == 0
  cat(sprintf("needs_rebuild=%s\n", tolower(needs_rebuild)),
      file = github_output, append = TRUE)
  cat(sprintf("changed_packages=%s\n", paste(changed$Package, collapse = ",")),
      file = github_output, append = TRUE)
  cat(sprintf("num_changed=%d\n", nrow(changed)),
      file = github_output, append = TRUE)
}

# Always update state file
write_json(as.data.frame(current), "config/cran_state.json", pretty = TRUE)

# Write test manifest
write.csv(
  data.frame(package = sort(watchlist)),
  "config/revdep_manifest.csv",
  row.names = FALSE
)

cat(sprintf("\nWrote state for %d packages\n", nrow(current)))
