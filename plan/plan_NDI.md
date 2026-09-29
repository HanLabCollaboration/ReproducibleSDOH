# ReproducibleSDOH — NDI family plan (Messer · Powell-Wiley · ICE)

_Drafted 2026-09-29. This plan builds on [`plan.md`](plan.md) and follows every decision there (D1–D14). It covers only what is specific to the NDI family, plus what has to exist before NDI can run on Sherlock._

**NDI is the first family to go through the pipeline.** Its run therefore also builds the shared pieces: the package skeleton, the pipeline core, and the **`geoinfo` and `geometry` releases**. The later families (Yost, SDI, CDI) reuse them unchanged.

---

## 0. Summary

| | |
|---|---|
| Source package | `HanLabCollaboration/ReproducibleNDI`, currently `0.0.0.9000` at commit **`06b5efb`** (pushed; **no tags yet**, see N1) |
| Output series | `ndi_messer`, `ndi_powellwiley`, `ice` |
| Releases produced | `ndi-v{RUN_ID}` (Messer + Powell-Wiley), `ice-v{RUN_ID}`, and the shared **`geoinfo-v{RUN_ID}`** and **`geometry-v{RUN_ID}`** |
| Tasks | 80 Messer + 56 Powell-Wiley + 40 ICE = **176**, plus **40** geography tasks (each writes one `geoinfo` and one `geometry` file) |
| Calls per task | **1**. With `impute = TRUE`, both `computeNDI()` and `computeICE()` return the raw baseline and the best version from one download |
| Pipeline diagram | `ReproducibleNDI.html` (to move to `inst/diagrams/`) |

---

## 1. What gets computed

### 1.1 The one call per task

| Series | Call (the pipeline adds `geo`, `year`, `scope`) |
|---|---|
| `ndi_messer` | `ReproducibleNDI::computeNDI(type = "messer", states = "all", impute = TRUE, weight_var = "tot_pop", keep_geometry = FALSE, return_format = "detailed", quiet = TRUE)` |
| `ndi_powellwiley` | `ReproducibleNDI::computeNDI(type = "powell_wiley", …same arguments…)` |
| `ice` | `ReproducibleNDI::computeICE(states = "all", impute = TRUE, keep_geometry = FALSE, return_format = "detailed", quiet = TRUE)`. There is no `scope`; imputation is unweighted (fixed inside `computeICE()`) |

`keep_geometry = FALSE` is overridden by `impute = TRUE`: both functions still download geometry to find neighbours for imputation. That's expected. The geometry is used in memory and not written, since boundaries come from the geometry release.

### 1.2 Coverage

| Series | Geos | Scopes | Years | Tasks |
|---|---|---|---|---|
| `ndi_messer` | county, tract, block group | national, state | 2011–2024 (block group 2013+) | 80 |
| `ndi_powellwiley` | county, tract (its DP/S tables stop at tract) | national, state | 2011–2024 | 56 |
| `ice` | county, tract, block group | — | 2011–2024 (block group 2013+) | 40 |
| `geoinfo` + `geometry` (shared) | county, tract, block group | — | 2011–2024 (block group 2013+) | 40 |

---

## 2. Output files and where each column comes from

### 2.1 `ndi_messer_{geo}_{scope}_{year}.parquet` and `ndi_powellwiley_{geo}_{scope}_{year}.parquet`

| Column | Type | Source in the `computeNDI()` result |
|---|---|---|
| `GEOID` | string | `df_ndi` |
| `NDI` | double | `df_ndi_raw$NDI` (raw: complete cases, no imputation) |
| `NDIImputed` | double | `df_ndi$NDIImputed` (best) |

That's the whole file (plan.md D13). `year`, `geo` and `scope` go into the file metadata.

**Kept in memory for checks, not written:**

