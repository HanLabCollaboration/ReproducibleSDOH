# =============================================================================
# ndi/config.R — every setting for the ReproducibleNDI run. Sourced by the ndi/
# scripts. The package produces three series, all run from this folder:
#   messer        Messer Neighborhood Deprivation Index
#   powell_wiley  Powell-Wiley Neighborhood Deprivation Index
#   ice           Index of Concentration at the Extremes (five measures)
# No API key or token belongs here: CENSUS_API_KEY comes from the environment
# (~/.Renviron).
# =============================================================================

if (!exists("INDEX_DIR")) INDEX_DIR <- getwd()

INDEX <- "ndi"

# --- Run ---------------------------------------------------------------------
RUN_ID         <- Sys.getenv("RUN_ID", unset = "2026-10")
# Messer and Powell-Wiley are released together (ndi-v2026.10); ICE has its own
# release (ice-v2026.10).
release_tag <- function(series) {
  sprintf("%s-v%s", if (series == "ice") "ice" else "ndi", gsub("-", ".", RUN_ID))
}
SCHEMA_VERSION <- 1L

# --- Package, pinned (GitHub repo@commit-or-tag) ------------------------------
# environment_setup.sh installs it; run_task.R stops if the installed commit
# differs from the pin.
PACKAGE     <- "ReproducibleNDI"
PACKAGE_REF <- "HanLabCollaboration/ReproducibleNDI@6ae291e"

# --- Coverage: 82 tasks --------------------------------------------------------
#   messer:       tract 2011-2024 x 2 scopes = 28  (its ACS tables stop at tract)
#   powell_wiley: tract 2011-2024 x 2 scopes = 28  (its ACS tables stop at tract)
#   ice:          tract 2011-2024 = 14; block group 2013-2024 = 12  (ICE has no scope)
YEAR_MIN             <- 2011L
YEAR_MAX             <- 2024L
YEAR_MIN_BLOCK_GROUP <- 2013L   # ACS 5-year block groups start in 2013

# --- What is computed ----------------------------------------------------------
# One call per task. With impute = TRUE, each function returns both versions
# that are published: the raw one (no imputation) and the imputed one.
#   computeNDI(): df_ndi_raw$NDI and df_ndi$NDIImputed
#   computeICE(): df_ice_raw$ICE_* and df_ice$ICE_* (written with an "Imputed" suffix)
ICE_MEASURES <- c("ICE_inc", "ICE_edu", "ICE_rewb", "ICE_wbinc", "ICE_wpcinc")

NDI_SCHEMA <- c(GEOID = "character", NDI = "double", NDIImputed = "double")
ICE_SCHEMA <- c(
  GEOID = "character",
  setNames(rep("double", 5), ICE_MEASURES),
  setNames(rep("double", 5), paste0(ICE_MEASURES, "Imputed"))
)

SERIES <- list(
  messer = list(
    fun         = "computeNDI",
    geos        = c("tract"),
    scopes      = c("national", "state"),
    file_prefix = "ndi_messer",
    schema      = NDI_SCHEMA,
    sign_var    = "POV",              # higher NDI must mean more poverty
    args = list(type = "messer", states = "all", impute = TRUE, weight_var = "tot_pop",
                keep_geometry = FALSE, return_format = "detailed", quiet = TRUE)
  ),
  powell_wiley = list(
    fun         = "computeNDI",
    geos        = c("tract"),
    scopes      = c("national", "state"),
    file_prefix = "ndi_powellwiley",
    schema      = NDI_SCHEMA,
    sign_var    = "PctFamBelowPov",   # higher NDI must mean more poverty
    args = list(type = "powell_wiley", states = "all", impute = TRUE, weight_var = "tot_pop",
                keep_geometry = FALSE, return_format = "detailed", quiet = TRUE)
  ),
  ice = list(
    fun         = "computeICE",
    geos        = c("tract", "block group"),
    scopes      = c("none"),          # ICE is not relative to a reference set
    file_prefix = "ice",
    schema      = ICE_SCHEMA,
    args = list(states = "all", impute = TRUE, keep_geometry = TRUE,
                return_format = "detailed", quiet = TRUE)
  )
)

# The package's `annotation` values for the NDI: when a score must be missing,
# and when not. (ICE annotates rows, not measures; see run_task.R.)
NA_REASONS <- c("No population", "Imputation incomplete", "PCA failed")
OK_REASONS <- c("Complete data", "Imputation completed")

file_name <- function(series, geo, scope, year) {
  parts <- c(SERIES[[series]]$file_prefix, gsub(" ", "_", geo),
             if (scope != "none") scope, as.integer(year))
  paste0(paste(parts, collapse = "_"), ".parquet")
}

# --- Where outputs go ----------------------------------------------------------
# Sherlock: $SCRATCH/sdoh/<RUN_ID>/ndi/. Elsewhere (laptop tests):
# pipeline/runs/<RUN_ID>/ndi/, which .gitignore excludes.
# Override the part before /ndi with SDOH_OUT_ROOT.
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
# Same values as the Yost run, where tract peaked at 14 GB (2011-2012) and
# block group at 6 GB. Adjust them from the peak memory and run time that
# every task records in its done JSON.
TIER_BY_GEO <- c("tract" = "medium", "block group" = "high")
TIERS <- list(
  medium = list(mem = "20G", time = "12:00:00", max_parallel = 8L),
  high   = list(mem = "48G", time = "24:00:00", max_parallel = 8L)
)
SLURM_CPUS      <- 2L
SLURM_PARTITION <- Sys.getenv("SDOH_PARTITION", unset = "qsu,normal,owners")
