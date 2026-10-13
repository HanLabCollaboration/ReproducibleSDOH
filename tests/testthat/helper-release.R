# A tiny local copy of the data repository's releases, so tests need no network.
# Releases are folders under one base folder, read through a file:// address.

fake_geoids <- function(geo) {
  ids <- c("01001020100", "06001400100", "06001400200", "44001030100")
  if (geo == "block group") paste0(ids, "1") else ids
}

write_fake_release <- function(dir, files) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  for (name in names(files)) nanoparquet::write_parquet(files[[name]], file.path(dir, name))
  sums <- vapply(names(files), function(name) {
    digest::digest(file = file.path(dir, name), algo = "sha256")
  }, character(1))
  writeLines(paste0(sums, "  ", names(files)), file.path(dir, "SHA256SUMS"))
}

# Builds releases yost-v0.1, ndi-v0.1, ice-v0.1, geoinfo-v0.1 and geometry-v0.1.
# Returns the base folder.
make_fake_releases <- function(base = tempfile("sdoh-releases-")) {
  score <- function(geo, offset) {
    ids <- fake_geoids(geo)
    # Deliberately unsorted, to check that results come back sorted by GEOID.
    data.frame(GEOID = rev(ids), value = rev(seq_along(ids)) + offset, stringsAsFactors = FALSE)
  }
  yost <- function(geo, offset) {
    s <- score(geo, offset)
    data.frame(GEOID = s$GEOID, Yost = s$value, YostStabilizedImputed = s$value + 0.5,
               stringsAsFactors = FALSE)
  }
  ndi <- function(geo, offset) {
    s <- score(geo, offset)
    data.frame(GEOID = s$GEOID, NDI = s$value, NDIImputed = s$value + 0.5, stringsAsFactors = FALSE)
  }
  ice <- function(geo) {
    s <- score(geo, 0)
    m <- c("ICE_inc", "ICE_edu", "ICE_rewb", "ICE_wbinc", "ICE_wpcinc")
    if (geo == "block group") m <- m[1:3]
    out <- data.frame(GEOID = s$GEOID, stringsAsFactors = FALSE)
    for (col in m) out[[col]] <- s$value / 10
    for (col in m) out[[paste0(col, "Imputed")]] <- s$value / 10 + 0.01
    out
  }
  geoinfo <- function(geo) {
    ids <- fake_geoids(geo)
    data.frame(GEOID = ids, NAME = paste("Area", ids), tot_pop = seq_along(ids) * 100L,
               stringsAsFactors = FALSE)
  }

  write_fake_release(file.path(base, "yost-v0.1"), list(
    "yost_tract_national_2021.parquet"       = yost("tract", 100),
    "yost_tract_national_2022.parquet"       = yost("tract", 200),
    "yost_tract_state_2022.parquet"          = yost("tract", 300),
    "yost_block_group_national_2022.parquet" = yost("block group", 400)
  ))
  write_fake_release(file.path(base, "ndi-v0.1"), list(
    "ndi_messer_tract_national_2022.parquet"      = ndi("tract", 10),
    "ndi_powellwiley_tract_national_2022.parquet" = ndi("tract", 20)
  ))
  write_fake_release(file.path(base, "ice-v0.1"), list(
    "ice_tract_2022.parquet"       = ice("tract"),
    "ice_block_group_2022.parquet" = ice("block group")
  ))
  write_fake_release(file.path(base, "geoinfo-v0.1"), list(
    "geoinfo_tract_2021.parquet"       = geoinfo("tract"),
    "geoinfo_tract_2022.parquet"       = geoinfo("tract"),
    "geoinfo_block_group_2022.parquet" = geoinfo("block group")
  ))

  if (requireNamespace("sf", quietly = TRUE)) {
    ids <- fake_geoids("tract")
    squares <- lapply(seq_along(ids), function(i) {
      sf::st_polygon(list(rbind(c(i, 0), c(i + 1, 0), c(i + 1, 1), c(i, 1), c(i, 0))))
    })
    geometry <- data.frame(GEOID = ids, stringsAsFactors = FALSE)
    geometry$geometry <- unclass(sf::st_as_binary(sf::st_sfc(squares, crs = 4269)))
    dir <- file.path(base, "geometry-v0.1")
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    nanoparquet::write_parquet(geometry, file.path(dir, "geometry_tract_2022.parquet"),
                               metadata = c(crs_epsg = "4269", geometry_encoding = "WKB"))
    writeLines(
      paste0(digest::digest(file = file.path(dir, "geometry_tract_2022.parquet"), algo = "sha256"),
             "  geometry_tract_2022.parquet"),
      file.path(dir, "SHA256SUMS")
    )
  }
  base
}

# Points the package at a fresh fake repository and an empty cache for one test.
local_fake_repo <- function(env = parent.frame()) {
  base <- make_fake_releases()
  withr::local_options(
    list(
      ReproducibleSDOH.base_url  = paste0("file://", base),
      ReproducibleSDOH.cache_dir = tempfile("sdoh-cache-")
    ),
    .local_envir = env
  )
  base
}
