# addNtiles() and addQuintiles(): equal-size groups of the scores returned by
# getYostIndex(), getNDI() and getICE().

# Every score column a get*() function can return.
sdoh_score_cols <- function() {
  c("Yost", "YostStabilizedImputed", "NDI", "NDIImputed",
    ice_measures(), paste0(ice_measures(), "Imputed"))
}

# Split `x` into `n` groups of (nearly) equal size, 1 = lowest values. Missing
# values stay missing. Same result as dplyr::ntile(): ties are broken by row
# order, and when the groups cannot be equal the lower groups get the extra rows.
sdoh_ntile <- function(x, n) {
  pos <- rank(x, ties.method = "first", na.last = "keep")
  len <- sum(!is.na(x))
  if (len == 0) return(rep(NA_integer_, length(x)))

  n_larger         <- len %% n
  larger_size      <- ceiling(len / n)
  smaller_size     <- floor(len / n)
  larger_threshold <- larger_size * n_larger

  in_larger <- pos <= larger_threshold
  bins <- ifelse(
    in_larger,
    (pos + larger_size - 1) / larger_size,
    (pos - larger_threshold + smaller_size - 1) / smaller_size + n_larger
  )
  as.integer(floor(bins))
}

# Name of the group column for `n` groups: "Quintile" for 5, "Ntile7" for 7.
sdoh_ntile_suffix <- function(n) {
  named <- c("3" = "Tertile", "4" = "Quartile", "5" = "Quintile",
             "10" = "Decile", "100" = "Percentile")
  key <- as.character(n)
  if (key %in% names(named)) named[[key]] else paste0("Ntile", n)
}

# Groups of `x` computed separately within each set of `sets`.
sdoh_ntile_by <- function(x, sets, n) {
  group <- rep(NA_integer_, length(x))
  for (r in split(seq_along(x), sets)) group[r] <- sdoh_ntile(x[r], n)
  group
}

# One label per row: rows with the same label are grouped against each other.
# Rows are never compared across years (nor across geographies or scopes, when
# several are stacked), and with scope = "state" each state is its own set.
sdoh_ntile_sets <- function(data) {
  parts <- lapply(intersect(c("year", "geo", "scope"), names(data)), function(col) data[[col]])
  if ("scope" %in% names(data) && any(data$scope == "state", na.rm = TRUE)) {
    if (!"GEOID" %in% names(data)) {
      stop("'data' has scope = \"state\" but no 'GEOID' column to find each area's state.",
           call. = FALSE)
    }
    in_state <- !is.na(data$scope) & data$scope == "state"
    parts <- c(parts, list(ifelse(in_state, substr(data$GEOID, 1, 2), "")))
  }
  if (length(parts) == 0) return(rep("all", nrow(data)))
  do.call(paste, c(parts, sep = "|"))
}

# Where `data` came from, as recorded by the get*() functions, or NULL if it is
# unknown or no longer describes the data.
sdoh_ntile_source <- function(data) {
  source <- attr(data, "sdoh_source")
  if (!is.list(source) || !all(c("GEOID", "year", "geo") %in% names(data))) return(NULL)
  if (!identical(unique(data$geo), source$geo)) return(NULL)
  if (source$has_scope && !identical(unique(data$scope), source$scope)) return(NULL)
  source
}

# Groups of the score columns `cols`, computed against every area the scores are
# relative to: all areas of the published file of each year, or all areas of the
# same state for scope = "state". The rows of `data` only say which groups to
# return, so the result does not depend on which states `data` was filtered to.
# Returns a named list with one integer vector per column.
sdoh_ntile_reference <- function(data, cols, n, source) {
  groups <- stats::setNames(lapply(cols, function(col) rep(NA_integer_, nrow(data))), cols)
  for (y in unique(data$year)) {
    file <- sdoh_file_name(source$prefix, source$geo, y, source$scope)
    ref  <- sdoh_read(sdoh_download(source$release, file, source$cache, quiet = TRUE))
    # Sorted by GEOID, as get*() returns it, so that tied scores fall in the
    # same groups as when the whole file is grouped directly.
    ref  <- ref[order(ref$GEOID), , drop = FALSE]
    sets <- if (identical(source$scope, "state")) substr(ref$GEOID, 1, 2) else rep("all", nrow(ref))
    rows <- which(data$year == y)
    at   <- match(data$GEOID[rows], ref$GEOID)
    for (col in cols) groups[[col]][rows] <- sdoh_ntile_by(ref[[col]], sets, n)[at]
  }
  # A score that is missing in `data` has no group.
  for (col in cols) groups[[col]][is.na(data[[col]])] <- NA_integer_
  groups
}

