# The shared engine behind getYostIndex(), getNDI(), getICE() and getGeoInfo().

# --- Argument checks ---------------------------------------------------------

sdoh_check_geo <- function(geo, allowed = c("tract", "block group"), what = "This index") {
  geo <- rlang::arg_match0(geo, values = c("tract", "block group", "cbg"), arg_nm = "geo")
  if (geo == "cbg") geo <- "block group"
  if (!geo %in% allowed) {
    stop(glue::glue(
      "{what} is published for {glue::glue_collapse(allowed, sep = ' and ')} only ",
      "(got geo = '{geo}')."
    ), call. = FALSE)
  }
  geo
}

sdoh_check_year <- function(year, geo) {
  if (!is.numeric(year) || length(year) == 0 || anyNA(year) || any(year != round(year))) {
    stop("'year' must be one or more whole numbers, such as 2022 or 2019:2022.", call. = FALSE)
  }
  year <- sort(unique(as.integer(year)))
  year_min <- if (geo == "block group") 2013L else 2011L
  if (any(year < year_min)) {
    stop(glue::glue(
      "ACS 5-year data for geo = '{geo}' starts in {year_min} ",
      "(got year = {glue::glue_collapse(year[year < year_min], sep = ', ')})."
    ), call. = FALSE)
  }
  year
}

sdoh_check_flags <- function(...) {
  flags <- list(...)
  for (nm in names(flags)) {
    if (!is.logical(flags[[nm]]) || length(flags[[nm]]) != 1 || is.na(flags[[nm]])) {
      stop(glue::glue("'{nm}' must be TRUE or FALSE."), call. = FALSE)
    }
  }
  invisible(TRUE)
}

# --- Reading the shared geography files ----------------------------------------

sdoh_read <- function(path) as.data.frame(nanoparquet::read_parquet(path), stringsAsFactors = FALSE)

# GEOID, NAME, tot_pop for one geography and year.
sdoh_read_geoinfo <- function(geo, year, version, cache, quiet) {
  path <- sdoh_download(paste0("geoinfo-", version), sdoh_file_name("geoinfo", geo, year), cache, quiet)
  sdoh_read(path)[, c("GEOID", "NAME", "tot_pop")]
}

# Turn `df` into an sf object by attaching each row's boundary.
sdoh_attach_geometry <- function(df, geo, year, version, cache, quiet) {
  path <- sdoh_download(paste0("geometry-", version), sdoh_file_name("geometry", geo, year), cache, quiet)
  boundaries <- nanoparquet::read_parquet(path)

  rows <- match(df$GEOID, boundaries$GEOID)
  if (anyNA(rows)) {
    stop(glue::glue(
      "{sum(is.na(rows))} GEOID(s) have no boundary in '{basename(path)}'. ",
      "Please report this at https://github.com/HanLabCollaboration/ReproducibleSDOH-data/issues"
    ), call. = FALSE)
  }

  # The coordinate system is recorded in the file (EPSG:4269, NAD83, for Census boundaries).
  meta <- nanoparquet::read_parquet_metadata(path)$file_meta_data$key_value_metadata[[1]]
  epsg <- suppressWarnings(as.integer(meta$value[match("crs_epsg", meta$key)]))
  if (length(epsg) != 1 || is.na(epsg)) epsg <- 4269L

  shapes <- sf::st_as_sfc(structure(as.list(boundaries$geometry[rows]), class = "WKB"), crs = epsg)
  sf::st_sf(tibble::as_tibble(df), geometry = shapes)
}

sdoh_filter_states <- function(df, fips) {
  if (is.null(fips)) return(df)
  df[substr(df$GEOID, 1, 2) %in% fips, , drop = FALSE]
}

sdoh_bind <- function(pieces, geometry) {
  out <- do.call(rbind, pieces)
  if (!geometry) {
    out <- tibble::as_tibble(out)
  }
  rownames(out) <- NULL
  out
}

# --- The engine ------------------------------------------------------------------

# Reads one index for one geography and scope, over one or more years.
# Columns, in order: GEOID, NAME*, year, geo, scope*, tot_pop*, scores, geometry*
# (* only when requested or applicable).
sdoh_get <- function(index, type = NULL, geo, year, scope = NULL, version, states,
                     info, geometry, release, cache, quiet) {
  spec <- sdoh_index_spec(index, type)

  # 1. Arguments
  geo     <- sdoh_check_geo(geo, allowed = spec$geos, what = paste("The", spec$label))
  year    <- sdoh_check_year(year, geo)
  version <- rlang::arg_match0(version, values = c("both", "raw", "best"), arg_nm = "version")
  if (spec$has_scope) {
    scope <- rlang::arg_match0(scope, values = c("national", "state"), arg_nm = "scope")
  }
  sdoh_check_flags(info = info, geometry = geometry, cache = cache, quiet = quiet)
  fips <- sdoh_state_fips(states)
  if (geometry) rlang::check_installed("sf", reason = "to return boundaries (geometry = TRUE).")

  # 2. Release
  tag         <- sdoh_resolve_release(spec$series, release)
  tag_version <- sdoh_release_version(tag)

  score_cols <- switch(version, both = c(spec$raw, spec$best), raw = spec$raw, best = spec$best)

  # 3. One piece per year
  pieces <- lapply(year, function(y) {
    file   <- sdoh_file_name(spec$prefix, geo, y, if (spec$has_scope) scope)
    scores <- sdoh_read(sdoh_download(tag, file, cache, quiet))

    out <- data.frame(GEOID = scores$GEOID, year = y, geo = geo, stringsAsFactors = FALSE)
    if (spec$has_scope) out$scope <- scope
    if (info) {
      gi <- sdoh_read_geoinfo(geo, y, tag_version, cache, quiet)
      at <- match(out$GEOID, gi$GEOID)
      out <- cbind(out["GEOID"], NAME = gi$NAME[at], out[setdiff(names(out), "GEOID")],
                   tot_pop = gi$tot_pop[at], stringsAsFactors = FALSE)
    }
    out <- cbind(out, scores[, score_cols, drop = FALSE])
    out <- sdoh_filter_states(out, fips)
    out <- out[order(out$GEOID), , drop = FALSE]
    if (geometry) out <- sdoh_attach_geometry(out, geo, y, tag_version, cache, quiet)
    out
  })

  sdoh_bind(pieces, geometry)
}
