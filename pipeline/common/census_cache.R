# =============================================================================
# census_cache.R — disk cache for tidycensus::get_acs(), for the pipeline only.
#
# The sibling packages call tidycensus::get_acs() and are not changed. In the
# pipeline's R session, install_census_cache() swaps that function for a
# version that stores each result on disk and replays it for an identical call.
#
# What it saves for Yost:
#   - national and state tasks for the same geo and year make the same call;
#   - with stabilization at state scope, the parent geography is fetched again
#     for every state group (about 51 identical calls per task).
# tidycensus also calls get_acs() once per state internally, so each state is
# cached on its own: a failed run resumes from the states already downloaded.
#
# The cache key is a hash of ALL call arguments (including `geometry`), so a
# cached result is only ever replayed for exactly the same call.
#
# The cache is throwaway: delete it after the run, so a new release always
# downloads fresh ACS data.
# =============================================================================

.census_cache <- new.env(parent = emptyenv())

install_census_cache <- function(cache_dir, max_tries = 5L, wait_seconds = 10) {
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)

  st <- .census_cache
  st$dir     <- cache_dir
  st$orig    <- tidycensus::get_acs
  st$depth   <- 0L   # > 0 while inside another get_acs() call
  st$n_calls <- 0L   # every call seen, at any depth
  st$stats   <- c(hits = 0L, misses = 0L, nested_hits = 0L, nested_misses = 0L, retries = 0L)

  count <- function(what) st$stats[[what]] <- st$stats[[what]] + 1L

  cached_get_acs <- function(...) {
    args   <- list(...)
    nested <- st$depth > 0L
    st$n_calls <- st$n_calls + 1L

    key  <- digest::digest(
      list(args = args[order(names(args))],
           tidycensus = as.character(utils::packageVersion("tidycensus"))),
      algo = "sha256"
    )
    path <- file.path(st$dir, paste0(key, ".rds"))

    if (file.exists(path)) {
      count(if (nested) "nested_hits" else "hits")
      return(readRDS(path))
    }

    # One job downloads; another job asking for the same call waits, then reads.
    # If the file system does not support locks, both download: still correct,
    # because each result is written to a temporary file and then renamed.
    lock <- tryCatch(filelock::lock(paste0(path, ".lock"), timeout = Inf), error = function(e) NULL)
    if (!is.null(lock)) on.exit(filelock::unlock(lock), add = TRUE)
    if (file.exists(path)) {
      count(if (nested) "nested_hits" else "hits")
      return(readRDS(path))
    }

    count(if (nested) "nested_misses" else "misses")
    attempt <- 0L
    repeat {
      attempt      <- attempt + 1L
      calls_before <- st$n_calls
      st$depth     <- st$depth + 1L
      result <- tryCatch(st$orig(...), error = function(e) e)
      st$depth     <- st$depth - 1L
      if (!inherits(result, "error")) break

      # If this call fanned out into per-state calls, those already retried.
      fanned_out <- st$n_calls > calls_before
      if (fanned_out || attempt >= max_tries) stop(result)
      count("retries")
      wait <- wait_seconds * 2^(attempt - 1L)
      message(sprintf("get_acs failed (attempt %d of %d): %s. Waiting %ds.",
                      attempt, max_tries, conditionMessage(result), wait))
      Sys.sleep(wait)
    }

    tmp <- paste0(path, ".tmp.", Sys.getpid())
    saveRDS(result, tmp, compress = FALSE)
    file.rename(tmp, path)
    result
  }

  utils::assignInNamespace("get_acs", cached_get_acs, ns = "tidycensus")
  invisible(TRUE)
}

census_cache_stats <- function() {
  if (is.null(.census_cache$stats)) return(NULL)
  as.list(.census_cache$stats)
}
