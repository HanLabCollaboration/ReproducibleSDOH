test_that("getYostIndex returns a sorted tibble with the documented columns", {
  local_fake_repo()
  out <- getYostIndex(geo = "tract", year = 2022, release = "v0.1", quiet = TRUE)

  expect_s3_class(out, "tbl_df")
  expect_named(out, c("GEOID", "NAME", "year", "geo", "scope", "tot_pop",
                      "Yost", "YostStabilizedImputed"))
  expect_identical(out$GEOID, sort(fake_geoids("tract")))
  expect_type(out$GEOID, "character")
  expect_identical(unique(out$year), 2022L)
  expect_identical(unique(out$geo), "tract")
  expect_identical(unique(out$scope), "national")
  # Scores and geography info stay attached to the right GEOID after sorting
  expect_equal(out$Yost[out$GEOID == "01001020100"], 201)
  expect_equal(out$YostStabilizedImputed[out$GEOID == "01001020100"], 201.5)
  expect_identical(out$NAME[out$GEOID == "44001030100"], "Area 44001030100")
  expect_identical(out$tot_pop[out$GEOID == "44001030100"], 400L)
})

test_that("version selects the raw or best column", {
  local_fake_repo()
  raw  <- getYostIndex(year = 2022, version = "raw",  info = FALSE, release = "v0.1", quiet = TRUE)
  best <- getYostIndex(year = 2022, version = "best", info = FALSE, release = "v0.1", quiet = TRUE)
  expect_named(raw,  c("GEOID", "year", "geo", "scope", "Yost"))
  expect_named(best, c("GEOID", "year", "geo", "scope", "YostStabilizedImputed"))
  expect_error(getYostIndex(year = 2022, version = "all", release = "v0.1"), "version")
})

test_that("scope and geo pick the right file", {
  local_fake_repo()
  state <- getYostIndex(year = 2022, scope = "state", info = FALSE, release = "v0.1", quiet = TRUE)
  expect_identical(unique(state$scope), "state")
  expect_equal(min(state$Yost), 301)

  bg <- getYostIndex(geo = "cbg", year = 2022, release = "v0.1", quiet = TRUE)
  expect_identical(unique(bg$geo), "block group")
  expect_identical(bg$GEOID, sort(fake_geoids("block group")))
  expect_true(all(startsWith(bg$NAME, "Area ")))
})

test_that("states filters by postal code or FIPS, keeping leading zeros", {
  local_fake_repo()
  ca <- getYostIndex(year = 2022, states = "CA", release = "v0.1", quiet = TRUE)
  expect_identical(ca$GEOID, c("06001400100", "06001400200"))

  mixed <- getYostIndex(year = 2022, states = c("01", "ri"), release = "v0.1", quiet = TRUE)
  expect_identical(mixed$GEOID, c("01001020100", "44001030100"))

  none <- getYostIndex(year = 2022, states = "WY", release = "v0.1", quiet = TRUE)
  expect_identical(nrow(none), 0L)

  expect_error(getYostIndex(year = 2022, states = c("CA", "XX", "PR"), release = "v0.1"),
               "Invalid state\\(s\\): XX, PR")
})

test_that("several years are stacked and told apart by the year column", {
  local_fake_repo()
  out <- getYostIndex(year = c(2022, 2021), info = FALSE, release = "v0.1", quiet = TRUE)
  expect_identical(nrow(out), 8L)
  expect_identical(out$year, rep(c(2021L, 2022L), each = 4))
  expect_equal(out$Yost[out$year == 2021 & out$GEOID == "01001020100"], 101)
  expect_equal(out$Yost[out$year == 2022 & out$GEOID == "01001020100"], 201)
})

test_that("year and geo are validated before anything is downloaded", {
  local_fake_repo()
  expect_error(getYostIndex(year = 2010, release = "v0.1"), "starts in 2011")
  expect_error(getYostIndex(geo = "block group", year = 2012, release = "v0.1"), "starts in 2013")
  expect_error(getYostIndex(year = "2022", release = "v0.1"), "whole numbers")
  expect_error(getYostIndex(year = 2022.5, release = "v0.1"), "whole numbers")
  expect_error(getYostIndex(geo = "county", year = 2022, release = "v0.1"), "geo")
  expect_error(getYostIndex(year = 2022, scope = "county", release = "v0.1"), "scope")
  expect_error(getYostIndex(year = 2022, info = "yes", release = "v0.1"), "'info' must be TRUE or FALSE")
})

test_that("a combination that is not published gives a clear error", {
  local_fake_repo()
  expect_error(
    getYostIndex(geo = "block group", year = 2022, scope = "state", release = "v0.1", quiet = TRUE),
    "'yost_block_group_state_2022.parquet' is not part of release 'yost-v0.1'"
  )
  expect_error(getYostIndex(year = 2022, release = "v9.9", quiet = TRUE),
               "Could not download the file list of release 'yost-v9.9'")
})

