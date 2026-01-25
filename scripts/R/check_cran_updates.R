#!/usr/bin/env Rscript
# Check CRAN for package updates that should trigger a cache rebuild

library(jsonlite)

cat("=== Checking CRAN for updates ===\n")

# Load config
seed_pkgs <- readLines("config/seed_packages.txt")
seed_pkgs <- seed_pkgs[nzchar(trimws(seed_pkgs))]

cat(sprintf("Seed packages: %s\n", paste(seed_pkgs, collapse = ", ")))

# For dependency resolution - use available.packages()
ap <- available.packages(repos = "https://cloud.r-project.org")

revdeps <- tools::package_dependencies(
  seed_pkgs, db = ap, reverse = TRUE, recursive = FALSE,
  which = c("Depends", "Imports", "LinkingTo")
)

# For state tracking (MD5sum) - use CRAN_package_db()
db <- tools::CRAN_package_db()[, c("Package", "Version", "MD5sum")]
# Get current CRAN state
db <- tools::CRAN_package_db()[, c("Package", "Version", "MD5sum")]

watchlist <- sort(unique(c(seed_pkgs, unlist(revdeps))))

cat(sprintf("Watchlist: %d packages\n", length(watchlist)))

# Compare to cached state
cached <- tryCatch({
  x <- fromJSON("config/cran_state.json")
  # Handle empty list from initial []
  if (length(x) == 0) {
    data.frame(Package = character(), MD5sum = character())
  } else {
    as.data.frame(x)
  }
}, error = function(e) {
  data.frame(Package = character(), MD5sum = character())
})

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


cat(sprintf("Watchlist: %d packages\n", length(watchlist)))

# Write test manifest
write.csv(
  data.frame(package = sort(watchlist)),
  "config/revdep_manifest.csv",
  row.names = FALSE
)

cat(sprintf("\nWrote state for %d packages\n", nrow(current)))
