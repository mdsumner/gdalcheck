docker run --rm \
  -v $(pwd)/config:/config:ro \
  -v $(pwd)/scripts/R:/scripts:ro \
  -v $(pwd)/cache-out:/output \
  -e MAKEFLAGS=-j20 \
  gdalcheck-base \
  Rscript /scripts/build_binary_cache.R /output 6 8

