#!/usr/bin/env Rscript
# =============================================================================
# yost/run_task.R — computes ONE Yost task (one geo x scope x year) and writes
# one Parquet file with GEOID, Yost (raw) and YostStabilizedImputed (best).
#
# Called by SLURM through job.sh, or by hand:
#   Rscript pipeline/yost/run_task.R --grid <grid.csv> --task 1
#
# Options:
#   --grid <csv>     task list from make_grid.R   (default: $SDOH_GRID)
#   --task <n>       task_id in that list         (default: $SLURM_ARRAY_TASK_ID)
#   --allow-dirty    run with uncommitted pipeline changes or an unpinned
#                    package (debugging only; never for published files)
#   --no-cache       do not use the Census download cache
#   --force          recompute even if the task is already done
#
# Outputs (under OUT_ROOT, see config.R):
#   out/<file>.parquet        the published file
#   done/<file>.json          what ran, checks, timings, versions
#   done/<file>.error.json    written instead if the task fails
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
out_path   <- file.path(OUT_DIR, task$file)
done_path  <- file.path(DONE_DIR, paste0(task$file, ".json"))
error_path <- file.path(DONE_DIR, paste0(task$file, ".error.json"))

cat(sprintf("[%s task %d] geo=%s | scope=%s | year=%d -> %s\n",
            INDEX, task_id, task$geo, task$scope, task$year, out_path))

