#' Get the pre-computed Neighborhood Deprivation Index
#'
#' @description
#' Downloads the pre-computed Neighborhood Deprivation Index (NDI), by the
#' Messer or the Powell-Wiley method, from the
#' [ReproducibleSDOH-data](https://github.com/HanLabCollaboration/ReproducibleSDOH-data)
#' repository. No Census API key is needed.
#'
#' Both methods cover census tracts only (ACS 5-year 2011 onwards), because
#' some of their ACS tables are not published for block groups. They cover the
#' 50 states and the District of Columbia, at national and state scope. For a
#' block-group measure, see [getICE()].
#'
#' To compute the index yourself, with other options or geographies, use
#' `ReproducibleNDI::computeNDI()`.
#'
#' @inheritParams getYostIndex
#' @param type The NDI method: `"messer"` (default) or `"powell_wiley"`.
#' @param geo Geography. Only `"tract"` (default) is available for the NDI.
#' @param version Which version of the score to return:
#'   * `"raw"`: computed from the ACS estimates as published. Areas with a
#'     missing component have no score.
#'   * `"best"`: with missing components imputed from neighboring areas, so
#'     far fewer areas are missing.
#'   * `"both"` (default): both, side by side.
#'
#' @return A tibble with one row per area and year, sorted by `GEOID` within
#'   each year, with columns:
#'   * `GEOID`: Census identifier, as text (it has leading zeros).
#'   * `NAME`, `tot_pop`: only if `info = TRUE`.
#'   * `year`, `geo`, `scope`.
#'   * `NDI` (raw) and/or `NDIImputed` (best), depending on `version`. Higher
#'     values mean more deprivation.
#'
#'   With `geometry = TRUE`, an `sf` object with the same columns and a
#'   `geometry` column (NAD83, EPSG:4269).
#'
#'   The two methods give different indices on different scales; do not mix
#'   them in one analysis.
#'
#' @seealso [getYostIndex()], [getICE()], [getGeoInfo()]
#'
#' @export
#'
#' @examples
#' \dontrun{
#'   # Messer NDI for every US census tract, 2018-2022 ACS
#'   ndi <- getNDI(type = "messer", geo = "tract", year = 2022)
#'
#'   # Powell-Wiley NDI within each state, Texas only
#'   ndi_tx <- getNDI(type = "powell_wiley", year = 2022, scope = "state", states = "TX")
#' }
getNDI <- function(
    type     = "messer",
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
  type <- rlang::arg_match0(type, values = c("messer", "powell_wiley"), arg_nm = "type")
  sdoh_get(
    index = "ndi", type = type, geo = geo, year = year, scope = scope,
    version = version, states = states, info = info, geometry = geometry,
    release = release, cache = cache, quiet = quiet
  )
}
