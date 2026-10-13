#!/usr/bin/env Rscript
# =============================================================================
# geography/run_task.R — handles ONE geography task (one geo x year). From one
# Census download it writes two Parquet files:
#   geoinfo_{geo}_{year}.parquet    GEOID, NAME, tot_pop
#   geometry_{geo}_{year}.parquet   GEOID, geometry (boundary, as WKB)
#
# Called by SLURM through job.sh, or by hand:
#   Rscript pipeline/geography/run_task.R --grid <grid.csv> --task 1
#
# Options:
#   --grid <csv>     task list from make_grid.R   (default: $SDOH_GRID)
#   --task <n>       task_id in that list         (default: $SLURM_ARRAY_TASK_ID)
#   --allow-dirty    run with uncommitted pipeline changes (debugging only;
#                    never for published files)
#   --no-cache       do not use the Census download cache
#   --force          recompute even if the task is already done
#
# Outputs (under OUT_ROOT, see config.R):
#   out/geoinfo_*.parquet, out/geometry_*.parquet   the published files
#   done/geography_{geo}_{year}.json                what ran, checks, timings, versions
#   done/geography_{geo}_{year}.error.json          written instead if the task fails
# =============================================================================

INDEX_DIR <- local({
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  if (length(f) > 0) dirname(normalizePath(f)) else getwd()
})
PIPELINE_DIR <- dirname(INDEX_DIR)
source(file.path(INDEX_DIR, "config.R"))
source(file.path(PIPELINE_DIR, "common", "census_cache.R"))

# --- Arguments ---------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(flag, default) {
  i <- which(args == flag)
  if (length(i) == 1 && length(args) > i) args[i + 1] else default
}
grid_path   <- arg_value("--grid", Sys.getenv("SDOH_GRID", unset = ""))
task_id     <- as.integer(arg_value("--task", Sys.getenv("SLURM_ARRAY_TASK_ID", unset = NA)))
allow_dirty <- "--allow-dirty" %in% args
use_cache   <- !("--no-cache" %in% args)
force       <- "--force" %in% args

if (!nzchar(grid_path) || !file.exists(grid_path)) stop("Grid file not found: '", grid_path, "'")
if (is.na(task_id)) stop("No task: pass --task <n> or set SLURM_ARRAY_TASK_ID")

grid <- read.csv(grid_path, stringsAsFactors = FALSE)
task <- grid[grid$task_id == task_id, ]
if (nrow(task) != 1) stop(sprintf("task_id %d not found in %s", task_id, grid_path))

