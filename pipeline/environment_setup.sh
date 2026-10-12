#!/bin/bash
# =============================================================================
# environment_setup.sh
#
# Environment for the ReproducibleSDOH pipeline on Stanford Sherlock:
# the modules to load and the R packages to install.
# Follows plan/plan.md (§5.5) and plan/plan_NDI.md (§6.1).
#
# Run everything on a Sherlock LOGIN or COMPUTE node (not the dtn node):
#   ssh <sunetid>@login.sherlock.stanford.edu
#
# -----------------------------------------------------------------------------
# STEP 0 — one time: get the code
# -----------------------------------------------------------------------------
#   mkdir -p $GROUP_HOME/tidySDOH && cd $GROUP_HOME/tidySDOH
#   git clone https://github.com/HanLabCollaboration/ReproducibleSDOH.git
#
# -----------------------------------------------------------------------------
# STEP 1 — one time: Census API key (never put it in the repo)
# -----------------------------------------------------------------------------
#   echo 'CENSUS_API_KEY=<your key>' >> ~/.Renviron && chmod 600 ~/.Renviron
#
# -----------------------------------------------------------------------------
# STEP 2 — one time: install the packages, on a compute node (compiling is heavy)
# -----------------------------------------------------------------------------
#   sh_dev -c 4 -m 16GB -t 2:00:00
#   bash $GROUP_HOME/tidySDOH/ReproducibleSDOH/pipeline/environment_setup.sh install
#
# -----------------------------------------------------------------------------
# STEP 3 — every session and every SLURM script: load the environment
# -----------------------------------------------------------------------------
#   source $GROUP_HOME/tidySDOH/ReproducibleSDOH/pipeline/environment_setup.sh
#
# Other one-time steps, only needed later in the plan:
#   rclone config        # create a remote named "box"     (archive.sh)
#   gh auth login        # GitHub CLI, to publish releases (publish.R)
# =============================================================================

# -----------------------------------------------------------------------------
# SETTINGS
# -----------------------------------------------------------------------------

# Root folder: holds the repo checkout and the R library; it is not purged.
export TIDYSDOH_ROOT="${TIDYSDOH_ROOT:-${GROUP_HOME}/tidySDOH}"

# Module versions (from `module spider` on Sherlock, 2026-10-12)
R_VERSION="${R_VERSION:-4.4.2}"         # category: math
GDAL_VERSION="3.10.2"                   # category: physics
GEOS_VERSION="3.13.1"                   # category: physics
PROJ_VERSION="9.5.1"                    # category: physics
UDUNITS_VERSION="2.2.26"                # category: physics
CMAKE_VERSION="3.31.4"                  # category: devel

# Folder of this script (pipeline/). The packages to install are the
# PACKAGE_REF pins in each index's config.R (pipeline/<index>/config.R).
export SDOH_PIPELINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------------------------------------------------------
# MODULES
# -----------------------------------------------------------------------------

# devel and math are Sherlock's sticky defaults; purge reports them as kept.
module purge

# R
module load math "R/${R_VERSION}" \
  || echo "ERROR: R/${R_VERSION} not loaded; run 'module spider R/${R_VERSION}'" >&2

# Geospatial system libraries: needed to compile and run sf, units, spdep, tigris
module load physics "gdal/${GDAL_VERSION}" "geos/${GEOS_VERSION}" "proj/${PROJ_VERSION}" "udunits/${UDUNITS_VERSION}" \
  || echo "ERROR: geospatial modules not loaded; run 'module spider gdal/${GDAL_VERSION}'" >&2

# cmake: builds s2 (a dependency of sf)
module load devel "cmake/${CMAKE_VERSION}" \
  || echo "ERROR: cmake/${CMAKE_VERSION} not loaded; run 'module spider cmake/${CMAKE_VERSION}'" >&2

# git: clone/pull the code, record the commit
module load system git \
  || echo "ERROR: git not loaded; run 'module spider git'" >&2

# Optional, only for the last steps of the plan
module load system rclone 2>/dev/null || echo "Note: rclone module not loaded (needed for archive.sh only)" >&2
module load system gh     2>/dev/null || echo "Note: gh module not loaded (needed for publish.R only)" >&2

# -----------------------------------------------------------------------------
# R LIBRARY — in the group folder, because $HOME has a small quota
# -----------------------------------------------------------------------------

export R_LIBS_USER="${TIDYSDOH_ROOT}/R_libs/${R_VERSION}"
mkdir -p "${R_LIBS_USER}"