#' Add groups of equal size (quintiles, quartiles, ...) to an index
#'
#' @description
#' Splits the areas into `n` groups of equal size by their score and adds the
#' group number as a new column, one per score column. Group 1 holds the lowest
#' scores and group `n` the highest. `addQuintiles()` is `addNtiles(n = 5)`.
#'
#' Areas are only compared with areas **of the same year**: when `data` holds
#' several years (`year = 2019:2022`), the groups are computed separately in
#' each.
#'
#' Within a year, an area is compared with every area its score is relative to,
#' whether or not those areas are in `data`:
#' * `scope = "national"`, and ICE: every area of the country. Asking for some
#'   states only (`states = "CA"`) does not change the groups. The function
#'   reads the whole country, forms the groups, and keeps your rows, so a
#'   California tract in quintile 5 is in the top fifth of all US tracts.
#' * `scope = "state"`: every area of the same state, because those scores are
#'   comparable only inside a state.
#'
#' @details
#' Comparing with areas that are not in `data` works for data returned by
#' [getYostIndex()], [getNDI()] or [getICE()], which record the file the scores
#' came from. The whole file is read again (from the cache), so this also holds
#' if you filtered the rows yourself, for example to one county. It needs the
#' `GEOID`, `year` and `geo` columns, and the record can be lost when the data
#' is rebuilt, for example by `merge()` or `rbind()`. For any other data frame,
#' and for columns in `cols` that are not scores of that index, the groups are
#' computed among the rows of `data`; a warning says so when the data is at
#' national scope and does not hold every state.
#'
#' Groups are formed as [dplyr::ntile()] does. Areas are ordered by score and
#' cut into `n` groups of equal count; when the count is not a multiple of `n`,
#' the lower groups get one extra area. Tied scores are ordered by their row
#' position, so areas with the same score can fall on both sides of a cut.
#' Areas with a missing score get a missing group and are not counted.
#'
#' A higher group always means a higher score. What that says about the
#' neighborhood depends on the index: a higher Yost Index is higher
#' socioeconomic status, while a higher NDI is more deprivation.
#'
#' @param data A data frame returned by [getYostIndex()], [getNDI()] or
#'   [getICE()], or any data frame with a numeric score column (see Details).
#'   If it has a `year` column, groups are computed within each year.
#' @param n Number of groups: `5` for quintiles, `4` for quartiles, `10` for
#'   deciles, `100` for percentiles.
#' @param cols Names of the score columns to group. `NULL` (default) uses every
#'   score column of the package's indices found in `data`, such as `Yost` and
#'   `YostStabilizedImputed`.
#' @param suffix Text added to each score column's name to name its group
#'   column. `NULL` (default) uses `"Tertile"`, `"Quartile"`, `"Quintile"`,
#'   `"Decile"` or `"Percentile"` for `n` = 3, 4, 5, 10 or 100, and
#'   `"Ntile<n>"` otherwise (`"Ntile7"` for `n = 7`).
#'
#' @return `data` with one more integer column per score column, named
#'   `<score><suffix>` (such as `YostQuintile`), holding the group, from 1
#'   (lowest scores) to `n` (highest). An existing column of that name is
#'   replaced.
#'
#' @seealso [getYostIndex()], [getNDI()], [getICE()]
#'
#' @export
#'
#' @examples
#' \dontrun{
#'   # National quintiles of the Yost Index: adds YostQuintile and
#'   # YostStabilizedImputedQuintile
#'   yost <- addQuintiles(getYostIndex(geo = "tract", year = 2022))
#'
#'   # California only, still in national quintiles (among all US tracts)
#'   yost_ca <- addQuintiles(getYostIndex(year = 2022, states = "CA"))
#'
#'   # Several years: quintiles are computed within each year
#'   yost_years <- addQuintiles(getYostIndex(year = 2019:2022))
#'
#'   # Quartiles of the Messer NDI within each state: adds NDIQuartile
#'   ndi <- getNDI(type = "messer", year = 2022, scope = "state", version = "raw")
#'   ndi <- addNtiles(ndi, n = 4)
#'
#'   # Deciles of one ICE measure
#'   ice <- addNtiles(getICE(year = 2022), n = 10, cols = "ICE_inc")
#' }
addNtiles <- function(data, n, cols = NULL, suffix = NULL) {
  if (!is.data.frame(data)) stop("'data' must be a data frame.", call. = FALSE)
  if (missing(n) || !is.numeric(n) || length(n) != 1 || is.na(n) || n != round(n) || n < 2) {
    stop("'n' must be a single whole number of groups, 2 or more (5 for quintiles).",
         call. = FALSE)
  }
  n <- as.integer(n)

  if (is.null(cols)) {
    cols <- intersect(sdoh_score_cols(), names(data))
    if (length(cols) == 0) {
      stop("No score column of the package's indices found in 'data'. ",
           "Name the columns to group in 'cols'.", call. = FALSE)
    }
  } else {
    if (!is.character(cols) || length(cols) == 0 || anyNA(cols)) {
      stop("'cols' must be a character vector of column names.", call. = FALSE)
    }
    cols <- unique(cols)
    absent <- setdiff(cols, names(data))
    if (length(absent) > 0) {
      stop(glue::glue(
        "Column(s) not found in 'data': {glue::glue_collapse(absent, sep = ', ')}."
      ), call. = FALSE)
    }
  }
  not_numeric <- cols[!vapply(cols, function(col) is.numeric(data[[col]]), logical(1))]
  if (length(not_numeric) > 0) {
    stop(glue::glue(
      "Column(s) must be numeric: {glue::glue_collapse(not_numeric, sep = ', ')}."
    ), call. = FALSE)
  }

  if (is.null(suffix)) {
    suffix <- sdoh_ntile_suffix(n)
  } else if (!is.character(suffix) || length(suffix) != 1 || is.na(suffix) || !nzchar(suffix)) {
    stop("'suffix' must be a single non-empty string.", call. = FALSE)
  }

  # Scores from a get*() function are grouped against the whole published file.
  source   <- sdoh_ntile_source(data)
  ref_cols <- if (is.null(source)) character(0) else intersect(cols, sdoh_score_cols())
  groups   <- if (length(ref_cols) > 0) sdoh_ntile_reference(data, ref_cols, n, source) else list()

  # Anything else is grouped among the rows of `data`.
  row_cols <- setdiff(cols, ref_cols)
  if (length(row_cols) > 0) {
    national <- "scope" %in% names(data) && any(data$scope == "national", na.rm = TRUE)
    if (national && "GEOID" %in% names(data) && length(unique(substr(data$GEOID, 1, 2))) < 51) {
      warning(glue::glue(
        "The groups of {glue::glue_collapse(row_cols, sep = ', ')} are computed among the rows ",
        "of 'data', which does not hold every state: they are not national groups."
      ), call. = FALSE)
    }
    sets <- sdoh_ntile_sets(data)
    for (col in row_cols) groups[[col]] <- sdoh_ntile_by(data[[col]], sets, n)
  }

  for (col in cols) data[[paste0(col, suffix)]] <- groups[[col]]
  data
}

#' @rdname addNtiles
#' @export
addQuintiles <- function(data, cols = NULL, suffix = NULL) {
  addNtiles(data, n = 5, cols = cols, suffix = suffix)
}
