# gdalcheck

NOT YET FUNCTIONAL 


Reverse dependency checking for R packages against bleeding-edge GDAL.

## What it could do ...

NOT YET FUNCTIONAL 

1. **Daily CRAN monitoring** — checks for updates to GDAL-dependent packages
2. **Binary cache building** — pre-compiles ~1500 R packages against the latest GDAL
3. **Parallel checking** — tests ~930 reverse dependencies of sf/terra/gdalraster/vapour/stars
4. **Dashboard** — results published to GitHub Pages

## Architecture

```
ghcr.io/hypertidy/gdal-r-full:latest   ← maintained by hypertidy/gdal-r-ci
           │  GDAL/PROJ/GEOS from source, single PROJ, full R CMD check
           ▼
ghcr.io/mdsumner/gdalcheck/gdalcheck-base:latest
           │  + additional sysreqs for revdep ecosystem (magick, jags, rgl...)
           ▼
ghcr.io/mdsumner/gdalcheck/gdalcheck:latest
           │  + binary cache of ~1500 pre-compiled R packages
           ▼
         Runner (OpenStack/HPC/SLURM)
           └─ pulls image, runs R CMD check in parallel
           └─ pushes results → dashboard rebuild
```

The base image is maintained by [hypertidy/gdal-r-ci](https://github.com/hypertidy/gdal-r-ci)
which builds GDAL/PROJ/GEOS from source with a single PROJ (no internal PROJ symbol
renaming). This means full `R CMD check` works for all packages including sf and terra —
no `--no-test-load` workarounds needed.

## Seed packages

Packages whose reverse dependencies are tested:

- `gdalcubes`
- `gdalraster`
- `raster`
- `sf`
- `stars`
- `terra`
- `vapour`

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

## Rebuilding the cache

The cache rebuilds automatically when CRAN packages change (daily check).
Manual trigger via Actions → "Rebuild binary cache" → workflow_dispatch.

The `no_cache` option forces a full rebuild bypassing Docker layer cache —
use this if you suspect stale layers.

## Generating system requirements

The `config/sysreqs.txt` file is generated from the revdep ecosystem using
`pkgdepends`. Packages already provided by `gdal-r-full` are excluded automatically:

```bash
Rscript scripts/R/generate_sysreqs.R config/sysreqs.txt ubuntu-24.04
```

## Dashboard

View at: https://mdsumner.github.io/gdalcheck/

## Related

- [hypertidy/gdal-r-ci](https://github.com/hypertidy/gdal-r-ci) — base images (gdal-system, gdal-r, gdal-r-full, gdal-python)
- [firelab/gdalraster](https://github.com/firelab/gdalraster) — primary test target
- [hypertidy/vapour](https://github.com/hypertidy/vapour) — hypertidy test target

## License

MIT