# --- Skip if already done: re-running an array is always safe ------------------
if (!force && file.exists(out_path) && file.exists(done_path)) {
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

  # --- Provenance: which pipeline commit, which package commit ----------------
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

  pin         <- sub("^.*@", "", PACKAGE_REF)
  package_sha <- utils::packageDescription(PACKAGE)$RemoteSha
  if (is.null(package_sha)) package_sha <- NA_character_
  if (is.na(package_sha) || !startsWith(package_sha, pin)) {
    msg <- sprintf("%s is not installed from the pinned commit %s (installed: %s).",
                   PACKAGE, pin, package_sha)
    if (!allow_dirty) stop(msg, " Run environment_setup.sh install, or pass --allow-dirty.")
    message("WARNING: ", msg)
  }

  # --- Census ------------------------------------------------------------------
  if (!nzchar(Sys.getenv("CENSUS_API_KEY"))) stop("CENSUS_API_KEY is not set (see ~/.Renviron).")
  options(tigris_use_cache = TRUE)
  if (use_cache) install_census_cache(CENSUS_CACHE_DIR)

  # --- Compute: one call returns raw and best -----------------------------------
  compute <- getExportedValue(PACKAGE, "computeYostIndex")
  t0 <- Sys.time()
  res <- do.call(compute, c(list(geo = task$geo, year = task$year, scope = task$scope), COMPUTE_ARGS))
  compute_seconds <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  cat(sprintf("Computed in %.0f s\n", compute_seconds))

  # --- Build the output table: GEOID + scores only -------------------------------
  raw  <- as.data.frame(res$df_yost_raw)
  best <- as.data.frame(res$df_yost)
  scores <- merge(raw[, c("GEOID", "Yost")],
                  best[, c("GEOID", "YostStabilizedImputed")],
                  by = "GEOID", all = TRUE)
  scores <- scores[order(scores$GEOID), ]
  rownames(scores) <- NULL
  scores$GEOID <- as.character(scores$GEOID)

  # --- Validate against the schema ------------------------------------------------
  stopifnot(
    "no rows"              = nrow(scores) > 0,
    "unexpected columns"   = identical(names(scores), names(SCHEMA)),
    "unexpected types"     = identical(unname(vapply(scores, typeof, "")), unname(SCHEMA)),
    "GEOID is not unique"  = !anyDuplicated(scores$GEOID),
    "GEOID has NA"         = !anyNA(scores$GEOID)
  )

  # --- Checks (recorded, not written to the file) ---------------------------------
  # NA consistency: a score is missing exactly when the package gives a reason.
  na_check <- function(col, ann_df) {
    ann <- ann_df$annotation[match(scores$GEOID, ann_df$GEOID)]
    miss <- is.na(scores[[col]])
    list(
      n_na                 = sum(miss),
      annotation_counts    = as.list(table(ann, useNA = "ifany")),
      na_without_reason    = sum(miss  & !(ann %in% NA_REASONS)),
      value_despite_reason = sum(!miss & !(ann %in% OK_REASONS))
    )
  }
  checks <- list(
    Yost                  = na_check("Yost", raw),
    YostStabilizedImputed = na_check("YostStabilizedImputed", best)
  )
  both <- stats::complete.cases(scores[, c("Yost", "YostStabilizedImputed")])
  checks$cor_raw_best <- if (sum(both) > 2) stats::cor(scores$Yost[both], scores$YostStabilizedImputed[both]) else NA
  checks$best_has_no_more_na_than_raw <- checks$YostStabilizedImputed$n_na <= checks$Yost$n_na
  checks$na_consistent <- all(vapply(
    checks[c("Yost", "YostStabilizedImputed")],
    function(x) x$na_without_reason == 0 && x$value_despite_reason == 0, logical(1)
  ))
  # Not run yet: they need pieces that do not exist yet (plan.md 5.6, steps 4b and 4c).
  checks$grouping_match   <- "not run: ReproducibleSDOH grouping functions not built yet"
  checks$population_match <- "not run: geoinfo release not built yet"

  # --- Write the Parquet file, with its provenance as file metadata ----------------
  fetched_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  meta <- list(
    schema_version     = SCHEMA_VERSION,
    index              = INDEX,
    geo                = task$geo,
    scope              = task$scope,
    acs_year           = task$year,
    acs_survey         = "acs5",
    release_tag        = RELEASE_TAG,
    geoinfo_release    = "",
    package            = PACKAGE,
    package_version    = as.character(utils::packageVersion(PACKAGE)),
    package_git_sha    = package_sha,
    r_version          = paste(R.version$major, R.version$minor, sep = "."),
    tidycensus_version = as.character(utils::packageVersion("tidycensus")),
    fetched_at         = fetched_at,
    pipeline_git_sha   = if (pipeline_dirty) paste0(pipeline_sha, "-dirty") else pipeline_sha
  )
  meta <- lapply(meta, function(x) if (is.na(x)) "" else as.character(x))

  tmp <- paste0(out_path, ".tmp.", Sys.getpid())
  nanoparquet::write_parquet(scores, tmp, metadata = unlist(meta))
  file.rename(tmp, out_path)

  # --- Done record --------------------------------------------------------------
  # Peak memory: the kernel's figure on Linux, R's own heap figure elsewhere.
  peak_mb <- tryCatch({
    hwm <- grep("^VmHWM", readLines("/proc/self/status"), value = TRUE)
    as.numeric(gsub("[^0-9]", "", hwm)) / 1024
  }, error = function(e) NA_real_, warning = function(w) NA_real_)
  g <- gc()
  if (length(peak_mb) != 1 || is.na(peak_mb)) peak_mb <- sum(g[, ncol(g)])   # "max used (Mb)"

  write_json(list(
    task            = as.list(task),
    status          = "done",
    rows            = nrow(scores),
    bytes           = file.size(out_path),
    checks          = checks,
    compute_seconds = round(compute_seconds, 1),
    total_seconds   = round(as.numeric(difftime(Sys.time(), t_start, units = "secs")), 1),
    peak_memory_mb  = round(peak_mb),
    census_cache    = if (use_cache) census_cache_stats() else "off",
    metadata        = meta,
    slurm_job       = Sys.getenv("SLURM_JOB_ID", unset = ""),
    node            = Sys.info()[["nodename"]]
  ), done_path)
  if (file.exists(error_path)) file.remove(error_path)

  cat(sprintf("Wrote %s (%d rows, %.1f MB). Peak memory %.0f MB.\n",
              out_path, nrow(scores), file.size(out_path) / 1024^2, peak_mb))
  if (!checks$na_consistent) message("WARNING: NA consistency check failed; see ", done_path)
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
