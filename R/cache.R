#' Local cache of downloaded files
#'
#' @description
#' The `get*()` functions save every file they download, so that later calls
#' read it from disk. `sdoh_cache_dir()` returns the folder; `sdoh_cache_clear()`
#' deletes cached files.
#'
#' The folder is `tools::R_user_dir("ReproducibleSDOH", "cache")`, or the value
#' of the option `ReproducibleSDOH.cache_dir` if it is set. Inside it there is
#' one sub-folder per release (for example `yost-v2026.10`).
#'
#' @param release Optional release tag (for example `"yost-v2026.10"`). If
#'   given, only that release's files are deleted; otherwise the whole cache is.
#'
#' @return `sdoh_cache_dir()` returns the path of the cache folder.
#'   `sdoh_cache_clear()` returns, invisibly, the path it deleted.
#'
#' @export
#'
#' @examples
#' sdoh_cache_dir()
#' \dontrun{
#'   sdoh_cache_clear("yost-v2026.10")
#'   sdoh_cache_clear()
#' }
sdoh_cache_dir <- function() {
  getOption("ReproducibleSDOH.cache_dir", tools::R_user_dir("ReproducibleSDOH", "cache"))
}

#' @rdname sdoh_cache_dir
#' @export
sdoh_cache_clear <- function(release = NULL) {
  root <- sdoh_cache_dir()
  target <- if (is.null(release)) root else file.path(root, release)
  if (!dir.exists(target)) return(invisible(character(0)))
  unlink(target, recursive = TRUE)
  invisible(target)
}
