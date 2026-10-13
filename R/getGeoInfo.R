#' Get area names, population and boundaries
#'
#' @description
#' Downloads, for census tracts or block groups, each area's name and total
#' population and, optionally, its boundary, from the
#' [ReproducibleSDOH-data](https://github.com/HanLabCollaboration/ReproducibleSDOH-data)
#' repository. No Census API key is needed.
#'
#' These files have exactly the same areas (`GEOID`s) as the index files for
#' the same geography and year, so they join one to one with the output of
#' [getYostIndex()], [getNDI()] and [getICE()]. Those functions add the name
#' and population themselves when `info = TRUE`.
#'
#' Area definitions change with the 2020 census: years 2011-2019 use 2010
#' tracts and block groups, and years from 2020 use the 2020 definitions.
#'
#' @inheritParams getYostIndex
#' @param states Optional vector of states to keep, as 2-letter postal codes
#'   (`c("CA", "NY")`) or 2-digit FIPS codes (`"06"`). `NULL` (default) returns
#'   the 50 states and DC.
#' @param release Which data release to read: `"latest"` (default) for the
#'   release this version of the package was built for, or a version such as
#'   `"v2026.10"` to pin one.
#'
#' @return A tibble with one row per area and year, sorted by `GEOID` within
#'   each year, with columns:
#'   * `GEOID`: Census identifier, as text (it has leading zeros).
#'   * `NAME`: the area's name, for example
#'     `"Census Tract 201; Autauga County; Alabama"`.
#'   * `year`, `geo`.
#'   * `tot_pop`: total population (ACS table B01003) for that 5-year period.
#'
#'   With `geometry = TRUE`, an `sf` object with the same columns and a
#'   `geometry` column (NAD83, EPSG:4269). A few areas, typically water-only,
#'   have an empty boundary.
#'
#' @seealso [getYostIndex()], [getNDI()], [getICE()]
#'
#' @export
#'
#' @examples
#' \dontrun{
#'   # Names and population of every US census tract, 2018-2022 ACS
#'   tracts <- getGeoInfo(geo = "tract", year = 2022)
#'
#'   # Block-group boundaries for Rhode Island
#'   ri <- getGeoInfo(geo = "block group", year = 2022, states = "RI", geometry = TRUE)
#' }
getGeoInfo <- function(
    geo      = "tract",
    year     = 2022,
    states   = NULL,
    geometry = FALSE,
    release  = "latest",
    cache    = TRUE,
    quiet    = FALSE
) {
  # --- 1. Arguments -------------------------------------------------------------
  geo  <- sdoh_check_geo(geo, what = "Geography information")
  year <- sdoh_check_year(year, geo)
  sdoh_check_flags(geometry = geometry, cache = cache, quiet = quiet)
  fips <- sdoh_state_fips(states)
  if (geometry) rlang::check_installed("sf", reason = "to return boundaries (geometry = TRUE).")

  # --- 2. Release ---------------------------------------------------------------
  tag_version <- sdoh_release_version(sdoh_resolve_release("geoinfo", release))

  # --- 3. One piece per year -------------------------------------------------------
  pieces <- lapply(year, function(y) {
    gi  <- sdoh_read_geoinfo(geo, y, tag_version, cache, quiet)
    out <- data.frame(GEOID = gi$GEOID, NAME = gi$NAME, year = y, geo = geo,
                      tot_pop = gi$tot_pop, stringsAsFactors = FALSE)
    out <- sdoh_filter_states(out, fips)
    out <- out[order(out$GEOID), , drop = FALSE]
    if (geometry) out <- sdoh_attach_geometry(out, geo, y, tag_version, cache, quiet)
    out
  })

  sdoh_bind(pieces, geometry)
}
