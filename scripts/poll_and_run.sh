#!/bin/bash
# Poll GitHub repo for changes and run revdep checks
# Run via cron: */15 * * * * /home/ubuntu/gdalcheck/poll_and_run.sh

set -euo pipefail

WORKDIR="${WORKDIR:-$HOME/gdalcheck-runner}"
REPO="mdsumner/gdalcheck"  # Change to your repo
IMAGE="ghcr.io/${REPO}/gdalcheck:latest"
PARALLEL_JOBS="${PARALLEL_JOBS:-$(nproc)}"

LOGFILE="$WORKDIR/logs/runner-$(date +%Y%m%d).log"
mkdir -p "$WORKDIR/logs" "$WORKDIR/results"

log() { echo "[$(date -Iseconds)] $*" | tee -a "$LOGFILE"; }

# Check for new manifest commit
LAST_SHA_FILE="$WORKDIR/.last_sha"
LAST_SHA=$(cat "$LAST_SHA_FILE" 2>/dev/null || echo "none")

CURRENT_SHA=$(curl -sf "https://api.github.com/repos/${REPO}/commits/main" | jq -r '.sha' || echo "error")

if [[ "$CURRENT_SHA" == "error" ]]; then
  log "Failed to fetch current SHA"
  exit 1
fi

if [[ "$CURRENT_SHA" == "$LAST_SHA" ]]; then
  log "No changes (SHA: ${CURRENT_SHA:0:8})"
  exit 0
fi

log "New commit detected: ${LAST_SHA:0:8} -> ${CURRENT_SHA:0:8}"

# Fetch latest manifest
MANIFEST_URL="https://raw.githubusercontent.com/${REPO}/main/manifests/test_manifest.csv"
curl -sfL "$MANIFEST_URL" -o "$WORKDIR/test_manifest.csv" || {
  log "Failed to fetch manifest"
  exit 1
}

PACKAGES=$(tail -n +2 "$WORKDIR/test_manifest.csv" | cut -d',' -f1)
PKG_COUNT=$(echo "$PACKAGES" | wc -l)

log "Found $PKG_COUNT packages to check"

# Pull latest image
log "Pulling image: $IMAGE"
docker pull "$IMAGE" || {
  log "Failed to pull image"
  exit 1
}

# Create results dir for this run
RUN_ID=$(date +%s)
RESULTS_DIR="$WORKDIR/results/$RUN_ID"
mkdir -p "$RESULTS_DIR"

log "Starting run $RUN_ID with $PARALLEL_JOBS parallel jobs"

# Run checks in parallel
echo "$PACKAGES" | parallel -j "$PARALLEL_JOBS" --joblog "$RESULTS_DIR/parallel.log" --halt never \
  'docker run --rm -v '"$RESULTS_DIR"':/results '"$IMAGE"' /usr/local/bin/check_one.sh {} /results 2>&1 | tee '"$RESULTS_DIR"'/{}.log'

log "Checks complete, aggregating results..."

# Aggregate results
Rscript --vanilla << EOF
library(jsonlite)

results_dir <- "$RESULTS_DIR"
json_files <- list.files(results_dir, pattern = "\\.json$", full.names = TRUE)

if (length(json_files) == 0) {
  cat("No results found!\n")
  quit(status = 1)
}

results <- lapply(json_files, function(f) {
  tryCatch(fromJSON(f), error = function(e) NULL)
})
results <- Filter(Negate(is.null), results)

df <- do.call(rbind, lapply(results, function(r) {
  data.frame(
    package = r\$package,
    status = r\$status,
    gdal_version = r\$gdal_version %||% NA,
    stringsAsFactors = FALSE
  )
}))

passed <- sum(df\$status == "OK")
failed <- sum(df\$status != "OK")

summary_data <- list(
  run_id = "$RUN_ID",
  completed_at = as.character(Sys.time()),
  total = nrow(df),
  passed = passed,
  failed = failed,
  gdal_version = df\$gdal_version[1],
  failures = df\$package[df\$status != "OK"]
)

write_json(summary_data, file.path(results_dir, "summary.json"), pretty = TRUE, auto_unbox = TRUE)
write.csv(df, file.path(results_dir, "all_results.csv"), row.names = FALSE)

cat(sprintf("Results: %d passed, %d failed\n", passed, failed))
if (failed > 0) {
  cat("Failures:", paste(head(summary_data\$failures, 20), collapse = ", "))
  if (failed > 20) cat(sprintf(" ... and %d more", failed - 20))
  cat("\n")
}
EOF

log "Run $RUN_ID complete"

# Update last SHA
echo "$CURRENT_SHA" > "$LAST_SHA_FILE"

# Push results back to repo
log "Pushing results to GitHub..."

cd "$WORKDIR"
if [[ ! -d "repo" ]]; then
  git clone "https://github.com/${REPO}.git" repo
fi

cd repo
git fetch origin
git checkout main
git pull origin main

# Copy results
mkdir -p "results/$RUN_ID"
cp "$RESULTS_DIR/summary.json" "results/$RUN_ID/"
cp "$RESULTS_DIR/all_results.csv" "results/$RUN_ID/"

git add "results/$RUN_ID"
git commit -m "Results for run $RUN_ID [skip ci]" || log "No changes to commit"
git push origin main || log "Failed to push (may need auth configured)"

log "Done"
