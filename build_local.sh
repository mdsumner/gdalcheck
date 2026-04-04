#!/bin/bash
# build_local.sh - Build gdalcheck image locally
# Usage: ./build_local.sh [MAKEFLAGS_J] [NCPUS]
# Example: ./build_local.sh 4 8  # -j4 per package, 8 packages in parallel

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

echo "Starting package cache build..." | tee -a "$LOGFILE"

docker run --rm \
  -v "$(pwd)/config:/config:ro" \
  -v "$(pwd)/scripts/R:/scripts:ro" \
  -v "$(pwd)/cache-out:/output" \
  -e "MAKEFLAGS=-j${MAKEFLAGS_J}" \
  ghcr.io/hypertidy/gdal-r-full:latest \
  Rscript /scripts/build_binary_cache.R /output 6 "$NCPUS" \
  >> "$LOGFILE" 2>&1

echo "" | tee -a "$LOGFILE"
echo "=== Build complete ===" | tee -a "$LOGFILE"
cat cache-out/build_summary.json | tee -a "$LOGFILE"

echo ""
echo "Next steps:"
echo "  1. Generate Dockerfile:"
echo "     ./scripts/generate_dockerfile.sh cache-out docker/Dockerfile.cached"
echo ""
echo "  2. Build image:"
echo "     docker build -t gdalcheck --build-arg BASE_IMAGE=ghcr.io/hypertidy/gdal-r-full:latest -f docker/Dockerfile.cached ."
echo ""
echo "  3. Test:"
echo "     docker run --rm gdalcheck gdalcheck-status"
echo ""
echo "  4. Push:"
echo "     docker tag gdalcheck ghcr.io/mdsumner/gdalcheck/gdalcheck:latest"
echo "     docker push ghcr.io/mdsumner/gdalcheck/gdalcheck:latest"
