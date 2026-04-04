# gdalcheck

Reverse dependency checking for R packages against bleeding-edge GDAL.

## What it does

1. **Binary cache image** - Pre-compiles ~2200 R packages against `ghcr.io/hypertidy/gdal-r-full:latest`
2. **CLI tools** - Simple `docker run` commands to check any package
3. **Parallel checking** - Test ~1000 reverse dependencies of GDAL-linked packages
4. **Dashboard** - Results published to GitHub Pages

## Quick start

```bash
# Check a package
docker run --rm ghcr.io/mdsumner/gdalcheck/gdalcheck:latest \
  /usr/local/bin/check_one.sh sf /tmp

# Check multiple packages
docker run --rm -v $(pwd)/results:/results \
  ghcr.io/mdsumner/gdalcheck/gdalcheck:latest \
  gdalcheck-pkg sf,terra,stars

# Image status
docker run --rm ghcr.io/mdsumner/gdalcheck/gdalcheck:latest gdalcheck-status
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Local machine (initial build)                                   │
│  └─ build_local.sh → builds ~2200 packages in ~90 mins          │
│  └─ Pushes image to GHCR                                        │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│ GitHub                                                          │
│  ├─ GHCR: ghcr.io/mdsumner/gdalcheck/gdalcheck (~13GB)          │
│  ├─ Daily: check CRAN for updates (triggers incremental rebuild)│
│  └─ Pages: hosts dashboard                                      │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│ Runner (OpenStack / HPC / Local)                                │
│  └─ Pulls image, runs checks via CLI                            │
│  └─ Pushes JSON results → triggers dashboard rebuild            │
└─────────────────────────────────────────────────────────────────┘
```

## Seed packages

Reverse dependencies of these packages are tested:

* `gdalcubes`
* `gdalraster`
* `mapview`
* `raster`
* `sf`
* `stars`
* `terra`
* `tmap`
* `vapour`
* `wk`

Edit `config/seed_packages.txt` to modify.

## CLI Tools

The image includes these commands:

| Command | Description |
|---------|-------------|
| `gdalcheck-status` | Show image build info, installed packages, versions |
| `gdalcheck-pkg <pkg>[,pkg,...]` | Run R CMD check on one or more packages |
| `check_one.sh <pkg> <results_dir>` | Low-level single package check |

### Examples

```bash
# Quick status
docker run --rm ghcr.io/mdsumner/gdalcheck/gdalcheck:latest gdalcheck-status

# Check sf with results saved locally
docker run --rm -v $(pwd)/results:/results \
  ghcr.io/mdsumner/gdalcheck/gdalcheck:latest \
  gdalcheck-pkg sf

# Check multiple packages with parallel make
docker run --rm -v $(pwd)/results:/results \
  -e MAKEFLAGS=-j4 \
  ghcr.io/mdsumner/gdalcheck/gdalcheck:latest \
  gdalcheck-pkg sf,terra,stars,gdalraster

# Interactive debugging
docker run --rm -it ghcr.io/mdsumner/gdalcheck/gdalcheck:latest R
```

## Running full test suite

### Option 1: Local (parallel with GNU parallel)

```bash
docker pull ghcr.io/mdsumner/gdalcheck/gdalcheck:latest

# Get test manifest
docker run --rm ghcr.io/mdsumner/gdalcheck/gdalcheck:latest \
  cat /opt/test_manifest.csv | tail -n +2 | cut -d, -f1 > packages.txt

# Run in parallel (8 at a time)
mkdir -p results
cat packages.txt | parallel -j8 \
  'docker run --rm -v $(pwd)/results:/results \
    ghcr.io/mdsumner/gdalcheck/gdalcheck:latest \
    gdalcheck-pkg {}'
```

### Option 2: HPC/SLURM

```bash
#!/bin/bash
#SBATCH --array=1-1086%50
#SBATCH --time=00:30:00
#SBATCH --mem=4G

PKG=$(sed -n "${SLURM_ARRAY_TASK_ID}p" packages.txt)
singularity exec docker://ghcr.io/mdsumner/gdalcheck/gdalcheck:latest \
  gdalcheck-pkg "$PKG"
```

### Option 3: OpenStack runner (polling)

```bash
# One-time setup
curl -sL https://raw.githubusercontent.com/mdsumner/gdalcheck/main/scripts/setup_runner.sh | bash

# Configure git credentials, then add cron:
crontab -e
# */15 * * * * /home/$USER/gdalcheck-runner/poll_and_run.sh
```

## Building the image locally

For initial builds or major updates (GHA runners don't have enough disk space):

```bash
# Clone repo
git clone https://github.com/mdsumner/gdalcheck.git
cd gdalcheck

# Build with local resources (adjust -j and Ncpus for your machine)
# Usage: ./build_local.sh [MAKEFLAGS_J] [NCPUS]
./build_local.sh 4 8   # -j4 per package, 8 packages in parallel

# Watch progress
tail -f build_*.log

# When done, build final image
./scripts/generate_dockerfile.sh cache-out docker/Dockerfile.cached
docker build -t gdalcheck \
  --build-arg BASE_IMAGE=ghcr.io/hypertidy/gdal-r-full:latest \
  -f docker/Dockerfile.cached .

# Test
docker run --rm gdalcheck gdalcheck-status

# Push to GHCR
echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin
docker tag gdalcheck ghcr.io/mdsumner/gdalcheck/gdalcheck:latest
docker push ghcr.io/mdsumner/gdalcheck/gdalcheck:latest
```

## Image contents

| Item | Description |
|------|-------------|
| Base | `ghcr.io/hypertidy/gdal-r-full:latest` (GDAL/PROJ/GEOS from source, R, core geo packages) |
| Packages | ~2200 R packages pre-compiled against bleeding-edge GDAL |
| Test manifest | ~1086 packages (reverse deps of seeds) |
| Size | ~13GB |

## Dashboard

View results at: https://mdsumner.github.io/gdalcheck/

## Output format

Check results are JSON for easy parsing:

```json
{
  "package": "sf",
  "version": "1.0-15",
  "status": "OK",
  "errors": 0,
  "warnings": 2,
  "notes": 1,
  "check_time_secs": 45,
  "gdal_version": "3.12.0",
  "timestamp": "2026-04-04T12:00:00Z"
}
```

Pipe to `jq` for quick summaries:

```bash
# All results
cat results/*.json | jq -s '[.[] | {pkg: .package, status: .status}]'

# Failures only
cat results/*.json | jq -s '[.[] | select(.status != "OK")]'
```

## License

MIT