| Value | Source | Used by |
|---|---|---|
| `NDIQuartile`, `NDIImputedQuartile` (Messer only) | `df_ndi_raw`, `df_ndi` | grouping match (§3.1) |
| `tot_pop` | `df_raw_values` (Messer `B01003_001`, Powell-Wiley `B01001_001`) | population check against `geoinfo` (§3.5) |
| `annotation` (raw and best) | `df_ndi_raw`, `df_ndi` | NA consistency (§3.4) |
| components (`POV`, `PctFamBelowPov`, …) | `df_components` | sign check (§3.2) |

### 2.2 `ice_{geo}_{year}.parquet`

| Column | Type | Source in the `computeICE()` result |
|---|---|---|
| `GEOID` | string | `df_ice` |
| `ICE_inc`, `ICE_edu`, `ICE_rewb`, `ICE_wbinc`, `ICE_wpcinc` | double | `df_ice_raw` (raw) |
| `ICE_incImputed` … `ICE_wpcincImputed` | double | `df_ice` (best), renamed with the `Imputed` suffix |

That's the whole file. `year` and `geo` go into the file metadata. **Kept in memory for checks, not written:** `tot_pop` (`df_raw_values`, from `B03002_001`) and `annotation` (`df_ice`; the raw ICE has none).

### 2.3 `geoinfo` and `geometry` releases (shared, built in this run)

One Census download per (geo × year), `B01003_001` with `geometry = TRUE`, writes two files:

- `geoinfo_{geo}_{year}.parquet` → **`geoinfo-` release**: `GEOID`, `NAME`, `tot_pop`.
- `geometry_{geo}_{year}.parquet` → **`geometry-` release**: `GEOID` and `geometry` (WKB), with the CRS in the file metadata.

`getNDI()` and `getICE()` join `geoinfo` by default, so users get `GEOID`, `NAME`, `tot_pop` and the index together. See `plan.md` D13 and §5.7.

### 2.4 Expected size

Scores only, two versions each: roughly **a few MB per file** at block group (the Yost test file came to 4.0 MB) and much less at county. Expect **a few hundred MB** each for the `ndi-` and `ice-` releases. The geometry release is ~5 GB, mostly block group and the 2011–2012 tract files (O4).

---

## 3. NDI-specific checks

These run inside `run_task.R` while the full `compute*()` result is still in memory, and are recorded in each task's `done` JSON. `qa_release.R` then summarises them.

### 3.1 Grouping match (plan.md §5.6 step 4b)

| Series | Package column | Reproduced with | Grouped by |
|---|---|---|---|
| `ndi_messer` | `NDIQuartile`, `NDIImputedQuartile` | `addQuartiles(method = "quantile_breaks")`, falling back to `ntile` when cut points are degenerate | scope group: all rows (national) or state |
| `ndi_powellwiley` | *(none in the package)* | — (no check) | — |
| `ice` | *(none)* | — | — |

**The pass condition is 0 mismatches.** Messer uses fixed quantile cut points, so tied scores don't depend on row order the way `ntile` does. Any mismatch is a real difference.

### 3.2 Direction of the index (sign) check

