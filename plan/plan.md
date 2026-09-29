# ReproducibleSDOH — Plan

_Drafted 2026-09-29. This is a living document: update it as decisions change._

Family plans: [`plan_NDI.md`](plan_NDI.md) (Messer · Powell-Wiley · ICE; the first family through the pipeline). Yost, SDI and CDI will follow the same template.

ReproducibleSDOH is the umbrella R package for the ReproducibleX family:

- ReproducibleYostIndex
- ReproducibleNDI (Messer, Powell-Wiley, ICE)
- ReproducibleSDI
- ReproducibleCDI

It gives users two ways to get an index:

- **Fast path:** `get*()` functions download **pre-computed** results. No Census API key is needed.
- **Compute path:** `computeSDOH()` hands off to the sibling package's `compute*()`, for options the pre-computed files don't cover.

The pre-computed data is produced on **Stanford Sherlock** by a SLURM pipeline. It is published as GitHub Release assets in a separate data-only repository.

---

## 1. Decisions

| # | Decision | Choice |
|---|---|---|
| D1 | Repositories | **Two:** `ReproducibleSDOH` holds the package and the Sherlock pipeline (the pipeline is excluded from the package build). `ReproducibleSDOH-data` holds data only. |
| D2 | Releases | **One independent release series per index.** Each release is self-contained for its index. A `manifest.json` on the data repo's `main` branch records the latest tag per index. |
| D3 | Geography releases | **Two shared release series, independent of any index**, published once per run and reused by every index: **`geoinfo-`** (`GEOID`, `NAME`, `tot_pop`) and **`geometry-`** (`GEOID` + boundaries). |
| D4 | Versions published | **Two per index: raw** (no stabilization, no imputation) and **best** (every option on). No `scope = "county"`. |
| D5 | Dependencies | Sibling packages go in **`Suggests` only**, so the base install stays light. |
| D6 | Storage format | **Parquet** (`.parquet`). CSV is produced on request by `sdoh_export_csv()` and is not published in releases. |
| D7 | Geometry format | Parquet with a **WKB geometry column**, which either reader (`arrow` or `nanoparquet`) plus `sf` can turn into boundaries. Not GeoParquet, which needs GDAL built with Parquet support or the `arrow` + `geoarrow` packages. |
| D8 | Readers | **Pending (O8):** `arrow` vs `nanoparquet` as the package's reader. The pipeline writes with `arrow` either way. The docs cover **R and Python** only. |
| D9 | Census download reuse | **No changes to the sibling packages.** The pipeline caches `tidycensus::get_acs()` results on disk, for the pipeline session only (§5.4). |
| D10 | File size | **One Parquet file per pipeline task**: one index × geo × scope × year. |
| D11 | Groupings | **Store index scores only.** No quintile, quartile or percentile columns: `YostQuintile`, `NDIQuartile`, `our_SDI` and `our_CDI` are dropped. Groupings are calculated after download by the package's grouping functions (§4.4). Population-weighted groupings use `tot_pop` from the `geoinfo` release (D13). |
| D12 | Sibling packages | Once the grouping functions match every package's current output (§7, Phase 6), the grouping columns are **deprecated and then removed** from the sibling packages' `compute*()` outputs. |
| D13 | `geoinfo` release | **A dedicated release holds one small table per (geo × year): `geoinfo_{geo}_{year}.parquet` with `GEOID`, `NAME` and `tot_pop`.** Index files then hold **only `GEOID` and the index scores**. Every index joins `geoinfo` on `GEOID`; `get*()` does it by default (`info = TRUE`), so users see name, population and index side by side without downloading boundaries. |
| D14 | Code repo visibility | `HanLabCollaboration/ReproducibleSDOH` is **public**, so Sherlock can use a plain `git clone`. |

Why D11:

- **Groupings are derived from the score.** Storing them duplicates information and lets the two drift apart.
- **Groupings are a user choice:** the number of groups, whether to weight by population, and the reference set (national or within state).
- **Consistency across indices.** Today each index uses a different grouping.

File size is a minor reason. Measured on `yost_block_group_state_2022` (239,781 rows), the quintile columns are only ~4% of a Parquet file. The main size saving comes from publishing two versions instead of four: 8.33 MB → 4.00 MB.

### "Best" version per index

| Index | Raw column | Best column | Calls per task |
|---|---|---|---|
| Yost | `Yost` | `YostStabilizedImputed` | **1**: `stabilize = TRUE, impute = TRUE` also returns the baseline in `df_yost_raw` |
| NDI Messer | `NDI` | `NDIImputed` | **1**: `impute = TRUE` also returns `df_ndi_raw` |
| NDI Powell-Wiley | `NDI` | `NDIImputed` | **1** (same as Messer) |
| ICE | `ICE_inc`, `ICE_edu`, `ICE_rewb`, `ICE_wbinc`, `ICE_wpcinc` | same five names + `Imputed` suffix | **1**: `impute = TRUE` also returns `df_ice_raw` |
| SDI | `SDI` (z-score rescaling) | `SDIImputed` (z-score rescaling, imputed) | **2**: raw and best are separate calls |
| CDI | `CDI_std` (mean 100 / SD 20) | `CDI_stdImputed` | **2**: raw and best are separate calls |

Index files contain **only `GEOID` and these score columns** (§3.3). `NAME` and `tot_pop` come from the `geoinfo` release (D13); `year`, `geo` and `scope` are in the file name, the file metadata and the manifest, and `get*()` adds them as columns when reading.

Why D13:

