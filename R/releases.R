# Releases of ReproducibleSDOH-data this version of the package reads by default,
# and how each index is laid out in them.

sdoh_base_url <- function() {
  getOption(
    "ReproducibleSDOH.base_url",
    "https://github.com/HanLabCollaboration/ReproducibleSDOH-data/releases/download"
  )
}

# The release used for `release = "latest"`, per release series.
sdoh_latest_releases <- function() {
  c(
    yost     = "yost-v2026.10",
    ndi      = "ndi-v2026.10",
    ice      = "ice-v2026.10",
    geoinfo  = "geoinfo-v2026.10",
    geometry = "geometry-v2026.10"
  )
}

# Turn `release` into a tag such as "yost-v2026.10".
#   "latest"        -> the default tag of that series
#   "v2026.10"      -> "<series>-v2026.10"
#   "yost-v2026.10" -> unchanged
sdoh_resolve_release <- function(series, release = "latest") {
  if (!is.character(release) || length(release) != 1 || is.na(release) || !nzchar(release)) {
    stop("'release' must be \"latest\" or a single release tag such as \"v2026.10\".")
  }
  if (release == "latest") return(unname(sdoh_latest_releases()[[series]]))
  if (grepl("^v", release)) return(paste0(series, "-", release))
  release
}

# The version part of a tag ("yost-v2026.10" -> "v2026.10"), used to find the
# geoinfo and geometry releases that belong with an index release.
sdoh_release_version <- function(tag) sub("^[a-z]+-", "", tag)

ice_measures <- function() c("ICE_inc", "ICE_edu", "ICE_rewb", "ICE_wbinc", "ICE_wpcinc")

# How one index is stored: its release series, file prefix, whether its files
# have a scope, its raw and best score columns, and its geographies.
sdoh_index_spec <- function(index, type = NULL) {
  switch(
    index,
    yost = list(
      label = "Yost Index", series = "yost", prefix = "yost", has_scope = TRUE,
      raw = "Yost", best = "YostStabilizedImputed",
      geos = c("tract", "block group")
    ),
    ndi = list(
      label = if (type == "messer") "Messer NDI" else "Powell-Wiley NDI",
      series = "ndi", has_scope = TRUE,
      prefix = if (type == "messer") "ndi_messer" else "ndi_powellwiley",
      raw = "NDI", best = "NDIImputed",
      geos = "tract"
    ),
    ice = list(
      label = "ICE", series = "ice", prefix = "ice", has_scope = FALSE,
      raw = ice_measures(), best = paste0(ice_measures(), "Imputed"),
      geos = c("tract", "block group"),
      # Household income by race is not published for block groups.
      tract_only = c("ICE_wbinc", "ICE_wpcinc")
    ),
    stop("Unknown index: ", index)
  )
}

# "block group" -> "block_group", as used in file names.
sdoh_geo_tag <- function(geo) gsub(" ", "_", geo)

sdoh_file_name <- function(prefix, geo, year, scope = NULL) {
  paste0(paste(c(prefix, sdoh_geo_tag(geo), scope, as.integer(year)), collapse = "_"), ".parquet")
}