# Cache downloaded boundary shapefiles (tigris)
export TIGRIS_CACHE_DIR="${TIDYSDOH_ROOT}/tigris_cache"
mkdir -p "${TIGRIS_CACHE_DIR}"

# Stop here unless called as:  bash environment_setup.sh install
if [[ "${1:-}" != "install" ]]; then
  echo "tidySDOH environment loaded (R ${R_VERSION}; library: ${R_LIBS_USER})"
  return 0 2>/dev/null || exit 0
fi

# =============================================================================
# INSTALL (one time)
# =============================================================================

module list
echo "Installing R packages into ${R_LIBS_USER} ..."

Rscript - <<'EOF'
lib <- Sys.getenv("R_LIBS_USER")
options(
  repos = c(CRAN = "https://cloud.r-project.org"),
  Ncpus = as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", unset = "2"))
)

# --- CRAN packages -----------------------------------------------------------
cran_packages <- c(
  # Imports of the sibling packages (ReproducibleNDI / YostIndex / SDI / CDI)
  "dplyr", "tidycensus", "glue", "purrr", "magrittr", "sf", "spdep", "psych",
  "tidyr", "stringr", "rlang",
  "httr2", "readr",   # ReproducibleYostIndex only
  "statar",           # ReproducibleSDI only
  # Pipeline
  "remotes",          # install the sibling packages at a pinned ref
  "renv",             # renv.lock, once pipeline/ exists
  "nanoparquet",      # write Parquet with file metadata (arrow's prebuilt
                      # library needs a newer glibc than Sherlock has)
  "filelock",         # lock files for the Census cache
  "digest",           # hash of get_acs() arguments (cache key)
  "memoise", "cachem",
  "pkgload",          # load_all() of the ReproducibleSDOH checkout
  "jsonlite",         # done JSONs, provenance.json, manifest.json
  "testthat", "withr"
)

missing <- setdiff(cran_packages, rownames(installed.packages()))
if (length(missing) > 0) install.packages(missing, lib = lib)

# --- Sibling packages, at the commits pinned in pipeline/<index>/config.R ------
# These repos are public, so no token is needed. An expired GITHUB_PAT in the
# environment makes GitHub answer "401 Bad credentials", so ignore any token here.
Sys.unsetenv(c("GITHUB_PAT", "GITHUB_TOKEN"))
configs <- Sys.glob(file.path(Sys.getenv("SDOH_PIPELINE_DIR"), "*", "config.R"))
refs <- unique(vapply(configs, function(f) {
  e <- new.env()
  assign("INDEX_DIR", dirname(f), envir = e)
  sys.source(f, envir = e)
  e$PACKAGE_REF
}, character(1)))
if (length(refs) == 0) stop("No pipeline/<index>/config.R found.", call. = FALSE)
message("Sibling packages: ", paste(refs, collapse = ", "))
for (ref in refs) {
  remotes::install_github(ref, lib = lib, upgrade = "never", dependencies = TRUE)
}

# --- Check and record --------------------------------------------------------
sibling_names <- sub("@.*$", "", basename(refs))
needed <- c(cran_packages, sibling_names)
failed <- setdiff(needed, rownames(installed.packages()))

root <- Sys.getenv("TIDYSDOH_ROOT")
ip <- as.data.frame(installed.packages()[, c("Package", "Version", "LibPath")])
write.csv(ip[order(ip$Package), ], file.path(root, "installed_packages.csv"), row.names = FALSE)
writeLines(capture.output(sessionInfo()), file.path(root, "session_info.txt"))

if (length(failed) > 0) {
  stop("Not installed: ", paste(failed, collapse = ", "), call. = FALSE)
}

# sf must find GDAL/GEOS/PROJ at run time
print(sf::sf_extSoftVersion())

if (!nzchar(Sys.getenv("CENSUS_API_KEY"))) {
  message("CENSUS_API_KEY is not set: add it to ~/.Renviron (see STEP 1).")
} else {
  x <- tidycensus::get_acs(geography = "state", variables = "B01003_001", year = 2022)
  message("Test Census call OK: ", nrow(x), " rows.")
}
message("All R packages installed. Versions written to ", file.path(root, "installed_packages.csv"))
EOF
R_STATUS=$?

if [[ ${R_STATUS} -ne 0 ]]; then
  echo "R package installation FAILED (see messages above)." >&2
  exit ${R_STATUS}
fi
echo "Done."
