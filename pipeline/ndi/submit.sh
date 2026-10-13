#!/bin/bash
# =============================================================================
# ndi/submit.sh — submits a task list as a SLURM array.
#
#   bash pipeline/ndi/submit.sh --grid <grid.csv>               # every task in the list
#   bash pipeline/ndi/submit.sh --grid <grid.csv> --ids 3,7     # only these task_ids
#   bash pipeline/ndi/submit.sh --grid <grid.csv> --tier high   # override the tier (e.g. after out-of-memory)
#   bash pipeline/ndi/submit.sh --grid <grid.csv> --dry-run     # print the sbatch command only
#
# Memory, time and concurrency come from the tier in config.R.
# Optional environment:
#   SDOH_MAIL=<address>      email when the array ends or a task fails
#   SDOH_PARTITION=<list>    SLURM partitions (default in config.R)
# =============================================================================

set -euo pipefail

INDEX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="$(dirname "${INDEX_DIR}")"

GRID=""; IDS=""; TIER=""; DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --grid)    GRID="$2"; shift 2 ;;
    --ids)     IDS="$2";  shift 2 ;;
    --tier)    TIER="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
[[ -f "${GRID}" ]] || { echo "Grid file not found: '${GRID}'" >&2; exit 2; }
GRID="$(cd "$(dirname "${GRID}")" && pwd)/$(basename "${GRID}")"

# R is needed to read the settings from config.R
if ! command -v Rscript >/dev/null 2>&1; then
  source "${PIPELINE_DIR}/environment_setup.sh"
fi

# tier mem time max_parallel cpus n_tasks partition log_dir
SETTINGS="$(Rscript -e '
  a <- commandArgs(TRUE)
  INDEX_DIR <- a[1]
  source(file.path(INDEX_DIR, "config.R"))
  g <- read.csv(a[2])
  tier <- if (nzchar(a[3])) a[3] else unique(g$tier)
  if (length(tier) != 1 || !tier %in% names(TIERS)) stop("Unknown or mixed tier: ", paste(tier, collapse = ","))
  t <- TIERS[[tier]]
  cat(tier, t$mem, t$time, t$max_parallel, SLURM_CPUS, nrow(g), SLURM_PARTITION, LOG_DIR, INDEX)
' "${INDEX_DIR}" "${GRID}" "${TIER}")"
read -r TIER MEM TIME MAX_PARALLEL CPUS N_TASKS PARTITION LOG_DIR INDEX <<< "${SETTINGS}"

ARRAY="${IDS:-1-${N_TASKS}}"
mkdir -p "${LOG_DIR}"

CMD=(sbatch
  --job-name="sdoh_${INDEX}_${TIER}"
  --array="${ARRAY}%${MAX_PARALLEL}"
  --mem="${MEM}"
  --time="${TIME}"
  --cpus-per-task="${CPUS}"
  --partition="${PARTITION}"
  --output="${LOG_DIR}/%x_%A_%a.out"
  --error="${LOG_DIR}/%x_%A_%a.err"
  --export="ALL,SDOH_PIPELINE_DIR=${PIPELINE_DIR},SDOH_GRID=${GRID}"
)
if [[ -n "${SDOH_MAIL:-}" ]]; then
  CMD+=(--mail-type=END,FAIL --mail-user="${SDOH_MAIL}")
fi
CMD+=("${INDEX_DIR}/job.sh")

echo "Grid: ${GRID} (${N_TASKS} tasks) | tier ${TIER}: ${MEM}, ${TIME}, up to ${MAX_PARALLEL} at once"
echo "Logs: ${LOG_DIR}"
printf '%q ' "${CMD[@]}"; echo
if [[ ${DRY_RUN} -eq 0 ]]; then
  "${CMD[@]}"
fi
