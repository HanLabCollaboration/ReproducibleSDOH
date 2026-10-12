#!/usr/bin/env Rscript
# =============================================================================
# yost/make_grid.R — writes the task lists, one CSV per memory tier.
#
#   Rscript pipeline/yost/make_grid.R            # full grid  -> grids/tasks_<tier>.csv
#   Rscript pipeline/yost/make_grid.R --pilot    # pilot grid -> grids/pilot_<tier>.csv
#
# Each row is one SLURM array task: task_id, index, geo, scope, year, tier, file.
# =============================================================================

INDEX_DIR <- local({
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  if (length(f) > 0) dirname(normalizePath(f)) else getwd()
})
source(file.path(INDEX_DIR, "config.R"))

pilot <- "--pilot" %in% commandArgs(trailingOnly = TRUE)

grid <- expand.grid(
  index = INDEX, geo = GEOS, scope = SCOPES, year = YEAR_MIN:YEAR_MAX,
  stringsAsFactors = FALSE
)
grid <- grid[!(grid$geo == "block group" & grid$year < YEAR_MIN_BLOCK_GROUP), ]
grid$tier <- unname(TIER_BY_GEO[grid$geo])
grid$file <- mapply(file_name, grid$geo, grid$scope, grid$year, USE.NAMES = FALSE)

if (pilot) {
  # Tract 2022, both scopes (the state task should reuse the national download),
  # plus one block-group task (2022, national) to measure memory and time.
  keep <- grid$year == 2022L &
          (grid$geo == "tract" | (grid$geo == "block group" & grid$scope == "national"))
  grid <- grid[keep, ]
}

# National before state: they make the same Census calls, so the state task
# reuses what the national task downloaded.
grid <- grid[order(grid$tier, grid$scope != "national", grid$year), ]

dir.create(GRID_DIR, recursive = TRUE, showWarnings = FALSE)
prefix <- if (pilot) "pilot" else "tasks"

for (tier in unique(grid$tier)) {
  g <- grid[grid$tier == tier, ]
  g <- cbind(task_id = seq_len(nrow(g)), g)
  path <- file.path(GRID_DIR, sprintf("%s_%s.csv", prefix, tier))
  write.csv(g, path, row.names = FALSE)
  cat(sprintf("%-7s %3d tasks -> %s\n", tier, nrow(g), path))
}

cat("\nTasks by geo, scope and tier:\n")
counts <- as.data.frame(table(geo = grid$geo, scope = grid$scope, tier = grid$tier),
                        responseName = "tasks")
print(counts[counts$tasks > 0, ], row.names = FALSE)
