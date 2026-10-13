#!/usr/bin/env Rscript
# =============================================================================
# geography/make_grid.R — writes the task list.
#
#   Rscript pipeline/geography/make_grid.R            # full grid  -> grids/tasks_standard.csv
#   Rscript pipeline/geography/make_grid.R --pilot    # pilot grid -> grids/pilot_standard.csv
#
# Each row is one SLURM array task:
#   task_id, index, geo, year, tier, geoinfo_file, geometry_file
# =============================================================================

INDEX_DIR <- local({
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  if (length(f) > 0) dirname(normalizePath(f)) else getwd()
})
source(file.path(INDEX_DIR, "config.R"))

pilot <- "--pilot" %in% commandArgs(trailingOnly = TRUE)

grid <- expand.grid(index = INDEX, geo = GEOS, year = YEAR_MIN:YEAR_MAX, stringsAsFactors = FALSE)
grid <- grid[!(grid$geo == "block group" & grid$year < YEAR_MIN_BLOCK_GROUP), ]
grid$tier          <- "standard"
grid$geoinfo_file  <- mapply(file_name, "geoinfo",  grid$geo, grid$year, USE.NAMES = FALSE)
grid$geometry_file <- mapply(file_name, "geometry", grid$geo, grid$year, USE.NAMES = FALSE)

if (pilot) {
  # Tract 2022 (ordinary boundaries) and tract 2011 (full-detail boundaries,
  # the heaviest case).
  grid <- grid[grid$geo == "tract" & grid$year %in% c(2011L, 2022L), ]
}

grid <- grid[order(grid$geo, grid$year), ]
grid <- cbind(task_id = seq_len(nrow(grid)), grid)

dir.create(GRID_DIR, recursive = TRUE, showWarnings = FALSE)
path <- file.path(GRID_DIR, sprintf("%s_standard.csv", if (pilot) "pilot" else "tasks"))
write.csv(grid, path, row.names = FALSE)
cat(sprintf("standard %3d tasks -> %s\n", nrow(grid), path))

cat("\nTasks by geo:\n")
print(as.data.frame(table(geo = grid$geo), responseName = "tasks"), row.names = FALSE)
