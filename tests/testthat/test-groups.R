test_that("sdoh_ntile matches dplyr::ntile, with ties and missing values", {
  skip_if_not_installed("dplyr")
  set.seed(1)
  for (len in c(1, 4, 5, 7, 23, 100, 1001)) {
    x <- round(rnorm(len), 1)            # rounding creates ties
    x[sample(len, len %/% 6)] <- NA
    for (n in c(2, 4, 5, 10, 100)) {
      expect_identical(sdoh_ntile(x, n), dplyr::ntile(x, n))
    }
  }
  expect_identical(sdoh_ntile(c(NA_real_, NA_real_), 5), c(NA_integer_, NA_integer_))
})

test_that("addQuintiles adds one Quintile column per score column", {
  local_fake_repo()
  yost <- getYostIndex(year = 2022, release = "v0.1", quiet = TRUE)
  out  <- addQuintiles(yost)

  expect_s3_class(out, "tbl_df")
  expect_named(out, c(names(yost), "YostQuintile", "YostStabilizedImputedQuintile"))
  expect_identical(out$YostQuintile, sdoh_ntile(yost$Yost, 5))
  expect_identical(out[names(yost)], yost)
  expect_identical(addNtiles(yost, n = 5), out)
})

test_that("groups are computed within each year", {
  data <- data.frame(
    GEOID = sprintf("%011d", 1:20),
    year  = rep(c(2021L, 2022L), each = 10),
    Yost  = c(1:10, 101:110)      # every 2022 score is above every 2021 score
  )
  out <- addQuintiles(data)
  expect_identical(out$YostQuintile, rep(rep(1:5, each = 2), 2))

  # Row order does not matter
  shuffled <- data[c(20:11, 1:10)[c(seq(1, 19, 2), seq(2, 20, 2))], ]
  out2 <- addQuintiles(shuffled)
  expect_identical(out2$YostQuintile[match(data$GEOID, out2$GEOID)], out$YostQuintile)
})

test_that("with scope = 'state', groups are computed within each state", {
  data <- data.frame(
    GEOID = c(paste0("06", sprintf("%09d", 1:4)), paste0("44", sprintf("%09d", 1:4))),
    year  = 2022L,
    scope = "state",
    NDI   = c(1:4, 11:14)
  )
  expect_identical(addNtiles(data, n = 2)$NDINtile2, rep(c(1L, 1L, 2L, 2L), 2))

  data$scope <- "national"
  expect_warning(out <- addNtiles(data, n = 2), "not national groups")
  expect_identical(out$NDINtile2, rep(1:2, each = 4))
})

test_that("national groups stay national when only some states were asked for", {
  local_fake_repo()
  full <- addNtiles(getYostIndex(year = 2022, release = "v0.1", quiet = TRUE), n = 2)
  expect_identical(full$YostNtile2, c(1L, 1L, 2L, 2L))

  part <- getYostIndex(year = 2022, states = c("CA", "RI"), release = "v0.1", quiet = TRUE)
  out  <- addNtiles(part, n = 2)
  # Among the three rows alone the groups would be 1, 1, 2
  expect_identical(out$YostNtile2, c(1L, 2L, 2L))
  expect_identical(out$YostNtile2, full$YostNtile2[match(out$GEOID, full$GEOID)])
  expect_identical(out$YostStabilizedImputedNtile2, c(1L, 2L, 2L))

  # Also after the user filters the rows, and without the info columns
  expect_identical(addNtiles(part[part$GEOID != "06001400100", ], n = 2)$YostNtile2, c(2L, 2L))
  bare <- getYostIndex(year = 2022, states = "RI", version = "raw", info = FALSE,
                       release = "v0.1", quiet = TRUE)
  expect_identical(addNtiles(bare, n = 4)$YostQuartile, 4L)

  # Several years: each against its own year
  years <- getYostIndex(year = 2021:2022, states = "RI", release = "v0.1", quiet = TRUE)
  expect_identical(addNtiles(years, n = 4)$YostQuartile, c(4L, 4L))

  # ICE has no scope: always against the whole country
  ice <- getICE(year = 2022, states = "RI", release = "v0.1", quiet = TRUE)
  expect_identical(addNtiles(ice, n = 4)$ICE_incQuartile, 4L)
  expect_identical(addNtiles(ice, n = 4)$ICE_wpcincImputedQuartile, 4L)
})

