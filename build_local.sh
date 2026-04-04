#!/bin/bash
# build_local.sh
# Run from repo root

set -euo pipefail

MAKEFLAGS_J="${1:-4}"
NCPUS="${2:-8}"
LOGFILE="build_$(date +%Y%m%d_%H%M%S).log"

echo "=== gdalcheck local build ===" | tee "$LOGFILE"
echo "MAKEFLAGS=-j${MAKEFLAGS_J}, Ncpus=${NCPUS}" | tee -a "$LOGFILE"
echo "Logging to: $LOGFILE" | tee -a "$LOGFILE"
echo "Run: tail -f $LOGFILE" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

mkdir -p cache-out

docker run --rm \
  -v "$(pwd)/config:/config:ro" \
  -v "$(pwd)/scripts/R:/scripts:ro" \
  -v "$(pwd)/cache-out:/output" \
  -e "MAKEFLAGS=-j${MAKEFLAGS_J}" \
  ghcr.io/hypertidy/gdal-r-full:latest \
  Rscript /scripts/build_binary_cache.R /output 6 "$NCPUS" \
  >> "$LOGFILE" 2>&1

echo "" | tee -a "$LOGFILE"
echo "=== Done ===" | tee -a "$LOGFILE"
cat cache-out/build_summary.json | tee -a "$LOGFILE"