Both NDI methods flip the sign so that higher = more deprived (the package's documented deviation from `ndi`). Within **every scope group**, record:

- **Messer:** `cor(NDI, POV)` and `cor(NDIImputed, POV)` using `df_components`. **Must be > 0.**
- **Powell-Wiley:** `cor(NDI, PctFamBelowPov)` from the standardized `df_components`. **Must be > 0.**

A negative value in any state flags the task as failed QA.

### 3.3 PCA diagnostics per scope group

- **Messer:** variance explained by PC1, and the number of scope groups where the PCA failed or was skipped (`annotation == "PCA failed"`, or too few complete cases).
- **Powell-Wiley:** the number of components the Kaiser criterion chose (`pca_object$nfa`) and the variables used for scoring (|structure loading| > 0.4). Big jumps in `nfa` between years or states are worth a look.

### 3.4 Value checks (registry `checks`)

- ICE raw and imputed values all in **[−1, 1]**.
- **NA consistency**, using the in-memory annotation: scores are NA **exactly** where the annotation says `No population`, `PCA failed` or `Imputation incomplete`.
- Imputed columns have **no more NAs** than raw.
- Raw vs best correlation per file is high (> 0.95 expected), and never negative.

### 3.5 Population check against `geoinfo`

`tot_pop` isn't stored in NDI files, so the population a user sees comes from `geoinfo` (`B01003_001`). For every task, the package's own `tot_pop` is compared with `geoinfo`:

| Series | Package's population table | Expected differences |
|---|---|---|
| `ndi_messer` | `B01003_001`, the same table as `geoinfo` | 0 |
| `ndi_powellwiley` | `B01001_001` (sex by age, total) | 0: the same ACS total-population estimate, **to verify in the pilot** |
| `ice` | `B03002_001` (Hispanic origin by race, total) | 0: the same estimate, **to verify in the pilot** |

If Powell-Wiley or ICE differ, the pilot report shows by how much, and D13 is revisited for that series.

### 3.6 External check against the CRAN `ndi` package (pilot only)

ReproducibleNDI ports its methods from `ndi` (Buller), so `ndi` is an independent reference. This runs in the pilot, with `ndi` installed on Sherlock for the pipeline only.

| Compare | Where | Expectation |
|---|---|---|
| `ICE_*` vs `ndi::krieger()` | county and tract, 2019 and 2022 | **Exact match**: same formulas and income cut points, no PCA |
| Messer `NDI` vs `ndi::messer()` | county, national, 2022 | \|r\| ≈ 1. Small differences are expected from complete cases vs pairwise correlations; the sign may be flipped because of the POV alignment |
| Powell-Wiley `NDI` vs `ndi::powell_wiley()` | county, national, 2022 | Same as Messer. Also compare `ndi`'s population-weighted quintiles with `addIndexGroups()`, which settles the "method to verify" note in plan.md §4.4 |

---

## 4. Memory and time (starting guesses; the pilot refines them)

| Tier | Tasks | `--mem` | `--time` | Concurrency |
|---|---|---|---|---|
| `standard` | every county task; ICE tract | 16 GB | 2 h | `%20` |
| `medium` | Messer and Powell-Wiley tract (national and state) | 48 GB | 8 h | `%10` |
| `high` | Messer and ICE block group | 128 GB | 16 h | `%5` |

- **Why block group is heavy:** ~240k block groups, with Queen-contiguity neighbours built over the whole country for imputation. In the old Yost run, national block group jobs needed up to 128 GB.
- **This adds a third tier** (`medium`) to `plan.md`'s two. Tiers are therefore set per series in `registry.R`, not hard-coded in `make_grid.R`.
- **How the tiers get adjusted:** every `done` JSON records peak memory and run time. After the pilot, the tiers are set to observed peak + 50%.

### Census calls

- **One `get_acs()` call per task.** For tract and block group, tidycensus internally sends one request per state (~51).
- **National and state tasks share the download.** For the same series, geo and year they send identical arguments (all states), so `make_grid.R` puts national first and state tasks hit the cache (plan.md §5.4).
- **Expected Census traffic:**
  - Messer: 80 → ~40 real downloads.
  - Powell-Wiley: 56 → ~28.
  - ICE: 40 (no scope, so no sharing).
  - Geometry: 40.

---

## 5. Milestones for the NDI run

| Step | Work | Done when |
|---|---|---|
| N-0 | Decide N1 (tag ReproducibleNDI, or pin `06b5efb`). N2 and N3 are decided | Recorded here |
| N-1 | **Repo:** `git init`, first commit (plans, diagrams, `.gitignore`), create the **public** `HanLabCollaboration/ReproducibleSDOH`, push | Clonable from Sherlock |
| N-2 | **Package skeleton + `groups.R`:** `addGroups()` / `addQuartiles()` with `quantile_breaks`. It only needs to be good enough for the match check; the full package comes later | Local fixture test matches `NDIQuartile` from a local `computeNDI()` run (county, one state) |
| N-3 | **Pipeline core:** `config.R`, `registry.R` (entries `ndi_messer`, `ndi_powellwiley`, `ice`), `census_cache.R`, `make_grid.R` (with `--pilot`), `run_task.R` (including §3.1–3.4), `build_geometry.R`, `submit.sh`, `check_status.R`, `setup_env.sh` | One task runs end to end **on the laptop**, writing to a local folder ignored by `.gitignore` |
| N-4 | **Sherlock setup** (§6.1) | `setup_env.sh` finishes; a test Census call works |
| N-5 | **Pilot** (§6.3) | Every pilot task is done; §3 checks pass; the uncached re-run is identical; ICE matches `ndi::krieger()` exactly; files open in R and Python |
| N-6 | **Geoinfo + geometry, full run:** 40 tasks → `qa_release.R geoinfo` / `geometry` → `publish.R geoinfo` / `geometry` | `geoinfo-v{RUN_ID}` and `geometry-v{RUN_ID}` published; the manifest lists both; `getGeoInfo()` works |
| N-7 | **NDI and ICE, full run:** 176 tasks, re-submitting failures until everything is done | `check_status.R` shows 0 missing and 0 failed |
| N-8 | **QA + publish:** `qa_release.R ndi` / `ice` → review → `publish.R ndi` / `ice` | `ndi-v…` and `ice-v…` published; the manifest updated |
| N-9 | `bash archive.sh` (copies to Box, deletes the Census cache) | The run is archived before the `$SCRATCH` purge |

`qa_release.R`, `publish.R` and `archive.sh` are only needed from N-6 on, so the pilot doesn't wait for them.

---

## 6. Running on Sherlock

### 6.1 One-time setup

```bash
# 1. Log in
ssh <sunetid>@login.sherlock.stanford.edu

# 2. Clone the code (public repo, so no GitHub credentials are needed; $HOME is fine)
cd $HOME
git clone https://github.com/HanLabCollaboration/ReproducibleSDOH.git

# 3. Census API key — only in ~/.Renviron, never in the repo
echo 'CENSUS_API_KEY=<your key>' >> ~/.Renviron && chmod 600 ~/.Renviron

# 4. Build the R environment on a compute node, not the login node (compiling sf/spdep/arrow is heavy)
sh_dev -c 4 -m 16GB -t 2:00:00
cd $HOME/ReproducibleSDOH && bash pipeline/setup_env.sh
```

What `setup_env.sh` does (plan.md §5.5), specifically for NDI:

- **Loads modules:** R and the geospatial libraries. Start from what worked for the Yost run (`module load R/4.2.0`), and check `module spider R` / `module spider gdal` for newer versions.
- **Keeps installed packages out of `$HOME`:** sets `RENV_PATHS_CACHE=$GROUP_HOME/renv-cache`, since `$HOME` has a small quota (check with `sh_quota`).
- **Installs** `ReproducibleNDI` at the pinned ref (`@06b5efb`, or the tag from N1), plus `arrow`, `filelock`, `memoise`/`cachem`, `pkgload` and, for the pilot only, `ndi`.
- **Makes one test Census call** and writes `provenance.json`.

### 6.2 The edit → run loop

- **Scripts are changed only on the laptop, then pushed.** On Sherlock you only `git pull`.
- `run_task.R` records `pipeline_git_sha` in every file. It **refuses to run with uncommitted changes** unless `--allow-dirty` is passed for debugging. Every published file can then be traced back to an exact commit.

```bash
cd $HOME/ReproducibleSDOH && git pull
export RUN_ID=2026-10            # or edit pipeline/config.R and push
```

### 6.3 Pilot (N-5)

The pilot grid (`make_grid.R --pilot`) has **15 tasks**:

- **County, 2019 and 2022**, all three series, both scopes where applicable: Messer 4 + Powell-Wiley 4 + ICE 2 = 10.
- **Geoinfo + geometry** county 2019 and 2022: 2. These run first, because the population check needs them.
- **Memory calibration**, 2022 national: Messer tract, Powell-Wiley tract, Messer block group: 3.

```bash
Rscript pipeline/make_grid.R --pilot              # writes $SCRATCH/sdoh/$RUN_ID/grids/pilot_*.csv

# First, one task by hand on an interactive node, to see errors directly
sh_dev -c 2 -m 16GB -t 1:00:00
SLURM_ARRAY_TASK_ID=1 Rscript pipeline/run_task.R --grid $SCRATCH/sdoh/$RUN_ID/grids/pilot_standard.csv

# Then the rest as arrays
bash pipeline/submit.sh --grid $SCRATCH/sdoh/$RUN_ID/grids/pilot_standard.csv --tier standard
bash pipeline/submit.sh --grid $SCRATCH/sdoh/$RUN_ID/grids/pilot_medium.csv   --tier medium
bash pipeline/submit.sh --grid $SCRATCH/sdoh/$RUN_ID/grids/pilot_high.csv     --tier high

squeue -u $USER                                   # watch jobs
Rscript pipeline/check_status.R                   # done / failed / missing + re-run commands
```

**The pilot passes when:**

1. Every task is done.
2. The grouping match shows **0** mismatches (§3.1).
3. The sign checks are positive in every state (§3.2).
4. The population check shows **0** differences for all three series (§3.5).
5. The state tasks show **cache hits**.
6. An uncached re-run of one county task is **identical**.
7. ICE equals `ndi::krieger()` exactly.
8. The Parquet files open in R (`arrow` / `nanoparquet`) and Python (`pandas`, `polars`), and `getNDI()`-style joins with `geoinfo` give one row per `GEOID`.

### 6.4 Full run (N-6, N-7)

```bash
Rscript pipeline/make_grid.R --indices geometry,ndi_messer,ndi_powellwiley,ice
bash pipeline/submit.sh --grid …/tasks_geometry.csv --tier standard     # geoinfo + geometry first
bash pipeline/submit.sh --grid …/tasks_standard.csv --tier standard
bash pipeline/submit.sh --grid …/tasks_medium.csv   --tier medium
bash pipeline/submit.sh --grid …/tasks_high.csv     --tier high
Rscript pipeline/check_status.R                   # repeat; re-submit with --ids until 0 missing
```

Publishing (N-6, N-8) needs the `gh` command-line tool on Sherlock, authenticated to the org (`gh auth login`). The alternative is to publish from the laptop after `archive.sh` copies the files to Box.

---

## 7. NDI-specific risks

| # | Risk | Mitigation |
|---|---|---|
| NR1 | `computeICE()` returns no `NAME` | Resolved by D13: no score file stores `NAME` |
| NR2 | Imputation at block group runs out of memory or time (neighbours built over the whole US) | `high` tier; the pilot measures one Messer block-group task first; lower concurrency |
| NR3 | Powell-Wiley's DP/S variables change codes between years (e.g. `DP04_0074P` → `DP04_0075P` in 2015, already handled) and could change again | The pilot covers 2019 and 2022; the full run's `done` JSONs flag years with unusual NA rates; QA step 5 (NA rate per year) |
| NR4 | 2011–2012 ACS data-profile/subject tables behave differently | Covered by the full run; watch the NA-rate report for 2011–2012 before publishing |
| NR5 | The package changes between the pilot and the full run | Pin `06b5efb` or a tag (N1) in `config.R`; `provenance.json` records the installed SHA; `run_task.R` stops if it differs from the pin |
| NR6 | Messer PCA fails in small states (fewer than 10 complete observations at county, state scope) | Expected (e.g. DE, RI, DC at county): the package annotates `PCA failed`. QA reports these counts rather than failing |

---

## 8. Open decisions (NDI)

- **N1:** Tag ReproducibleNDI as **`v0.1.0`** before the full run (recommended, as a readable reference in the release notes), or pin commit `06b5efb`?
- ~~**N2:** ICE `NAME`~~ **Decided:** `NAME` and `tot_pop` live only in the `geoinfo` release; index files hold `GEOID` + scores (plan.md D13).
- ~~**N3:** Code repo visibility~~ **Decided:** public (plan.md D14).
- **N4:** NDI imputation weights: keep the package default `weight_var = "tot_pop"`, as proposed? ICE is always unweighted.