for (d in c(OUT_DIR, DONE_DIR)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
geoinfo_path  <- file.path(OUT_DIR, task$geoinfo_file)
geometry_path <- file.path(OUT_DIR, task$geometry_file)
stem          <- sub("^geometry_", "geography_", sub("\\.parquet$", "", task$geometry_file))
done_path     <- file.path(DONE_DIR, paste0(stem, ".json"))
error_path    <- file.path(DONE_DIR, paste0(stem, ".error.json"))

cat(sprintf("[%s task %d] geo=%s | year=%d -> %s, %s\n",
            INDEX, task_id, task$geo, task$year, task$geoinfo_file, task$geometry_file))

# --- Skip if already done: re-running an array is always safe ------------------
if (!force && file.exists(geoinfo_path) && file.exists(geometry_path) && file.exists(done_path)) {
  cat("Already done; skipping. Use --force to recompute.\n")
  quit(status = 0)
}

write_json <- function(x, path) {
  tmp <- paste0(path, ".tmp")
  jsonlite::write_json(x, tmp, auto_unbox = TRUE, pretty = TRUE, na = "null", digits = NA)
  file.rename(tmp, path)
}

main <- function() {
  t_start <- Sys.time()
  invisible(gc(reset = TRUE))

  # --- Provenance: which pipeline commit ----------------------------------------
  git <- function(...) {
    out <- suppressWarnings(tryCatch(
      system2("git", c("-C", shQuote(dirname(PIPELINE_DIR)), ...), stdout = TRUE, stderr = FALSE),
      error = function(e) character(0)
    ))
    if (length(out) == 0 || !is.null(attr(out, "status"))) NA_character_ else out
  }
  pipeline_sha   <- git("rev-parse", "HEAD")[1]
  pipeline_dirty <- git("status", "--porcelain", "--", "pipeline")
  pipeline_dirty <- !(length(pipeline_dirty) == 1 && is.na(pipeline_dirty)) && length(pipeline_dirty) > 0
  if (is.na(pipeline_sha) || pipeline_dirty) {
    msg <- "The pipeline has uncommitted changes (or is not a git checkout)."
    if (!allow_dirty) stop(msg, " Commit them, or pass --allow-dirty for debugging.")
    message("WARNING: ", msg)
  }

  # --- Census ------------------------------------------------------------------
  if (!nzchar(Sys.getenv("CENSUS_API_KEY"))) stop("CENSUS_API_KEY is not set (see ~/.Renviron).")
  options(tigris_use_cache = TRUE)
  if (use_cache) install_census_cache(CENSUS_CACHE_DIR)

  # --- Download: boundaries + total population, 50 states and DC -----------------
  states <- setdiff(unique(tidycensus::fips_codes$state), NON_STATES)
  t0 <- Sys.time()
  acs <- tidycensus::get_acs(
    geography   = task$geo,
    year        = task$year,
    output      = "wide",
    variables   = POPULATION_VARIABLE,
    survey      = "acs5",
    geometry    = TRUE,
    cache_table = TRUE,
    state       = states
  )
  download_seconds <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  cat(sprintf("Downloaded in %.0f s\n", download_seconds))

  acs <- acs[order(acs$GEOID), ]
  geom <- sf::st_geometry(acs)
  crs  <- sf::st_crs(geom)

  # --- geoinfo: GEOID, NAME, tot_pop ----------------------------------------------
  geoinfo <- data.frame(
    GEOID   = as.character(acs$GEOID),
    NAME    = as.character(acs$NAME),
    tot_pop = as.integer(acs[[paste0(POPULATION_VARIABLE, "E")]]),
    stringsAsFactors = FALSE
  )
  stopifnot(
    "no rows"              = nrow(geoinfo) > 0,
    "unexpected columns"   = identical(names(geoinfo), names(GEOINFO_SCHEMA)),
    "unexpected types"     = identical(unname(vapply(geoinfo, typeof, "")), unname(GEOINFO_SCHEMA)),
    "GEOID is not unique"  = !anyDuplicated(geoinfo$GEOID),
    "GEOID has NA"         = !anyNA(geoinfo$GEOID)
  )

  # --- geometry: GEOID + boundary as WKB ------------------------------------------
  geometry <- data.frame(GEOID = geoinfo$GEOID, stringsAsFactors = FALSE)
  geometry$geometry <- unclass(sf::st_as_binary(geom))
  stopifnot("geometry is not WKB" = all(vapply(geometry$geometry[seq_len(min(100, nrow(geometry)))], is.raw, logical(1))))

  # --- Checks (recorded) ------------------------------------------------------------
  checks <- list(
    tot_pop_na       = sum(is.na(geoinfo$tot_pop)),
    tot_pop_negative = sum(geoinfo$tot_pop < 0, na.rm = TRUE),
    tot_pop_zero     = sum(geoinfo$tot_pop == 0, na.rm = TRUE),
    tot_pop_total    = sum(as.numeric(geoinfo$tot_pop), na.rm = TRUE),
    name_empty       = sum(is.na(geoinfo$NAME) | !nzchar(geoinfo$NAME)),
    geometry_empty   = sum(sf::st_is_empty(geom)),
    geometry_types   = as.list(table(as.character(sf::st_geometry_type(geom)))),
    crs_epsg         = crs$epsg
  )

  # The same GEOIDs as the index files already computed in this run, if any.
  geo_tag <- gsub(" ", "_", task$geo)
  index_files <- Sys.glob(file.path(RUN_ROOT, "*", "out", sprintf("*_%s_*%d.parquet", geo_tag, task$year)))
  index_files <- index_files[!grepl("/geography/", index_files, fixed = TRUE)]
  compared <- lapply(index_files, function(f) {
    ids <- nanoparquet::read_parquet(f, col_select = "GEOID")$GEOID
    list(file = basename(f),
         only_in_index     = length(setdiff(ids, geoinfo$GEOID)),
         only_in_geography = length(setdiff(geoinfo$GEOID, ids)))
  })
  checks$index_files_compared <- length(compared)
  checks$index_files_differing <- Filter(function(x) x$only_in_index > 0 || x$only_in_geography > 0, compared)
  checks$geoids_match_indices <- length(checks$index_files_differing) == 0

  # --- Write both files, with provenance as file metadata ----------------------------
  fetched_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  meta_for <- function(kind) {
    meta <- list(
      schema_version     = SCHEMA_VERSION,
      index              = kind,
      geo                = task$geo,
      acs_year           = task$year,
      acs_survey         = "acs5",
      release_tag        = release_tag(kind),
      r_version          = paste(R.version$major, R.version$minor, sep = "."),
      tidycensus_version = as.character(utils::packageVersion("tidycensus")),
      tigris_version     = as.character(utils::packageVersion("tigris")),
      fetched_at         = fetched_at,
      pipeline_git_sha   = if (pipeline_dirty) paste0(pipeline_sha, "-dirty") else pipeline_sha
    )
    if (kind == "geoinfo") meta$population_variable <- POPULATION_VARIABLE
    if (kind == "geometry") {
      meta$geometry_encoding <- "WKB"
      meta$crs_epsg <- crs$epsg
      meta$crs_wkt  <- crs$wkt
    }
    unlist(lapply(meta, function(x) if (is.na(x)) "" else as.character(x)))
  }
  write_atomic <- function(df, path, meta) {
    tmp <- paste0(path, ".tmp.", Sys.getpid())
    nanoparquet::write_parquet(df, tmp, metadata = meta)
    file.rename(tmp, path)
  }
  write_atomic(geoinfo,  geoinfo_path,  meta_for("geoinfo"))
  write_atomic(geometry, geometry_path, meta_for("geometry"))

  # --- Done record --------------------------------------------------------------
  # Peak memory: the kernel's figure on Linux, R's own heap figure elsewhere.
  peak_mb <- tryCatch({
    hwm <- grep("^VmHWM", readLines("/proc/self/status"), value = TRUE)
    as.numeric(gsub("[^0-9]", "", hwm)) / 1024
  }, error = function(e) NA_real_, warning = function(w) NA_real_)
  g <- gc()
  if (length(peak_mb) != 1 || is.na(peak_mb)) peak_mb <- sum(g[, ncol(g)])   # "max used (Mb)"

  write_json(list(
    task             = as.list(task),
    status           = "done",
    rows             = nrow(geoinfo),
    geoinfo_bytes    = file.size(geoinfo_path),
    geometry_bytes   = file.size(geometry_path),
    checks           = checks,
    download_seconds = round(download_seconds, 1),
    total_seconds    = round(as.numeric(difftime(Sys.time(), t_start, units = "secs")), 1),
    peak_memory_mb   = round(peak_mb),
    census_cache     = if (use_cache) census_cache_stats() else "off",
    metadata         = as.list(meta_for("geoinfo")),
    slurm_job        = Sys.getenv("SLURM_JOB_ID", unset = ""),
    node             = Sys.info()[["nodename"]]
  ), done_path)
  if (file.exists(error_path)) file.remove(error_path)

  cat(sprintf("Wrote %s (%.1f MB) and %s (%.1f MB): %d rows. Peak memory %.0f MB.\n",
              task$geoinfo_file, file.size(geoinfo_path) / 1024^2,
              task$geometry_file, file.size(geometry_path) / 1024^2, nrow(geoinfo), peak_mb))
  if (!checks$geoids_match_indices) message("WARNING: GEOIDs differ from some index files; see ", done_path)
}

# --- Run; on error leave a record and make SLURM mark the task failed -------------
status <- tryCatch({
  main()
  0L
}, error = function(e) {
  message("ERROR: ", conditionMessage(e))
  write_json(list(
    task    = as.list(task),
    status  = "error",
    message = conditionMessage(e),
    call    = paste(deparse(conditionCall(e)), collapse = " "),
    time    = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    slurm_job = Sys.getenv("SLURM_JOB_ID", unset = "")
  ), error_path)
  1L
})
quit(status = status)
