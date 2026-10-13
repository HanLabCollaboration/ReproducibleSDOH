#!/bin/bash
# =============================================================================
# geography/job.sh — what each SLURM array task runs. Submitted by submit.sh, which
# sets the resources (memory, time, array range) and exports:
#   SDOH_PIPELINE_DIR   the pipeline/ folder of the checkout
#   SDOH_GRID           the task list (CSV) this array works through
# =============================================================================

echo "========================================"
echo "Job:     ${SLURM_JOB_ID:-none}"
echo "Task:    ${SLURM_ARRAY_TASK_ID:-none}"
echo "Node:    ${SLURMD_NODENAME:-$(hostname)}"
echo "Grid:    ${SDOH_GRID}"
echo "Started: $(date)"
echo "========================================"

source "${SDOH_PIPELINE_DIR}/environment_setup.sh"

Rscript "${SDOH_PIPELINE_DIR}/geography/run_task.R" --grid "${SDOH_GRID}"
EXIT_CODE=$?

echo "========================================"
echo "Finished: $(date)"
echo "Exit code: ${EXIT_CODE}"
echo "========================================"

exit ${EXIT_CODE}
