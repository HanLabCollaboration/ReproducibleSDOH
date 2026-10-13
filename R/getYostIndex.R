#' Get the pre-computed Yost Index
#'
#' @description
#' Downloads the pre-computed Yost Index, a composite measure of neighborhood
#' socioeconomic status, from the
#' [ReproducibleSDOH-data](https://github.com/HanLabCollaboration/ReproducibleSDOH-data)
#' repository. No Census API key is needed.
#'
#' Files cover census tracts (ACS 5-year 2011 onwards) and block groups (2013
#' onwards), for the 50 states and the District of Columbia, at national and
#' state scope. Files are cached after the first download, so later calls with
#' the same arguments read from disk.
#'
#' To compute the index yourself, with other options or geographies, use
#' `ReproducibleYostIndex::computeYostIndex()`.
#'
#' @param geo Geography: `"tract"` (default) or `"block group"` (alias `"cbg"`).
#' @param year ACS 5-year year or years, named by the last year of the period
#'   (`2022` is the 2018-2022 ACS). A vector such as `2019:2022` returns all
#'   those years stacked, told apart by the `year` column.
#' @param scope The set of areas the index was computed against: `"national"`
#'   (default) compares every area with the whole country; `"state"` computes
#'   the index separately within each state, so values are comparable only
#'   inside a state.
#' @param version Which version of the score to return:
#'   * `"raw"`: computed from the ACS estimates as published. Areas with a
#'     missing component have no score.
#'   * `"best"`: with small-area estimates stabilized and missing components
#'     imputed from neighboring areas, so far fewer areas are missing.
#'   * `"both"` (default): both, side by side.
#' @param states Optional vector of states to keep, as 2-letter postal codes
#'   (`c("CA", "NY")`) or 2-digit FIPS codes (`"06"`). `NULL` (default) returns
#'   the 50 states and DC. Filtering happens after the index was computed: with
#'   `scope = "national"`, scores stay relative to the whole country.
#' @param info Logical. If `TRUE` (default), adds each area's `NAME` and total
#'   population (`tot_pop`). See [getGeoInfo()].
#' @param geometry Logical. If `TRUE`, attaches each area's boundary and
#'   returns an `sf` object (needs the `sf` package). Boundary files are large.
#'   Defaults to `FALSE`.
#' @param release Which data release to read: `"latest"` (default) for the
#'   release this version of the package was built for, or a version such as
#'   `"v2026.10"` to pin one, for example to reproduce a published analysis.
#' @param cache Logical. If `TRUE` (default), keeps downloaded files in
#'   [sdoh_cache_dir()]. If `FALSE`, files are kept for the R session only.
#' @param quiet Logical. If `TRUE`, suppresses download messages.
#'
#' @return A tibble with one row per area and year, sorted by `GEOID` within
#'   each year, with columns:
#'   * `GEOID`: Census identifier, as text (it has leading zeros).
#'   * `NAME`, `tot_pop`: only if `info = TRUE`.
#'   * `year`, `geo`, `scope`.
#'   * `Yost` (raw) and/or `YostStabilizedImputed` (best), depending on
#'     `version`. Higher values mean higher socioeconomic status.
#'
#'   With `geometry = TRUE`, an `sf` object with the same columns and a
#'   `geometry` column (NAD83, EPSG:4269).
#'
#' @seealso [getNDI()], [getICE()], [getGeoInfo()]
#'
#' @export
#'
#' @examples
#' \dontrun{
#'   # Yost Index for every US census tract, 2018-2022 ACS
#'   yost <- getYostIndex(geo = "tract", year = 2022)
#'
#'   # Block groups in California and New York, computed within each state
#'   yost_bg <- getYostIndex(geo = "block group", year = 2022, scope = "state",
#'                           states = c("CA", "NY"))
#'
#'   # Only the stabilized and imputed version, for several years
#'   yost_best <- getYostIndex(year = 2019:2022, version = "best")
#'
#'   # With boundaries, for mapping
#'   yost_map <- getYostIndex(year = 2022, states = "RI", geometry = TRUE)
#' }
getYostIndex <- function(
    geo      = "tract",
    year     = 2022,
    scope    = "national",
    version  = "both",
    states   = NULL,
    info     = TRUE,
    geometry = FALSE,
    release  = "latest",
    cache    = TRUE,
    quiet    = FALSE
) {
  sdoh_get(
    index = "yost", geo = geo, year = year, scope = scope, version = version,
    states = states, info = info, geometry = geometry, release = release,
    cache = cache, quiet = quiet
  )
}
