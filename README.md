# ReproducibleSDOH

> **Status: under construction.** The R package does not exist yet. The Sherlock pipeline in `pipeline/` works and is being run one index at a time (see [Status](#status)).

ReproducibleSDOH will be the umbrella R package for the **ReproducibleX** family of neighborhood socioeconomic indices built from the US Census Bureau's American Community Survey:

| Package | Indices |
|---|---|
| [ReproducibleYostIndex](https://github.com/HanLabCollaboration/ReproducibleYostIndex) | Yost Index |
| [ReproducibleNDI](https://github.com/HanLabCollaboration/ReproducibleNDI) | Neighborhood Deprivation Index (Messer, Powell-Wiley), Index of Concentration at the Extremes (ICE) |
| [ReproducibleSDI](https://github.com/HanLabCollaboration/ReproducibleSDI) | Social Deprivation Index |
| [ReproducibleCDI](https://github.com/HanLabCollaboration/ReproducibleCDI) | Community Deprivation Index |

It will offer two ways to get an index:

- **`get*()` functions** (`getYost()`, `getNDI()`, `getICE()`, `getSDI()`, `getCDI()`) that download **pre-computed** indices, without a Census API key. The files are Parquet, published as releases of `ReproducibleSDOH-data`.
- **`computeSDOH()`**, which hands off to the sibling packages to compute an index locally with any options.

This repository also holds the **Stanford Sherlock (SLURM) pipeline** that pre-computes every index × geography × scope × year. It lives in `pipeline/` and is not part of the installed package.

## Pipeline

The pipeline runs **one index at a time**. Each index has its own folder, `pipeline/<index>/`, holding the same five scripts; everything that differs between indices is in that folder's `config.R`. Below, `<index>` stands for any of them (for example `yost`).

### Files in this repository

```
pipeline/
├── environment_setup.sh     Modules to load and R packages to install on Sherlock.
│                            `source` it to load the environment; run it with `install` once.
├── common/
│   └── census_cache.R       Disk cache for Census downloads, shared by every index.
└── <index>/
    ├── config.R             Every setting for this index: pinned package commit, geographies,
    │                        scopes, years, compute arguments, output columns, output paths,
    │                        SLURM memory and time.
    ├── make_grid.R          Writes the task lists: one row per geography × scope × year.
    ├── run_task.R           Computes ONE task and writes one Parquet file.
    ├── job.sh               What each SLURM array task runs (loads the environment, calls run_task.R).
    └── submit.sh            Submits a task list as a SLURM array.
```

### Files a run creates on Sherlock

Nothing below is committed to git. There are two locations.

**Group folder** (`$GROUP_HOME/tidySDOH/`): kept between runs.

```
$GROUP_HOME/tidySDOH/
├── ReproducibleSDOH/        Clone of this repository. Update it with `git pull` only.
├── R_libs/<R version>/      R packages installed by environment_setup.sh.
├── tigris_cache/            Census boundary shapefiles, downloaded once.
├── installed_packages.csv   Exact package versions of the install.
└── session_info.txt         R session information of the install.
```

**Scratch** (`$SCRATCH/sdoh/<RUN_ID>/<index>/`): one folder per run and index.

```
$SCRATCH/sdoh/<RUN_ID>/<index>/
├── grids/
│   ├── tasks_<tier>.csv     Full task list for one memory tier (from make_grid.R).
│   └── pilot_<tier>.csv     Small test list (from make_grid.R --pilot).
├── out/
│   └── <index>_<geo>_<scope>_<year>.parquet    The data: GEOID + index scores.
├── done/
│   ├── <file>.parquet.json         Written when a task succeeds: row count, checks,
│   │                               run time, peak memory, cache use, versions, commits.
│   └── <file>.parquet.error.json   Written instead when a task fails: the error message.
├── logs/
│   └── sdoh_<index>_<tier>_<jobid>_<task>.out / .err    SLURM logs, one pair per task.
└── census_cache/            Cached Census downloads. Delete after the run.
```

`<RUN_ID>` is set in `config.R` (for example `2026-10`). `<geo>` is `tract` or `block_group`; `<scope>` is `national` or `state`. Sherlock deletes scratch files that are not touched for 90 days, so copy `out/`, `done/`, `logs/` and `grids/` elsewhere after a run.

### Running an index

Run these on a Sherlock login or compute node, from the clone.

```bash
# One time: get the code and your Census API key
mkdir -p $GROUP_HOME/tidySDOH && cd $GROUP_HOME/tidySDOH
git clone https://github.com/HanLabCollaboration/ReproducibleSDOH.git
echo 'CENSUS_API_KEY=<your key>' >> ~/.Renviron && chmod 600 ~/.Renviron

# One time per index: install the packages (on a compute node; compiling is heavy)
cd $GROUP_HOME/tidySDOH/ReproducibleSDOH
sh_dev -c 4 -m 16GB -t 2:00:00
bash pipeline/environment_setup.sh install

# Every session: load the environment
source pipeline/environment_setup.sh

# Pilot: a few tasks, to check everything works and measure memory and time
Rscript pipeline/<index>/make_grid.R --pilot
Rscript pipeline/<index>/run_task.R --grid $SCRATCH/sdoh/<RUN_ID>/<index>/grids/pilot_<tier>.csv --task 1
bash pipeline/<index>/submit.sh --grid $SCRATCH/sdoh/<RUN_ID>/<index>/grids/pilot_<tier>.csv

# Full run: one submit per tier
Rscript pipeline/<index>/make_grid.R
bash pipeline/<index>/submit.sh --grid $SCRATCH/sdoh/<RUN_ID>/<index>/grids/tasks_<tier>.csv

# Follow it
squeue -u $USER
ls $SCRATCH/sdoh/<RUN_ID>/<index>/out | wc -l          # finished files
ls $SCRATCH/sdoh/<RUN_ID>/<index>/done/*.error.json    # failed tasks, if any
```

Things to know:

- **Re-submitting is always safe.** A task whose output already exists skips itself, so the same `submit.sh` command reruns only what is missing.
- **Change scripts on your own computer, then push.** On Sherlock, only `git pull`. `run_task.R` refuses to run when the clone has uncommitted pipeline changes, so that every file traces back to one commit.
- **The package version is pinned.** `config.R` names the exact commit of the sibling package; `run_task.R` refuses to run with any other.
- **Memory and time** are set per tier in `config.R`. `submit.sh --tier <tier>` overrides the tier, and `--ids 3,7` submits only those tasks.
- **Optional environment variables:** `RUN_ID`, `SDOH_OUT_ROOT` (write somewhere other than `$SCRATCH/sdoh/<RUN_ID>`), `SDOH_PARTITION`, `SDOH_MAIL` (email when an array ends or a task fails).

### Status

| Index | Folder | Status |
|---|---|---|
| Yost | `pipeline/yost/` | Full run complete on 2026-10-12: 52 of 52 tasks, all checks passed. Not yet published |
| NDI (Messer, Powell-Wiley), ICE | not created yet | Next |
| SDI | not created yet | |
| CDI | not created yet | |

Notes from the Yost run:

- **Coverage:** tract (2011–2024) and block group (2013–2024), national and state scope.
- **Versions published:** `Yost` (raw) and `YostStabilizedImputed` (stabilized and imputed), from one `computeYostIndex()` call per task.
- **Parquet writer:** `nanoparquet`. `arrow` does not load on Sherlock, because its prebuilt library needs a newer system C library.
- **Measured in the full run:** tract tasks peaked at 2.4–2.9 GB, except 2011 and 2012 at 14.3 GB (those years download full-detail boundaries), and took 16–33 minutes. Block-group tasks peaked at 2.4–5.5 GB and took 35–81 minutes.
- **Not built yet:** a status script, the QA report, publishing to `ReproducibleSDOH-data`, and archiving the run off scratch. The grouping and population checks described in the plan are recorded as "not run".

## Plans

- [`plan/plan.md`](plan/plan.md): the shared design: repositories, data format, package API, pipeline, release workflow.
- [`plan/plan_NDI.md`](plan/plan_NDI.md): the NDI family (Messer, Powell-Wiley, ICE).

The plans were written before the pipeline was built and differ from it in places: the pipeline has one folder per index instead of a shared registry, Yost ran first, and county is not computed.

## License

MIT © Rafael Catoia Pulgrossi, Tae Yoon Lee