test_that("getNDI reads the method asked for", {
  local_fake_repo()
  messer <- getNDI(type = "messer", year = 2022, release = "v0.1", quiet = TRUE)
  pw     <- getNDI(type = "powell_wiley", year = 2022, release = "v0.1", quiet = TRUE)
  expect_named(messer, c("GEOID", "NAME", "year", "geo", "scope", "tot_pop", "NDI", "NDIImputed"))
  expect_equal(messer$NDI[1], 11)
  expect_equal(pw$NDI[1], 21)
  expect_error(getNDI(type = "powell_wiley", geo = "block group", year = 2022, release = "v0.1"),
               "Powell-Wiley NDI is published for tract only")
  expect_error(getNDI(type = "singh", year = 2022, release = "v0.1"), "type")
})

test_that("getICE returns the five measures without a scope column", {
  local_fake_repo()
  m <- c("ICE_inc", "ICE_edu", "ICE_rewb", "ICE_wbinc", "ICE_wpcinc")
  both <- getICE(year = 2022, release = "v0.1", quiet = TRUE)
  expect_named(both, c("GEOID", "NAME", "year", "geo", "tot_pop", m, paste0(m, "Imputed")))
  raw <- getICE(year = 2022, version = "raw", info = FALSE, release = "v0.1", quiet = TRUE)
  expect_named(raw, c("GEOID", "year", "geo", m))
  best <- getICE(year = 2022, version = "best", info = FALSE, release = "v0.1", quiet = TRUE)
  expect_named(best, c("GEOID", "year", "geo", paste0(m, "Imputed")))
})

test_that("getGeoInfo returns names and population", {
  local_fake_repo()
  out <- getGeoInfo(geo = "tract", year = 2022, states = "CA", release = "v0.1", quiet = TRUE)
  expect_s3_class(out, "tbl_df")
  expect_named(out, c("GEOID", "NAME", "year", "geo", "tot_pop"))
  expect_identical(out$GEOID, c("06001400100", "06001400200"))
  expect_identical(out$tot_pop, c(200L, 300L))
})

test_that("geometry = TRUE returns an sf object with the right boundary per row", {
  skip_if_not_installed("sf")
  local_fake_repo()
  out <- getYostIndex(year = 2022, states = c("RI", "AL"), geometry = TRUE,
                      release = "v0.1", quiet = TRUE)
  expect_s3_class(out, "sf")
  expect_identical(out$GEOID, c("01001020100", "44001030100"))
  expect_identical(sf::st_crs(out)$epsg, 4269L)
  # The fake boundary of the i-th tract is the unit square starting at x = i
  expect_equal(unname(sf::st_bbox(out[1, ])[c("xmin", "xmax")]), c(1, 2))
  expect_equal(unname(sf::st_bbox(out[2, ])[c("xmin", "xmax")]), c(4, 5))

  geo <- getGeoInfo(year = 2022, geometry = TRUE, release = "v0.1", quiet = TRUE)
  expect_s3_class(geo, "sf")
  expect_identical(nrow(geo), 4L)
})

test_that("downloads are cached, and verified against the checksum list", {
  base <- local_fake_repo()
  first <- getYostIndex(year = 2022, info = FALSE, release = "v0.1", quiet = TRUE)
  expect_true(file.exists(file.path(sdoh_cache_dir(), "yost-v0.1", "yost_tract_national_2022.parquet")))

  # With the source gone, the cached copy still answers
  unlink(file.path(base, "yost-v0.1"), recursive = TRUE)
  again <- getYostIndex(year = 2022, info = FALSE, release = "v0.1", quiet = TRUE)
  expect_identical(again, first)

  # Clearing the cache removes it
  sdoh_cache_clear("yost-v0.1")
  expect_false(dir.exists(file.path(sdoh_cache_dir(), "yost-v0.1")))
  expect_error(getYostIndex(year = 2022, info = FALSE, release = "v0.1", quiet = TRUE),
               "Could not download")
})

test_that("a file that does not match its checksum is rejected", {
  base <- local_fake_repo()
  sums_path <- file.path(base, "ndi-v0.1", "SHA256SUMS")
  sums <- readLines(sums_path)
  sums[grepl("ndi_messer_tract_national_2022", sums)] <-
    paste0(strrep("0", 64), "  ndi_messer_tract_national_2022.parquet")
  writeLines(sums, sums_path)

  expect_error(getNDI(year = 2022, info = FALSE, release = "v0.1", quiet = TRUE),
               "checksum did not match")
  expect_false(file.exists(file.path(sdoh_cache_dir(), "ndi-v0.1", "ndi_messer_tract_national_2022.parquet")))
})

test_that("release accepts latest, a version, or a full tag", {
  expect_identical(sdoh_resolve_release("yost", "latest"), "yost-v2026.10")
  expect_identical(sdoh_resolve_release("ndi", "v2027.01"), "ndi-v2027.01")
  expect_identical(sdoh_resolve_release("ice", "ice-v2026.10"), "ice-v2026.10")
  expect_identical(sdoh_release_version("geoinfo-v2026.10"), "v2026.10")
  expect_error(sdoh_resolve_release("yost", c("a", "b")), "release")
})