- **It's what a user wants to see:** name, population and index in one table, from `get*()` with no extra steps.
- **Stored once:** otherwise the same name and population for a (geo × year) would be repeated in up to 12 index files (6 series × 2 scopes).
- **One population definition for all indices.** The packages take total population from different ACS tables (`B01003_001` for Yost, Messer, SDI and CDI; `B01001_001` for Powell-Wiley; `B03002_001` for ICE). All are the ACS total-population estimate and are expected to be identical; the pilot verifies it (§5.6 step 4c).
- **Index files stay minimal:** `GEOID` and the index. That makes them as small and fast to download as possible.
- **Its own release:** `geoinfo` depends only on geo and year, so it's released on its own schedule. A user can call `getGeoInfo()` without any index, and every index release records which `geoinfo` release it matches.
- **ICE doesn't return `NAME`**, so it would have needed a join anyway.

---

## 2. Repository layouts

### 2.1 `HanLabCollaboration/ReproducibleSDOH` (package + pipeline)

```
ReproducibleSDOH/
├── DESCRIPTION               Imports: <reader, see O8>, httr2, jsonlite, rlang, tools
│                             Suggests: sf, arrow, ReproducibleYostIndex, ReproducibleNDI,
│                                       ReproducibleSDI, ReproducibleCDI, testthat, withr
│                             Remotes: HanLabCollaboration/ReproducibleYostIndex, … (x4)
├── NAMESPACE
├── R/
│   ├── getYost.R  getNDI.R  getICE.R  getSDI.R  getCDI.R    thin exported wrappers
│   ├── get_engine.R          shared engine behind every get*() (§4.2)
│   ├── manifest.R            sdoh_manifest(), sdoh_releases()
│   ├── download.R            download + sha256 check + local cache
│   ├── cache.R               sdoh_cache_dir(), sdoh_cache_clear()
│   ├── geometry.R            WKB → sf, join onto scores
│   ├── export.R              sdoh_export_csv()
│   ├── open.R                sdoh_open()  (arrow, optional)
│   ├── computeSDOH.R         hand-off to sibling compute*() functions
│   └── ReproducibleSDOH-package.R
├── inst/
│   ├── CITATION
│   └── diagrams/             ReproducibleYostIndex/NDI/SDI/CDI.html (the current files in this folder)
├── tests/testthat/           fixture Parquet files + a local test manifest (no network)
├── pipeline/                 ← in .Rbuildignore; never part of the installed package
│   └── (see §5)
├── README.Rmd / README.md
├── CLAUDE.md                 "This code will be reviewed by codex."
├── .gitignore                ignores pipeline outputs, rendered plans, secrets
└── plan/
    ├── plan.md               this file (shared design)
    └── plan_<FAMILY>.md      one plan per index family, e.g. plan_NDI.md
```

### 2.2 `HanLabCollaboration/ReproducibleSDOH-data` (data only)

```
ReproducibleSDOH-data/
├── README.md        what's published, file naming, how to read the files in R and Python
├── SCHEMA.md        columns and types per index, with schema version history
├── manifest.json    releases, files, sizes, sha256 checksums; "latest" per index
├── LICENSE          data license (to decide, e.g. CC BY 4.0)
└── Releases (assets only):
    geoinfo-v2026.10   geometry-v2026.10          ← shared by every index
    yost-v2026.10      ndi-v2026.10      ice-v2026.10
    sdi-v2026.10       cdi-v2026.10
```

Assumptions (confirm):

- The **`ndi-` release holds both Messer and Powell-Wiley** files, since they come from one package.
- **ICE gets its own `ice-` release**, since it is a separate index.

### 2.3 The existing Yost data repo

`ReproducibleYostIndex-data` stays frozen as it is, so `ReproducibleYostIndex::getYostIndex()` keeps working. Its README will get a note pointing to `ReproducibleSDOH-data`.

---

## 3. Data specification

### 3.1 File naming

| Kind | Pattern | Example |
|---|---|---|
| Index scores | `{index}_{geo}_{scope}_{year}.parquet` | `yost_tract_state_2022.parquet` |
| NDI | `ndi_{type}_{geo}_{scope}_{year}.parquet` | `ndi_powellwiley_county_national_2019.parquet` |
| ICE (no scope) | `ice_{geo}_{year}.parquet` | `ice_block_group_2021.parquet` |
| Geography info (`geoinfo-` release) | `geoinfo_{geo}_{year}.parquet` | `geoinfo_tract_2020.parquet` |
| Boundaries (`geometry-` release) | `geometry_{geo}_{year}.parquet` | `geometry_tract_2020.parquet` |

In file names, `geo` is `county`, `tract` or `block_group` (underscore), and `scope` is `national` or `state`.

### 3.2 Coverage (≈ 430 pipeline tasks)

| Index | Geos | Scopes | Years | Tasks |
|---|---|---|---|---|
| Yost | county, tract, block group | national, state | 2011–2024 (block group 2013+) | 80 |
| NDI Messer | county, tract, block group | national, state | same | 80 |
| NDI Powell-Wiley | county, tract | national, state | 2011–2024 | 56 |
| ICE | county, tract, block group | — | 2011–2024 (block group 2013+) | 40 |
| SDI | county, tract, block group | national, state | same | 80 |
| CDI | county, tract, block group | national, state | 2016–2024 | 54 |
| Geoinfo + geometry (one task writes both) | county, tract, block group | — | 2011–2024 (block group 2013+) | 40 |

`YEAR_MAX` is a single setting (§5.1). Adding a year only requires raising it and cutting new releases.

### 3.3 Columns

