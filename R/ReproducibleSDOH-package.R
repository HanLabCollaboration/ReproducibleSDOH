#' ReproducibleSDOH: pre-computed neighborhood socioeconomic indices
#'
#' Downloads pre-computed indices from the
#' [ReproducibleSDOH-data](https://github.com/HanLabCollaboration/ReproducibleSDOH-data)
#' repository, without a Census API key:
#'
#' * [getYostIndex()]: the Yost Index.
#' * [getNDI()]: the Neighborhood Deprivation Index (Messer or Powell-Wiley).
#' * [getICE()]: the Index of Concentration at the Extremes.
#' * [getGeoInfo()]: area names, total population and, optionally, boundaries.
#'
#' Files are cached after the first download; see [sdoh_cache_dir()].
#'
#' @keywords internal
"_PACKAGE"
