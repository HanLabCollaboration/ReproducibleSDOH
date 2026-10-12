# =============================================================================
# yost/config.R — every setting for the Yost run. Sourced by the yost/ scripts.
# No API key or token belongs here: CENSUS_API_KEY comes from the environment
# (~/.Renviron).
# =============================================================================

if (!exists("INDEX_DIR")) INDEX_DIR <- getwd()

INDEX <- "yost"

# --- Run ---------------------------------------------------------------------
RUN_ID         <- Sys.getenv("RUN_ID", unset = "2026-10")
RELEASE_TAG    <- sprintf("%s-v%s", INDEX, gsub("-", ".", RUN_ID))   # e.g. yost-v2026.10
SCHEMA_VERSION <- 1L

# --- Package, pinned (GitHub repo@commit-or-tag) ------------------------------
# environment_setup.sh installs it; run_task.R stops if the installed commit
# differs from the pin.
PACKAGE     <- "ReproducibleYostIndex"
PACKAGE_REF <- "HanLabCollaboration/ReproducibleYostIndex@d537644"

# --- Coverage: 52 tasks --------------------------------------------------------
#   tract:       2011-2024 x 2 scopes = 28
#   block group: 2013-2024 x 2 scopes = 24
GEOS                 <- c("tract", "block group")
SCOPES               <- c("national", "state")
YEAR_MIN             <- 2011L
YEAR_MAX             <- 2024L
YEAR_MIN_BLOCK_GROUP <- 2013L   # ACS 5-year block groups start in 2013

# --- What is computed ----------------------------------------------------------
# One call per task. With stabilize + impute, computeYostIndex() returns both
# versions that are published:
#   df_yost_raw$Yost               raw  (no stabilization, no imputation)
#   df_yost$YostStabilizedImputed  best (stabilized and imputed)
COMPUTE_ARGS <- list(
  states        = "all",
  stabilize     = TRUE,
  impute        = TRUE,
  weight_var    = "tot_pop",
  keep_geometry = FALSE,
  return_format = "detailed",
  quiet         = TRUE
)

# Columns of the output file
SCHEMA <- c(GEOID = "character", Yost = "double", YostStabilizedImputed = "double")

# The package's `annotation` values: when a score must be missing, and when not
NA_REASONS <- c("No population", "Imputation incomplete", "Factor analysis failed")
OK_REASONS <- c("Complete data", "Imputation completed")

file_name <- function(geo, scope, year) {
  sprintf("yost_%s_%s_%d.parquet", gsub(" ", "_", geo), scope, as.integer(year))
}

# --- Where outputs go ----------------------------------------------------------
# Sherlock: $SCRATCH/sdoh/<RUN_ID>/yost/. Elsewhere (laptop tests):
# pipeline/runs/<RUN_ID>/yost/, which .gitignore excludes.
# Override the part before /yost with SDOH_OUT_ROOT.
OUT_ROOT <- local({
  root <- Sys.getenv("SDOH_OUT_ROOT", unset = "")
  if (!nzchar(root)) {
    scratch <- Sys.getenv("SCRATCH", unset = "")
    root <- if (nzchar(scratch)) file.path(scratch, "sdoh", RUN_ID)
            else file.path(dirname(INDEX_DIR), "runs", RUN_ID)
  }
  file.path(root, INDEX)
})
GRID_DIR         <- file.path(OUT_ROOT, "grids")
OUT_DIR          <- file.path(OUT_ROOT, "out")
DONE_DIR         <- file.path(OUT_ROOT, "done")
LOG_DIR          <- file.path(OUT_ROOT, "logs")
CENSUS_CACHE_DIR <- file.path(OUT_ROOT, "census_cache")

# --- SLURM --------------------------------------------------------------------
# A SLURM array cannot vary memory per task, so each tier is its own array.
# These are starting guesses; adjust them from the peak memory and run time
# that every task records in its done JSON.
TIER_BY_GEO <- c("tract" = "medium", "block group" = "high")
TIERS <- list(
  medium = list(mem = "48G",  time = "12:00:00", max_parallel = 10L),
  high   = list(mem = "128G", time = "24:00:00", max_parallel = 5L)
)
SLURM_CPUS      <- 2L
SLURM_PARTITION <- Sys.getenv("SDOH_PARTITION", unset = "normal,qsu,owners")
