# Downloading release files, with checksum verification and a local cache.

# Download `url` to `dest` through a temporary file, so an interrupted download
# never leaves a partial file behind. Returns TRUE on success, FALSE otherwise.
sdoh_fetch <- function(url, dest) {
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(dest, ".part")
  on.exit(unlink(tmp), add = TRUE)
  # Boundary files are large; R's default 60-second limit is too short for them.
  old <- options(timeout = max(3600, getOption("timeout", 60)))
  on.exit(options(old), add = TRUE)
  ok <- tryCatch(
    suppressWarnings(utils::download.file(url, tmp, mode = "wb", quiet = TRUE)) == 0,
    error = function(e) FALSE
  )
  if (!ok || !file.exists(tmp) || file.size(tmp) == 0) return(FALSE)
  file.rename(tmp, dest)
}

# Folder holding one release's files: the cache, or a session-only folder when
# cache = FALSE.
sdoh_release_dir <- function(release, cache) {
  root <- if (isTRUE(cache)) sdoh_cache_dir() else file.path(tempdir(), "ReproducibleSDOH")
  file.path(root, release)
}

# The release's checksum list, as a named character vector: file name -> sha256.
# It also tells which files the release contains.
sdoh_checksums <- function(release, cache = TRUE) {
  path <- file.path(sdoh_release_dir(release, cache), "SHA256SUMS")
  if (!file.exists(path)) {
    url <- paste(sdoh_base_url(), release, "SHA256SUMS", sep = "/")
    if (!sdoh_fetch(url, path)) {
      stop(glue::glue(
        "Could not download the file list of release '{release}' from\n  {url}\n",
        "Either the release does not exist (yet), or there is no internet connection. ",
        "Published releases: https://github.com/HanLabCollaboration/ReproducibleSDOH-data/releases"
      ), call. = FALSE)
    }
  }
  lines <- readLines(path, warn = FALSE)
  lines <- lines[nzchar(trimws(lines))]
  parts <- regmatches(lines, regexec("^([0-9a-fA-F]{64})\\s+\\*?(.+)$", lines))
  parts <- parts[lengths(parts) == 3]
  stats::setNames(
    tolower(vapply(parts, `[[`, "", 2)),
    vapply(parts, `[[`, "", 3)
  )
}

# Local path of one release file, downloading and verifying it if needed.
sdoh_download <- function(release, file, cache = TRUE, quiet = FALSE) {
  sums <- sdoh_checksums(release, cache)
  if (!file %in% names(sums)) {
    stop(glue::glue(
      "'{file}' is not part of release '{release}'. ",
      "That combination of geography, scope and year is not published in it."
    ), call. = FALSE)
  }

  path <- file.path(sdoh_release_dir(release, cache), file)
  if (file.exists(path)) return(path)

  url <- paste(sdoh_base_url(), release, file, sep = "/")
  matches <- function() identical(digest::digest(file = path, algo = "sha256"), sums[[file]])

  # A corrupted download is retried once.
  for (attempt in 1:2) {
    if (!quiet) message(glue::glue("Downloading {file} from release {release}..."))
    if (!sdoh_fetch(url, path)) {
      stop(glue::glue("Could not download\n  {url}\nCheck your internet connection."), call. = FALSE)
    }
    if (matches()) return(path)
    unlink(path)
  }
  stop(glue::glue(
    "'{file}' was downloaded twice from release '{release}' and its checksum did ",
    "not match either time. Please report this at ",
    "https://github.com/HanLabCollaboration/ReproducibleSDOH-data/issues"
  ), call. = FALSE)
}
