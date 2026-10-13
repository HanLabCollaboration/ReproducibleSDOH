# =============================================================================
# geography/config.R — every setting for the geography run. Sourced by the
# geography/ scripts.
#
# This folder computes no index. For each geography x year it downloads the
# Census boundaries with total population, and writes two files that every
# index shares:
#   geoinfo_{geo}_{year}.parquet    GEOID, NAME, tot_pop
#   geometry_{geo}_{year}.parquet   GEOID, geometry (boundary, as WKB)
#
# It needs no sibling package, so there is no PACKAGE_REF here.
# No API key or token belongs here: CENSUS_API_KEY comes from the environment
# (~/.Renviron).
# =============================================================================

if (!exists("INDEX_DIR")) INDEX_DIR <- getwd()

INDEX <- "geography"

# --- Run ---------------------------------------------------------------------
RUN_ID         <- Sys.getenv("RUN_ID", unset = "2026-10")
SCHEMA_VERSION <- 1L
release_tag <- function(kind) sprintf("%s-v%s", kind, gsub("-", ".", RUN_ID))   # geoinfo-v2026.10, geometry-v2026.10

# --- Coverage: 26 tasks, the same geographies and years as the indices ---------
#   tract:       2011-2024 = 14
#   block group: 2013-2024 = 12
GEOS                 <- c("tract", "block group")
YEAR_MIN             <- 2011L
YEAR_MAX             <- 2024L
YEAR_MIN_BLOCK_GROUP <- 2013L   # ACS 5-year block groups start in 2013

# --- What is downloaded --------------------------------------------------------
# The same source and the same boundary files the index packages use, so every
# GEOID matches the index files: tidycensus::get_acs() with geometry, for the
# 50 states and DC. Total population is ACS table B01003.
POPULATION_VARIABLE <- "B01003_001"
NON_STATES          <- c("PR", "AS", "GU", "MP", "VI", "UM")

GEOINFO_SCHEMA  <- c(GEOID = "character", NAME = "character", tot_pop = "integer")

file_name <- function(kind, geo, year) {
  sprintf("%s_%s_%d.parquet", kind, gsub(" ", "_", geo), as.integer(year))
}

# --- Where outputs go ----------------------------------------------------------
# Sherlock: $SCRATCH/sdoh/<RUN_ID>/geography/. Elsewhere (laptop tests):
# pipeline/runs/<RUN_ID>/geography/, which .gitignore excludes.
# Override the part before /geography with SDOH_OUT_ROOT.
RUN_ROOT <- local({
  root <- Sys.getenv("SDOH_OUT_ROOT", unset = "")
  if (!nzchar(root)) {
    scratch <- Sys.getenv("SCRATCH", unset = "")
    root <- if (nzchar(scratch)) file.path(scratch, "sdoh", RUN_ID)
            else file.path(dirname(INDEX_DIR), "runs", RUN_ID)
  }
  root
})
OUT_ROOT         <- file.path(RUN_ROOT, INDEX)
GRID_DIR         <- file.path(OUT_ROOT, "grids")
OUT_DIR          <- file.path(OUT_ROOT, "out")
DONE_DIR         <- file.path(OUT_ROOT, "done")
LOG_DIR          <- file.path(OUT_ROOT, "logs")
CENSUS_CACHE_DIR <- file.path(OUT_ROOT, "census_cache")

# --- SLURM --------------------------------------------------------------------
# One tier. In the index runs the 2011-2012 tracts (full-detail boundaries)
# peaked at 14 GB; here the boundaries are also converted to WKB, so allow more.
TIERS <- list(
  standard = list(mem = "32G", time = "06:00:00", max_parallel = 8L)
)
SLURM_CPUS      <- 2L
SLURM_PARTITION <- Sys.getenv("SDOH_PARTITION", unset = "qsu,normal,owners")