| File | Columns |
|---|---|
| **Index** (`yost_…`, `ndi_…`, `ice_…`, `sdi_…`, `cdi_…`) | `GEOID` (string), the raw score column(s), the best score column(s) (`double`). **Nothing else.** |
| **`geoinfo_{geo}_{year}`** | `GEOID` (string), `NAME` (string), `tot_pop` (int32; ACS 5-year `B01003_001` for that year) |
| **`geometry_{geo}_{year}`** | `GEOID` (string), `geometry` (WKB binary; CRS in the file metadata) |

Not stored in index files:

- `NAME` and `tot_pop` → `geoinfo` release (D13).
- `year`, `geo` and `scope` → the file name, the file metadata (§3.4) and the manifest. `get*()` adds them as columns when reading.
- Groupings (quintiles, quartiles, percentiles) → computed by the package (D11).
- The packages' `annotation` column (why a score is missing) → see O13.

`geoinfo` also defines the **expected set of `GEOID`s** for each (geo × year). QA checks every index file and every geometry file against it. It is a few MB at most.

### 3.4 Metadata stored in each Parquet file

Written as key–value metadata, so every file can explain where it came from:

`schema_version`, `index`, `geo`, `scope`, `acs_year`, `acs_survey = acs5`, `release_tag`, `geoinfo_release`, `package`, `package_version`, `package_git_sha`, `r_version`, `tidycensus_version`, `fetched_at` (UTC), `pipeline_git_sha`.

### 3.5 `manifest.json` (on the data repo's `main` branch)

```json
{
  "manifest_version": 1,
  "base_url": "https://github.com/HanLabCollaboration/ReproducibleSDOH-data/releases/download",
  "latest": { "geoinfo": "geoinfo-v2026.10", "geometry": "geometry-v2026.10",
              "yost": "yost-v2026.10", "ndi": "ndi-v2026.10" },
  "releases": {
    "yost-v2026.10": {
      "index": "yost", "schema_version": 1, "published": "2026-10-15",
      "package": "ReproducibleYostIndex", "package_git_sha": "abc123…",
      "geoinfo_release": "geoinfo-v2026.10", "geometry_release": "geometry-v2026.10",
      "files": [
        { "name": "yost_tract_state_2022.parquet", "bytes": 3145728, "sha256": "…",
          "geo": "tract", "scope": "state", "year": 2022, "rows": 85396 }
      ]
    }
  }
}
```

- It is fetched from `raw.githubusercontent.com`, so it isn't subject to GitHub API rate limits.
- Each index release names the `geoinfo` and `geometry` releases it was built against, so `get*()` always joins the matching names, population and boundaries.
- Old releases stay listed forever, so `release = "yost-v2026.10"` keeps working for reproducing a paper.

---

## 4. The R package

### 4.1 Exported functions

```r
getYost(geo = "tract", year = 2022, scope = "national", version = c("both", "raw", "best"),
        states = NULL, groups = NULL, info = TRUE, geometry = FALSE,
        release = "latest", cache = TRUE, quiet = FALSE)
getNDI(type = c("messer", "powell_wiley"), geo, year, scope, version, states, groups, info, geometry, release, cache, quiet)
getICE(geo, year, version, states, groups, info, geometry, release, cache, quiet)          # no scope
getSDI(geo, year, scope, version, states, groups, info, geometry, release, cache, quiet)
getCDI(geo, year, scope, version, states, groups, info, geometry, release, cache, quiet)

getGeoInfo(geo, year, states = NULL, release = "latest")   # GEOID, NAME, tot_pop — no index needed

# Grouping functions (§4.4) — work on get*() output or on sibling compute*() output
addQuintiles(data, cols = NULL, by = NULL, weight = NULL, method = "ntile")
addQuartiles(data, cols = NULL, by = NULL, weight = NULL, method = "ntile")
addPercentiles(data, cols = NULL, by = NULL, weight = NULL, method = "ntile")
addGroups(data, n, cols = NULL, by = NULL, weight = NULL,
          method = c("ntile", "quantile_breaks"), suffix = NULL)
addIndexGroups(data)       # applies each index's original convention (table in §4.4)

sdoh_releases(index = NULL)         # list of published releases (tag, date, schema, file count)
sdoh_export_csv(index, ..., path, gzip = FALSE, release = "latest")    # Parquet → CSV
sdoh_open(index, release = "latest")                                   # arrow Dataset over cached files
sdoh_cache_dir();  sdoh_cache_clear(index = NULL, release = NULL)
sdoh_citation(index, release = "latest")

computeSDOH(index = c("yost", "ndi", "ice", "sdi", "cdi"), ...)   # passes ... to the sibling compute*()
```

Naming note: the wrapper is `getYost()` rather than `getYostIndex()`. With the same name, one package's function would hide the other's when both packages are loaded.

### 4.2 What each R file does