test_that("state-scope groups are computed within each state of the file", {
  local_fake_repo()
  part <- getYostIndex(year = 2022, scope = "state", states = c("CA", "RI"),
                       release = "v0.1", quiet = TRUE)
  expect_identical(addNtiles(part, n = 2)$YostNtile2, c(1L, 2L, 1L))
  # One California tract alone keeps its place among California's two
  expect_identical(addNtiles(part[2, ], n = 2)$YostNtile2, 2L)
})

test_that("a missing score in the data has no group, and own columns use the rows", {
  local_fake_repo()
  part <- getYostIndex(year = 2022, states = c("CA", "RI"), release = "v0.1", quiet = TRUE)
  part$Yost[2] <- NA
  part$mine <- c(3, 1, 2)
  expect_warning(out <- addNtiles(part, n = 2, cols = c("Yost", "mine")), "mine")
  expect_identical(out$YostNtile2, c(1L, NA, 2L))
  expect_identical(out$mineNtile2, c(2L, 1L, 1L))
})

test_that("missing scores get a missing group and are not counted", {
  data <- data.frame(GEOID = sprintf("%011d", 1:6), year = 2022L,
                     Yost = c(NA, 1, 2, 3, 4, 5))
  expect_identical(addQuintiles(data)$YostQuintile, c(NA, 1:5))
})

test_that("the group column is named after n, or after suffix", {
  data <- data.frame(GEOID = sprintf("%011d", 1:200), Yost = 1:200)
  expect_true("YostTertile"    %in% names(addNtiles(data, n = 3)))
  expect_true("YostQuartile"   %in% names(addNtiles(data, n = 4)))
  expect_true("YostDecile"     %in% names(addNtiles(data, n = 10)))
  expect_true("YostPercentile" %in% names(addNtiles(data, n = 100)))
  expect_true("YostNtile7"     %in% names(addNtiles(data, n = 7)))
  expect_true("Yost_q5"        %in% names(addQuintiles(data, suffix = "_q5")))
  expect_identical(range(addNtiles(data, n = 100)$YostPercentile), c(1L, 100L))
})

test_that("cols picks the columns, and works on columns the package does not know", {
  data <- data.frame(GEOID = sprintf("%011d", 1:10), Yost = 1:10, other = 10:1)
  out <- addQuintiles(data, cols = "other")
  expect_named(out, c("GEOID", "Yost", "other", "otherQuintile"))
  expect_identical(out$otherQuintile, rep(5:1, each = 2))

  ice <- data.frame(GEOID = sprintf("%011d", 1:10), ICE_inc = 1:10, ICE_incImputed = 1:10)
  expect_named(addQuintiles(ice),
               c(names(ice), "ICE_incQuintile", "ICE_incImputedQuintile"))
})

test_that("bad arguments are rejected", {
  data <- data.frame(GEOID = c("01", "02"), Yost = 1:2, label = c("a", "b"))
  expect_error(addNtiles(data), "'n'")
  expect_error(addNtiles(data, n = 1), "'n'")
  expect_error(addNtiles(data, n = 2.5), "'n'")
  expect_error(addNtiles(1:3, n = 5), "data frame")
  expect_error(addQuintiles(data, cols = "nope"), "not found")
  expect_error(addQuintiles(data, cols = "label"), "numeric")
  expect_error(addQuintiles(data["GEOID"]), "No score column")
  expect_error(addQuintiles(data, suffix = ""), "suffix")
})

test_that("an sf object keeps its class and geometry", {
  skip_if_not_installed("sf")
  local_fake_repo()
  yost <- getYostIndex(year = 2022, geometry = TRUE, release = "v0.1", quiet = TRUE)
  out  <- addQuintiles(yost)
  expect_s3_class(out, "sf")
  expect_identical(out$YostQuintile, sdoh_ntile(yost$Yost, 5))
})
