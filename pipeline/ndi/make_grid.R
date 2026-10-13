#!/usr/bin/env Rscript
# =============================================================================
# ndi/make_grid.R — writes the task lists, one CSV per memory tier.
#
#   Rscript pipeline/ndi/make_grid.R            # full grid  -> grids/tasks_<tier>.csv
#   Rscript pipeline/ndi/make_grid.R --pilot    # pilot grid -> grids/pilot_<tier>.csv
#
# Each row is one SLURM array task:
#   task_id, index, series, geo, scope, year, tier, file
# =============================================================================

INDEX_DIR <- local({
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  if (length(f) > 0) dirname(normalizePath(f)) else getwd()
})
source(file.path(INDEX_DIR, "config.R"))

pilot <- "--pilot" %in% commandArgs(trailingOnly = TRUE)

grid <- do.call(rbind, lapply(names(SERIES), function(s) {
  expand.grid(
    index = INDEX, series = s, geo = SERIES[[s]]$geos, scope = SERIES[[s]]$scopes,
    year = YEAR_MIN:YEAR_MAX, stringsAsFactors = FALSE
  )
}))
grid <- grid[!(grid$geo == "block group" & grid$year < YEAR_MIN_BLOCK_GROUP), ]
grid$tier <- unname(TIER_BY_GEO[grid$geo])
grid$file <- mapply(file_name, grid$series, grid$geo, grid$scope, grid$year, USE.NAMES = FALSE)

if (pilot) {
  # 2022 only. Tract: every series, with both Messer scopes (the state task
  # should reuse the national download). Block group: Messer national, to
  # measure memory and time.
  keep <- grid$year == 2022L & (
    (grid$geo == "tract" & (grid$series == "messer" | grid$scope %in% c("national", "none"))) |
    (grid$geo == "block group" & grid$series == "messer" & grid$scope == "national")
  )
  grid <- grid[keep, ]
}

# National before state: they make the same Census calls, so the state task
# reuses what the national task downloaded.
grid <- grid[order(grid$tier, grid$scope == "state", grid$series, grid$year), ]

dir.create(GRID_DIR, recursive = TRUE, showWarnings = FALSE)
prefix <- if (pilot) "pilot" else "tasks"

for (tier in unique(grid$tier)) {
  g <- grid[grid$tier == tier, ]
  g <- cbind(task_id = seq_len(nrow(g)), g)
  path <- file.path(GRID_DIR, sprintf("%s_%s.csv", prefix, tier))
  write.csv(g, path, row.names = FALSE)
  cat(sprintf("%-7s %3d tasks -> %s\n", tier, nrow(g), path))
}

cat("\nTasks by series, geo, scope and tier:\n")
counts <- as.data.frame(
  table(series = grid$series, geo = grid$geo, scope = grid$scope, tier = grid$tier),
  responseName = "tasks"
)
print(counts[counts$tasks > 0, ], row.names = FALSE)
cat(sprintf("Total: %d tasks\n", nrow(grid)))