- **`get_engine.R`**: `sdoh_get(index, type, geo, year, scope, version, states, geometry, release, cache, quiet)`, the one engine behind every `get*()`.
  1. Checks the arguments against the manifest's coverage, e.g. rejects block group before 2013 or Powell-Wiley at block group.
  2. Resolves `release = "latest"` to a real tag through the manifest.
  3. Builds the file name (§3.1) and downloads it through `download.R`.
  4. Reads it with the chosen Parquet reader (O8), keeps the columns for `version`, and adds `year`, `geo` and `scope` columns.
  5. If `info = TRUE` (default), or if `groups` needs population weights, joins `NAME` and `tot_pop` from `geoinfo_{geo}_{year}.parquet`, in the `geoinfo` release named by the index release. That file is cached once and shared by every index for that geo and year.
  6. **If `groups` is set** (e.g. `groups = 5`, or `"index"` for each index's original convention), computes the groups through `groups.R` **before** filtering by state. That way a national quintile stays national even when you only ask for California.
  7. Filters to `states` using the state FIPS code at the start of `GEOID`.
  8. If `geometry = TRUE`, attaches boundaries from the `geometry` release via `geometry.R`.
  9. Attaches attributes `sdoh_index`, `sdoh_scope`, `sdoh_release` and `sdoh_filtered` (TRUE if `states` was used). The grouping functions use these to choose their defaults and to warn.
  10. Returns a tibble (or an `sf` object), sorted by `GEOID`, with columns in this order: `GEOID`, `NAME`, `year`, `geo`, `scope`, `tot_pop`, scores, groups.
- **`getYost.R` … `getCDI.R`**: thin exported wrappers. They carry the documentation and index-specific defaults (e.g. `getICE()` has no `scope`), then call the engine.
- **`manifest.R`**:
  - `sdoh_manifest()` downloads `manifest.json` and caches it for the session. Offline, it falls back to the last copy on disk, with a message.
  - `sdoh_releases()` turns the manifest into a tidy table.
- **`download.R`**:
  - Downloads to `sdoh_cache_dir()/<release_tag>/<file>` via a temporary file, then renames it, so an interrupted download never leaves a broken file.
  - Checks the **sha256 against the manifest** and re-downloads once on a mismatch.
  - Respects `cache = FALSE`.
- **`cache.R`**: finds the cache folder with `tools::R_user_dir("ReproducibleSDOH", "cache")`, and deletes it by index or release.
- **`geometry.R`**: reads a geometry Parquet file, turns the WKB column into `sf` with `sf::st_as_sfc(structure(x, class = "WKB"), crs = …)`, and joins it to the scores on `GEOID`. If `sf` is missing, `rlang::check_installed("sf")` stops with install instructions.
- **`export.R`**: `sdoh_export_csv()` fetches the file(s) through the engine and writes CSV (optionally `.csv.gz`) with `GEOID` always quoted. It accepts vectors of years or geos and writes one CSV per combination or a single combined file.
- **`open.R`**: `sdoh_open()` makes sure the requested files are cached, then returns `arrow::open_dataset()` over them, for dplyr queries across years. `arrow` is checked with `rlang::check_installed()`.
- **`groups.R`**: the grouping functions (§4.4). Also a small internal weighted-quantile helper, which reproduces `statar::xtile(x, n, wt)` without depending on `statar`.
- **`computeSDOH.R`**: maps `index` to `ReproducibleYostIndex::computeYostIndex`, `ReproducibleNDI::computeNDI` / `computeICE`, `ReproducibleSDI::computeSDI` or `ReproducibleCDI::computeCDI`. It checks the package is installed (with a `remotes::install_github()` hint) and passes `...` through unchanged.

### 4.3 Tests

- **No network in tests.** They use small fixture Parquet files and a local `manifest.json`, pointed to with `options(ReproducibleSDOH.manifest_url = "file://…")`.
- **What they cover:**
  - resolving "latest" to a tag
  - the checksum-mismatch path
  - filtering by state (FIPS codes with leading zeros)
  - selecting `version`
  - rebuilding geometry from WKB
  - CSV export keeping `GEOID` as text
  - `computeSDOH()` erroring cleanly when a sibling package is missing
  - **grouping matches the packages exactly.** Fixtures hold scores next to the groups the sibling packages produced, and the tests require an identical match for every convention in §4.4.
  - the weighted-quantile helper matches `statar::xtile()`, which is in `Suggests` for this test only
  - groups are computed within each state when `scope = "state"`
  - a warning when grouping data that was filtered to a subset of states under national scope

### 4.4 Grouping functions (replace the stored quintiles/quartiles)

**Core function:** `addGroups(data, n, cols, by, weight, method)` adds one integer group column per score column, e.g. `Yost` → `Yost_q5`.

- **`cols`:** defaults to every score column that `get*()` returned (raw and best).
- **`by`:** defaults to the scope stored with the data.
  - `"national"`: one group over all rows.
  - `"state"`: grouped within each state (the first 2 digits of `GEOID`), exactly as the packages do today.
- **`weight`:** `NULL` (unweighted) or a column name such as `"tot_pop"` (population-weighted cut points). If `tot_pop` isn't in the data (`info = FALSE`), the function stops and says to call `getGeoInfo()` or use `info = TRUE`.
- **`method`:**
  - `"ntile"`: equal-count groups, like `dplyr::ntile()`.
  - `"quantile_breaks"`: cut at the quantiles, like `cut(x, quantile(x, 0:n/n), include.lowest = TRUE)`. If the cut points are degenerate, it falls back to `"ntile"`, as Messer does today.
- **Missing scores:** NA or zero-population scores get an NA group.

`addQuintiles()`, `addQuartiles()` and `addPercentiles()` are the same function with `n` = 5, 4 and 100.

**`addIndexGroups(data)`** reproduces each package's current convention exactly. This is what the match tests check against:

| Index | Group | Method | Weight | Matches today's |
|---|---|---|---|---|
| Yost | quintile (5) | `ntile` | none | `YostQuintile` |
| NDI Messer | quartile (4) | `quantile_breaks` (fallback `ntile`) | none | `NDIQuartile` |
| NDI Powell-Wiley | quintile (5) | `quantile_breaks` | `tot_pop` | *not in the package today*; restores `ndi::powell_wiley`'s population-weighted quintiles (method to verify against `ndi`) |
| ICE | none by default | — | — | — |
| SDI | percentile (100) | weighted `ntile` (`statar::xtile`) | `tot_pop` | `our_SDI` |
| CDI | percentile (100) | `ntile` | none | `our_CDI` |

**Rules that keep groups correct:**

1. **Group over the scope's full reference set.** A national quintile must be computed over the whole country; `get*(groups = …)` does this before filtering by state. If `addGroups()` is called on data whose `sdoh_filtered` attribute is TRUE under national scope, it warns that the groups are relative to the subset.
2. **Ties.** `ntile` breaks ties by row order. Files are sorted by `GEOID`, while the packages keep the Census download order, so rare exact ties can land in different groups. The match check (§5.6 step 4b) counts this. It is expected to be zero or near zero for continuous scores.
3. **The same functions work on `compute*()` output,** so the download path and the compute path give identical groups.

---

## 5. The pipeline (`pipeline/`, runs on Sherlock)

```
pipeline/
├── README.md             step-by-step runbook for cutting a release
├── config.R              all settings in one place
├── registry.R            one entry per index: how to compute it and what to write
├── census_cache.R        disk cache for tidycensus::get_acs() (pipeline only)
├── make_grid.R           registry → task lists (one per memory tier)
├── setup_env.sh          one-time environment setup on Sherlock
├── run_task.R            runs ONE index task (called by SLURM)
├── build_geometry.R      runs ONE geometry task (geo × year)
├── submit.sh             submits a task list as a SLURM array
├── check_status.R        what's done / failed / missing; prints re-submit commands
├── qa_release.R          validates a finished release; writes a QA report
├── publish.R             checksums, release notes, gh release, manifest update
├── archive.sh            copies outputs + logs to Box/Oak (adapted from data_transfer.sh)
├── templates/release_notes.md
└── renv.lock             exact R package versions used for the run
```

Output layout on Sherlock (`$SCRATCH/sdoh/<run_id>/`):

```
<run_id>/
├── grids/        tasks_<tier>.csv
├── out/<index>/  final .parquet files (what gets published)
├── done/<index>/ one JSON per finished task
├── census_cache/ cached get_acs() results
├── logs/         SLURM .out/.err
└── qa/           QA report + checks
```

### 5.1 `config.R`

The single source of settings, sourced by every R script:

- `RUN_ID`, e.g. `2026-10`
- `YEAR_MIN = 2011`, `YEAR_MAX = 2024`
- `OUT_ROOT`
- `CENSUS_CACHE_DIR`
- `INDICES` to run, so one index can be run on its own
- the git refs (tags) of each sibling package to install
- the release tag pattern `"{index}-v{RUN_ID}"`
- memory/time per tier
- the SLURM concurrency cap (e.g. 20)

It reads `CENSUS_API_KEY` from the environment only. **No key or token is ever committed.**

### 5.2 `registry.R`

A named list with one entry per output series: `yost`, `ndi_messer`, `ndi_powellwiley`, `ice`, `sdi`, `cdi`. Each entry defines:

- **`package` and `fun`**: e.g. `ReproducibleNDI` / `computeNDI`.
- **`coverage`**: geos, scopes (or `NULL` for ICE), year range per geo.
- **`calls`**: the argument lists to run.
  - Yost: `list(best = list(stabilize = TRUE, impute = TRUE, return_format = "detailed"))`.
  - SDI: `list(raw = list(impute = FALSE), best = list(impute = TRUE))`.
- **`extract(results)`**: turns the returned object(s) into the index file of §3.3: **`GEOID` + score columns only**.
  - Yost/NDI/ICE take the raw columns from `df_*_raw` and the best columns from `df_*`.
  - SDI/CDI join the separate raw and best calls on `GEOID`.
  - `NAME`, `tot_pop` and `annotation` are **not written**. They're kept in memory for the checks in §5.6 (population 4c, NA consistency 4d).
  - The packages' grouping columns (`YostQuintile`, `NDIQuartile`, `our_SDI`, `our_CDI`) are **not written**. They are kept in memory only for the match check (§5.6 step 4b).
- **`groups_ref`**: names the package's grouping columns and the matching `addIndexGroups()` convention (§4.4), e.g. Yost → `YostQuintile` ↔ quintile / `ntile` / unweighted.
- **`schema`**: expected column names and types, checked before writing.
- **`file_name(geo, scope, year)`**: follows §3.1.
- **`checks`**: index-specific QA rules, used by `qa_release.R`:
  - ICE values in [−1, 1]
  - CDI_std roughly centred on 100 with SD near 20 within each scope group
  - scores are NA exactly where the package's in-memory `annotation` says they should be (§5.6 step 4d)

Adding an index later means adding one entry here and nothing else.

### 5.3 `make_grid.R`

- Expands the registry's coverage into one row per task: `task_id, index, geo, scope, year, tier`. It adds the 40 geometry tasks as `index = "geometry"`.
- Assigns a **memory tier**, set per series and geo in `registry.R` (see the family plans), e.g. `standard` 16 GB, `medium` 48 GB, `high` 128 GB.
- **Why tiers:** a SLURM array can't vary memory per task, so each tier gets its own list (`tasks_standard.csv`, `tasks_medium.csv`, `tasks_high.csv`) and its own `sbatch`.
- **Ordering:** national tasks come before state tasks. They make identical Census calls, so the second reuses the first's cache (§5.4).
- Prints a summary of task counts by index and tier.

### 5.4 `census_cache.R`

This is how Census downloads get reused **without changing any sibling package**.

- **How it plugs in.** All sibling packages call `do.call(tidycensus::get_acs, fetch_args)`. In the pipeline's R session only, this script swaps that function for a caching version with `assignInNamespace("get_acs", cached_get_acs, "tidycensus")`. Users of the packages never see it.
- **The cache key** is a hash of the call arguments, excluding `geometry`.
  - A result downloaded with geometry is also served to later calls that don't ask for geometry, with the geometry dropped.
  - A no-geometry result is never served to a call that needs geometry.
  - This matters for SDI and CDI, whose raw call fetches without geometry and whose best call (imputation) fetches with it. The runner does the **best call first**.
- **Writing safely:** each result is saved to a temporary file and then renamed, and a lock file (`filelock` package) stops two jobs from writing the same result at once.
- **Retries:** a Census download that fails is retried up to 5 times, waiting a little longer each time (e.g. 10 s, 20 s, 40 s, …). This covers throttling and server errors.
- **Logging:** each cache hit or miss is recorded, and the counts go into the task's `done` JSON.
- **Expected savings:**
  1. SDI/CDI raw + best: 2 downloads → 1.
  2. National and state scope for the same index, geo and year: 2 → 1.
  3. **Yost stabilization at state scope.** `processYostScope()` re-downloads the parent geography for *all* states once per state group, so about 51 identical calls per task; the cache makes that 1.
- **Also set** `options(tigris_use_cache = TRUE)` so boundary shapefiles are cached as well.
- **It's pipeline-only and throwaway.** The cache is deleted after each run (in `archive.sh`), so a new release always downloads fresh ACS data.

### 5.5 `setup_env.sh`

Run once, on a Sherlock login node, before submitting anything:

- Loads the R module and system libraries (GDAL/GEOS/PROJ for `sf` and `spdep`).
- Restores packages from `renv.lock`.
- Installs each sibling package at the **tagged version** from `config.R` (`remotes::install_github("…@v0.x.y")`).
- Checks that `CENSUS_API_KEY` is set and makes one test Census call.
- Records every package's git SHA in `<run_id>/provenance.json`.

### 5.6 `run_task.R`

The SLURM worker. It handles one index task, identified by `SLURM_ARRAY_TASK_ID` and a `--grid` file.

1. Reads its row from the grid and sources `config.R`, `registry.R` and `census_cache.R`.
2. **Skips itself** if the output file and its `done` JSON both exist and are valid. Re-running an array is therefore always safe.
3. Runs the registry `calls` in order (best first). Each call is timed, with `quiet = TRUE`, `states = "all"` and `keep_geometry = FALSE` where the function allows it. Geometry comes from the geometry release instead.
4. Builds the index table with `extract()` and **validates it against the schema**: columns, types, a unique `GEOID`, and a non-zero row count. `year`, `geo` and `scope` go into the file metadata, not columns.

   4b. **Grouping match check.** It runs `addIndexGroups()` from this repo's package on the extracted scores, grouped the same way as the task's scope, and compares the result row by row with the grouping columns that `compute*()` just returned. The number of mismatches per column goes into the `done` JSON. This validates the grouping functions on every task of the full grid, at no extra cost, before the packages' grouping columns are removed (D12). The pipeline loads the package with `pkgload::load_all()` from the repo checkout.

   4c. **Population check.** Compares the package's own `tot_pop` with `tot_pop` in `geoinfo` for the same (geo × year), which is built first. The number of differing `GEOID`s goes into the `done` JSON. Expected: 0 for every index. If an index's population table differs, D13 needs revisiting for that index.

   4d. **NA consistency check.** Uses the package's in-memory `annotation`: every NA score must have a reason (`No population`, `PCA failed`/`Factor analysis failed`, or `Imputation incomplete`), and every non-NA score must be `Complete data` or `Imputation completed`. The counts per annotation go into the `done` JSON.

5. Writes the Parquet file with the §3.4 metadata. It writes to a temporary file and renames it, so a half-written file never exists.
6. Writes `done/<index>/<file>.json`: task parameters, row count, NA counts per column, time per call, cache hits and misses, package versions and peak memory.
7. On error, writes `done/<index>/<file>.error.json` with the message and call stack, and exits with a non-zero status so SLURM marks the task failed.

### 5.7 `build_geometry.R` (writes both `geoinfo` and `geometry`)

A SLURM worker for one (geo × year) geometry task.

- **Downloads the boundaries** with `tidycensus::get_acs(variables = "B01003_001", geography = geo, year, state = <all>, geometry = TRUE)`.
  - This is the same source and boundary type the sibling packages use, so every `GEOID` matches.
- **Writes two files from that one download**, published in two releases:
  - `geoinfo_{geo}_{year}.parquet` → `geoinfo-` release: `GEOID`, `NAME` and `tot_pop` (D13). `tot_pop` is the `B01003_001` estimate that this same download already fetches, so it costs no extra Census call.
  - `geometry_{geo}_{year}.parquet` → `geometry-` release: `GEOID` and the WKB geometry, with the CRS in the file metadata.
- **Handles 2011–2012 tract files separately.** They use full-detail TIGER boundaries and come out at ~650 MB. Whether to simplify them is open decision O4.
- Writes a `done` JSON, as `run_task.R` does.

### 5.8 `submit.sh`

Wraps `sbatch`:

```bash
bash submit.sh --grid grids/tasks_standard.csv --tier standard   # → --array=1-N%20 --mem=16G
bash submit.sh --grid grids/tasks_high.csv     --tier high       # → --array=1-M%5  --mem=128G
bash submit.sh --grid … --ids 12,40,77                           # re-run specific tasks
```

It:

- sets the job name, time, partitions (`normal,qsu,owners`), log paths and failure emails;
- exports `RUN_ID` and the grid path;
- calls `Rscript run_task.R` or `Rscript build_geometry.R`, depending on the grid's index.

There is **no API key in this script**. It comes from `~/.Renviron` or the environment.

### 5.9 `check_status.R`

Compares the grids with `out/` and `done/`, then prints:

- a table of done, failed and missing tasks by index and tier;
- the first error line of each failure;
- ready-to-paste `submit.sh --ids …` commands to re-run what's left.

Run it any time while jobs are running and after they finish.

### 5.10 `qa_release.R`

Validates one index, or all of them, before publishing, and writes `qa/<index>_qa.md` plus a pass/fail exit code.

1. **Complete:** every expected file from the grid exists.
2. **Row counts:** each file's `GEOID`s are exactly the set in the matching `geoinfo` table.
3. **Schema:** columns, types and file metadata match the registry.
4. **Value ranges:** registry `checks`, e.g. ICE in [−1, 1]. For `geoinfo`: `tot_pop` ≥ 0, `NAME` never empty, `GEOID` unique.

   4b. **Grouping match summary:** collects the step 4b results from every `done` JSON. It passes only if every index has zero mismatches, or only mismatches explained by tied scores (§4.4, rule 2).

   4c. **Population summary:** collects the step 4c results. It passes only with 0 differences for every index.

   4d. **NA consistency summary:** collects the step 4d results. It passes only if no score is NA without a reason.

5. **Missing values:** NA rate per column and year. Anything above a threshold is flagged, e.g. imputed columns should have fewer NAs than raw.
6. **Consistency:**
   - For each file, the correlation between raw and best. It should be high; a sign flip or a near-zero value is flagged.
   - Across neighbouring years, the correlation of the same geographies' scores.
7. **Comparison with the previous release** (from the manifest): which `GEOID`s changed, and the mean absolute difference per column.
8. **Regression test against published Yost:** the new raw `Yost` should equal `Yost` in `ReproducibleYostIndex-data` release `data-v2026.05`, where the package version is the same. Also, `addQuintiles()` applied to the new raw `Yost` should reproduce that release's stored `YostQuintile`.
9. **Spot check without the cache:** re-computes 2–3 random tasks with the Census cache turned off and confirms the output is identical. This proves the cache didn't change any results.

### 5.11 `publish.R`

Run from a Sherlock login or data-transfer node, with `gh` authenticated. It has a `--dry-run` mode.

1. Refuses to run unless `qa_release.R` passed for that index.
2. Computes the sha256 checksum of every file.
3. Renders the release notes from `templates/release_notes.md`: coverage, schema version, package versions and SHAs, fetch dates, QA summary, and changes since the previous release.
4. Runs `gh release create {index}-v{RUN_ID} --repo HanLabCollaboration/ReproducibleSDOH-data` and uploads the files, retrying any file that fails.
5. Updates `manifest.json`: adds the release, sets `latest[index]` to it, and records `geometry_release`. Then it commits and pushes to the data repo's `main` branch.
6. The **`geoinfo` and `geometry` releases are published first**, because index releases point to them and QA checks against `geoinfo`.

### 5.12 `archive.sh`

Adapted from `ReproducibleYostIndex/batch/data_transfer.sh`, it copies the run to Box (e.g. `box:/…/ReproducibleSDOH/<run_id>/`) with `rclone copy`:

- `out/`, `done/`, `qa/`, `logs/`, `grids/`
- `provenance.json`

It skips `census_cache/`, then deletes that cache. Run it before Sherlock's `$SCRATCH` purge (90 days without access).

---

## 6. Release workflow (runbook summary)

1. **Tag the sibling packages** to be used, then set their tags and `RUN_ID` in `config.R`.
2. `bash setup_env.sh`
3. `Rscript make_grid.R`
4. **Geoinfo and geometry first:** `submit.sh` on the geometry tasks → `check_status.R` → `qa_release.R geoinfo` / `geometry` → `publish.R geoinfo` / `geometry`.
5. **Index tasks:** submit the `standard` and `high` tiers → `check_status.R` → re-submit failures until everything is done.
6. **For each index:** `qa_release.R <index>` → review the report → `publish.R <index>`. Indices can be published independently.
7. `bash archive.sh`
8. **In the package repo:**
   - update the test fixtures if the schema changed;
   - run the `get*()` functions against the new releases;
   - tag a package release if anything changed.

**Cadence:** once a year, after the Census publishes the new ACS 5-year estimates (usually December), plus whenever a package method fix changes results.

---

## 7. Milestones

| Phase | Work | Done when |
|---|---|---|
| 0. Prerequisites | Resolve the SDI concerns (§8, R6). Tag the four sibling packages. Pick a data license. | Tags exist; decision recorded |
| 1. Scaffold | Create both GitHub repos. Package skeleton. `SCHEMA.md` v1. Manifest spec. Move the HTML diagrams to `inst/diagrams/`. | `R CMD check` passes on the empty package |
| 2a. Grouping functions | `groups.R`: `addGroups()`, the wrappers, `addIndexGroups()`, the weighted-quantile helper, tests against fixtures from each sibling package | Tests match `YostQuintile`, `NDIQuartile`, `our_SDI` and `our_CDI` exactly on local fixtures |
| 2b. Pipeline core | `config.R`, `registry.R`, `census_cache.R`, `make_grid.R`, `run_task.R` (with the step 4b match check), `submit.sh`, `check_status.R` | Pilot run succeeds |
| 3. Pilot | Every index at **county, 2 years (2019, 2022), both scopes**, on Sherlock | Output identical with and without the cache; zero grouping mismatches; files load in R and Python |
| 4. Geoinfo + geometry | `build_geometry.R`, then publish `geoinfo-v…` and `geometry-v…` | QA passes; `getGeoInfo()` works; the geometry files turn into `sf` objects correctly |
| 5. Full runs + QA | Full grid; `qa_release.R`; the Yost regression check against `data-v2026.05` (scores and quintiles) | Every index passes QA, including the grouping match summary |
| 6. Publish | `publish.R` for each index; manifest updated | `getYost()` … `getCDI()` work against live releases |
| 7. Package release | `get*()` (with `groups =`), the grouping functions, `sdoh_export_csv()`, `sdoh_open()`, `computeSDOH()`, docs, README, tests | `R CMD check` clean; README examples run |
| 8. Hand-off | Note in the `ReproducibleYostIndex-data` README pointing to the new repo | — |
| 9. Remove groupings from sibling packages (D12) | 1. **Deprecate:** one release of each sibling package in which the grouping columns still appear but emit a `lifecycle` deprecation message pointing to `ReproducibleSDOH::addIndexGroups()`. 2. **Remove:** the next release drops the columns and the grouping code (`YostQuintile`, `NDIQuartile`, `our_SDI`, `our_CDI`), and updates the READMEs and pipeline diagrams. 3. **Pipeline:** remove the step 4b match check and `groups_ref` from the registry. | Every sibling package ships without grouping columns; `compute*()` output + `addIndexGroups()` equals the old output |

---

## 8. Risks and mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | Census API throttling or failures with hundreds of tasks at once | Concurrency cap (`%20`), retries (§5.4), the Census cache, national-before-state ordering, re-runs via `check_status.R` |
| R2 | Out-of-memory at block group (~220k polygons; `spdep::poly2nb` across the whole US) | `high` memory tier (64–128 GB) with lower concurrency; memory usage recorded per task in its `done` JSON |
| R3 | The cache changes results, e.g. through row order or geometry being dropped | QA spot check comparing against uncached runs (§5.10 step 9); outputs sorted by `GEOID` |
| R4 | `assignInNamespace()` stops working if a sibling package changes how it calls `get_acs()` | Pilot checks cache hits; `run_task.R` fails loudly if a task with Census calls records zero cache entries |
| R5 | `$SCRATCH` purge deletes outputs | `archive.sh` runs straight after publishing; the runbook says so |
| R6 | **A published release freezes bugs.** The SDI component centiles are computed across all requested states before the data is split by scope. The SDI score's sign isn't fixed, so its direction can differ by scope group. | Decide and fix before Phase 5; package git SHAs recorded in every release |
| R7 | Census revises ACS data, so re-runs don't reproduce old numbers | Old releases never change; `fetched_at` in each file; pinned `release =` tags |
| R8 | GitHub limits (2 GiB per file, API rate limits) | Per-task files are far below 2 GiB; the manifest comes from `raw.githubusercontent.com`; downloads are verified by checksum |
| R9 | Reading files straight from GitHub isn't reliable (downloads redirect to short-lived signed URLs) | Always download, cache, then read locally; no remote querying |
| R10 | Excel strips leading zeros from `GEOID` in exported CSVs | `GEOID` is always quoted; the docs warn about Excel |
| R11 | Schema changes break older package versions | `schema_version` in every file and in the manifest; the package refuses unknown major versions with a clear message |
| R13 | Groups computed over the wrong set of geographies, e.g. national quintiles computed after filtering to one state | `get*(groups = …)` groups before filtering; `addGroups()` groups by state under state scope and warns on filtered national data (§4.4) |
| R14 | Grouping functions don't exactly reproduce the packages (tied scores, row order, weighted-quantile details) | The step 4b match check on every task, fixture tests, and the Yost quintile regression test; the packages' groupings are removed only after all of these pass (Phase 9) |
| R15 | Users of the current packages rely on the grouping columns | Deprecation release first (Phase 9), with a message pointing to `addIndexGroups()`; the old `ReproducibleYostIndex-data` releases keep their quintiles |
| R12 | Credentials leak into the public repo | Keys come only from the environment; `.gitignore` covers `.Renviron`; no tokens in scripts (the commented `auth_token` line in `run_yost_batch.R` is not carried over) |

---

## 9. Open decisions

- **O1:** Should `ndi-` releases hold both Messer and Powell-Wiley (assumed), or should they be split?
- **O2:** Wrapper name: `getYost()` (proposed, avoids clashing with `ReproducibleYostIndex::getYostIndex()`) or `getYostIndex()`?
- **O3:** Data license for `ReproducibleSDOH-data`, e.g. CC BY 4.0.
- **O4:** Simplify the 2011–2012 tract geometry (~650 MB each) or publish it as-is?
- **O5:** Scores only (D11); `NAME` and `tot_pop` live in the `geoinfo` release (D13). Should the component variables also be published, perhaps later and in separate files? They would allow more analyses but make the files several times larger.
- **O6:** Fix the SDI concerns (R6) before the first release?
- **O7:** Mint a DOI per release (Zenodo upload), for citing in papers?
- **O8:** Package reader: **`arrow`** (in `Imports`: one code path with lazy dplyr queries, heavier install) or **`nanoparquet`** (in `Imports`, with `arrow` in `Suggests`: very light install; the data is loaded into memory before dplyr). The pipeline writes with `arrow` either way.
- ~~**O9:** `NAME` in score files?~~ **Decided (D13):** `NAME` and `tot_pop` live in the dedicated `geoinfo` release; index files hold only `GEOID` + scores.
- **O13:** The packages' `annotation` column explains *why* a score is missing (no population, PCA/factor analysis failed, imputation incomplete). It isn't stored under the "GEOID + index only" rule. Should it be kept as an optional small column, or left out (users can still see `tot_pop == 0` from `geoinfo`)? Parquet stores a column with few distinct values very compactly, so it would cost little.
- **O10:** Naming for the added group columns: `Yost_q5` / `NDI_q4` / `SDI_p100` (proposed), or the packages' current names (`YostQuintile`, `NDIQuartile`, `our_SDI`)? The current names would make migration seamless for existing users.
- **O11:** Should `addIndexGroups()` for **ICE** add national quintiles by default? Krieger's papers usually report them. Today the package adds none.
