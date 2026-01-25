# gdalcheck

Reverse dependency checking for R packages against bleeding-edge GDAL.

## What it does

1. **Daily CRAN monitoring** - GitHub Actions checks for updates to GDAL-dependent packages
2. **Binary cache building** - Pre-compiles ~1500 R packages against `osgeo/gdal:ubuntu-full-latest`
3. **Parallel checking** - Tests ~930 reverse dependencies of sf/terra/gdalraster/vapour/stars
4. **Dashboard** - Results published to GitHub Pages

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ GitHub                                                          │
│  ├─ Daily: check CRAN for updates                               │
│  ├─ On change: rebuild Docker image with binary cache           │
│  ├─ GHCR: stores images (~15GB, layered for upload)             │
│  └─ Pages: hosts dashboard                                      │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼ polls for changes
┌─────────────────────────────────────────────────────────────────┐
│ Runner (OpenStack/HPC)                                          │
│  └─ Pulls image, runs R CMD check on all revdeps in parallel    │
│  └─ Pushes results back to repo → triggers dashboard rebuild    │
└─────────────────────────────────────────────────────────────────┘
```

## Seed packages

Packages whose reverse dependencies are tested:

- `sf`
- `terra`  
- `gdalraster`
- `vapour`
- `stars`

Edit `config/seed_packages.txt` to add more.

## Running the checks

### Option 1: OpenStack/VM

```bash
# One-time setup
curl -sL https://raw.githubusercontent.com/mdsumner/gdalcheck/main/scripts/setup_runner.sh | bash

# Configure git credentials, then:
crontab -e
# */15 * * * * /home/$USER/gdalcheck-runner/poll_and_run.sh
```

### Option 2: Manual/local

```bash
# Pull the image
docker pull ghcr.io/mdsumner/gdalcheck/gdalcheck:latest

# Check a single package
docker run --rm -v $(pwd)/results:/results \
  ghcr.io/mdsumner/gdalcheck/gdalcheck:latest \
  /usr/local/bin/check_one.sh sf /results
```

### Option 3: HPC/SLURM

```bash
#!/bin/bash
#SBATCH --array=1-932%50
#SBATCH --time=00:30:00

PKG=$(sed -n "${SLURM_ARRAY_TASK_ID}p" packages.txt)
singularity exec docker://ghcr.io/mdsumner/gdalcheck/gdalcheck:latest \
  /usr/local/bin/check_one.sh "$PKG" "$RESULTS_DIR"
```

## Dashboard

View at: https://mdsumner.github.io/gdalcheck/

## Local development

```bash
# Build base image
docker build -t gdalcheck-base -f docker/Dockerfile.base docker/

# Run cache builder (takes ~2 hours)
docker run --rm \
  -v $(pwd)/config:/config:ro \
  -v $(pwd)/scripts/R:/scripts:ro \
  -v $(pwd)/cache-out:/output \
  gdalcheck-base \
  Rscript /scripts/build_binary_cache.R /output 6

# Generate Dockerfile
./scripts/generate_dockerfile.sh cache-out docker/Dockerfile.cached

# Build cached image
docker build -t gdalcheck \
  --build-arg BASE_IMAGE=gdalcheck-base \
  -f docker/Dockerfile.cached .
```

## License

MIT
