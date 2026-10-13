#' Get the pre-computed Index of Concentration at the Extremes
#'
#' @description
#' Downloads the five pre-computed measures of the Index of Concentration at
#' the Extremes (ICE) from the
#' [ReproducibleSDOH-data](https://github.com/HanLabCollaboration/ReproducibleSDOH-data)
#' repository. No Census API key is needed.
#'
#' Files cover census tracts (ACS 5-year 2011 onwards) and block groups (2013
#' onwards), for the 50 states and the District of Columbia. ICE has no
#' `scope`: each value depends only on the area itself.
#'
#' To compute the measures yourself, use `ReproducibleNDI::computeICE()`.
#'
#' @inheritParams getYostIndex
#' @param version Which version of the measures to return:
#'   * `"raw"`: computed from the ACS estimates as published.
#'   * `"best"`: with missing measures imputed from neighboring areas. These
#'     columns carry the suffix `Imputed`.
#'   * `"both"` (default): both, side by side.
#'
#' @return A tibble with one row per area and year, sorted by `GEOID` within
#'   each year, with columns:
#'   * `GEOID`: Census identifier, as text (it has leading zeros).
#'   * `NAME`, `tot_pop`: only if `info = TRUE`.
#'   * `year`, `geo`.
#'   * The five measures, raw and/or with the suffix `Imputed`, depending on
#'     `version`:
#'       * `ICE_inc`: income (high-income minus low-income households).
#'       * `ICE_edu`: education (bachelor's degree or more minus less than
#'         high school, age 25 and over).
#'       * `ICE_rewb`: race/ethnicity (non-Hispanic White minus non-Hispanic
#'         Black).
#'       * `ICE_wbinc`: race and income (high-income non-Hispanic White minus
#'         low-income Black households).
#'       * `ICE_wpcinc`: income among non-Hispanic White households
#'         (high-income minus low-income).
#'
#'   Every value lies between -1 (most deprived) and +1 (most privileged).
#'
#'   With `geometry = TRUE`, an `sf` object with the same columns and a
#'   `geometry` column (NAD83, EPSG:4269).
#'
#' @seealso [getYostIndex()], [getNDI()], [getGeoInfo()]
#'
#' @export
#'
#' @examples
#' \dontrun{
#'   # ICE for every US census tract, 2018-2022 ACS
#'   ice <- getICE(geo = "tract", year = 2022)
#'
#'   # Raw measures only, block groups in Illinois
#'   ice_il <- getICE(geo = "block group", year = 2022, version = "raw", states = "IL")
#' }
getICE <- function(
    geo      = "tract",
    year     = 2022,
    version  = "both",
    states   = NULL,
    info     = TRUE,
    geometry = FALSE,
    release  = "latest",
    cache    = TRUE,
    quiet    = FALSE
) {
  sdoh_get(
    index = "ice", geo = geo, year = year, version = version, states = states,
    info = info, geometry = geometry, release = release, cache = cache, quiet = quiet
  )
}
