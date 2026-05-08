---
name: slurm-seff-report
description: Modify a Slurm job script so it schedules a post-job `seff` usage report and writes efficiency data to a report file when the job completes.
allowed-tools: Read, Edit, Write, Glob, Grep
---

# Add a Post-Job `seff` Usage Report

Use this skill when the user wants an existing Slurm job script to automatically generate a usage or efficiency report after the job finishes.

The goal is to modify the user's job script so it schedules a lightweight dependent follow-up job that runs `seff` after the main batch job has completed and writes a durable report file.

## Why this pattern

Do **not** prefer a simple `trap 'seff "$SLURM_JOB_ID"' EXIT` block in the main job script. `seff` is most useful after Slurm accounting has finalized the batch job. A small dependent job with `--dependency=afterany:<jobid>` is more reliable.

## Inputs

The user should provide one of:

- A path to an existing `.sh` or `.slurm` job script
- The contents of an existing job script

If the user has not provided a script yet, ask for the script path or content.

## Workflow

### 1. Read the script and preserve its style

Inspect the existing script before editing:

- Existing `#SBATCH` directives
- The job name, account, output directory, and shell style
- Whether the script already creates `logs/`
- Whether the script already contains a `seff` block, a post-job report block, or a dependent reporting job

Do not duplicate an existing reporting mechanism. If one exists, update it instead of appending a second copy.

### 2. Prefer a companion report script

Create a sibling helper script next to the main job script, with a name like:

```text
<job-script-basename>.seff-report.sh
```

This helper script should:

- Be a small CPU-only batch script
- Reuse the original job's `--account` if the main script has one
- Use short resources such as `--time=00:05:00`, `--cpus-per-task=1`, `--mem=1G`
- Avoid requesting GPUs
- Run `seff <jobid>`
- Also run a concise `sacct` command for extra accounting context
- Write a human-readable report to a stable path such as:
  - `logs/<job_name>_<jobid>_usage.txt`, or
  - another user-visible report path if the script already has a reporting convention

Recommended helper body:

```bash
#!/bin/bash
#SBATCH --job-name=<main-job-name>-seff
#SBATCH --time=00:05:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --output=logs/%x_%j.out
#SBATCH --error=logs/%x_%j.err

set -euo pipefail

: "${SEFF_TARGET_JOB_ID:?missing job id}"
: "${SEFF_REPORT_PATH:?missing report path}"

mkdir -p "$(dirname "$SEFF_REPORT_PATH")"

{
  echo "Usage report for Slurm job ${SEFF_TARGET_JOB_ID}"
  echo "Generated: $(date)"
  echo
  echo "== seff =="
  seff "${SEFF_TARGET_JOB_ID}"
  echo
  echo "== sacct =="
  sacct -j "${SEFF_TARGET_JOB_ID}" \
    --format=JobID%15,JobName%28,Partition%12,State%12,ExitCode%10,Elapsed%12,TotalCPU%12,ReqMem%12,MaxRSS%12,AllocTRES%40 \
    --noheader
} | tee "${SEFF_REPORT_PATH}"
```

If the main script already has a clear account directive such as `#SBATCH --account=...`, copy that directive into the helper script. If the cluster clearly needs a partition for CPU-side work and the correct CPU partition is obvious from the existing script or repo conventions, add it; otherwise do not guess.

### 3. Modify the main job script to schedule the helper

Add a small block near the start of the executable body, after `set -euo pipefail` and after any `mkdir -p logs` style setup, so the batch job schedules the dependent helper exactly once when it starts.

Recommended pattern:

```bash
# Schedule a post-job efficiency report.
if [[ -n "${SLURM_JOB_ID:-}" ]]; then
  REPORT_DIR="${SLURM_SUBMIT_DIR:-$PWD}/logs"
  mkdir -p "$REPORT_DIR"
  SEFF_REPORT_PATH="${REPORT_DIR}/${SLURM_JOB_NAME:-job}_${SLURM_JOB_ID}_usage.txt"
  sbatch \
    --dependency=afterany:${SLURM_JOB_ID} \
    --export=ALL,SEFF_TARGET_JOB_ID="${SLURM_JOB_ID}",SEFF_REPORT_PATH="${SEFF_REPORT_PATH}" \
    "<absolute-or-stable-path-to-helper-script>" >/dev/null
fi
```

Guidelines:

- Use a clear comment so future readers know why the block exists.
- Keep the insertion idempotent. If the block already exists, update it rather than duplicating it.
- Use `SLURM_SUBMIT_DIR` when possible so reports land near the submission context.
- Prefer `afterany` instead of `afterok`, because users usually want a usage report even for failed or cancelled jobs.
- Do not change the user's main workload command unless needed to keep the script correct.

### 4. Generate a usage report path that is easy to find

Default to:

```text
logs/<job_name>_<jobid>_usage.txt
```

If the script already uses another report or artifact directory, align with that local pattern instead of inventing a new one.

### 5. Explain what changed

After editing:

- Tell the user which main script was changed
- Tell them which helper script was created
- Tell them where the final usage report will be written
- Mention that the helper job is a lightweight dependent job that runs `seff` after the main batch job completes

## Editing Rules

- Keep edits scoped. Do not refactor unrelated job logic.
- Preserve existing comments and environment setup unless they conflict with the new reporting logic.
- If the user pasted a script instead of giving a path, return the full modified script and the full helper script content.
- If the user gave a real file path, edit the file in place and create the companion helper script alongside it.

## Final reminder to the user

Tell the user that future jobs submitted with the modified script will produce:

- the normal job logs, and
- a post-job usage report driven by `seff`

If appropriate, mention that the resulting report can be used to reduce over-requested `--mem`, `--time`, CPU, or GPU resources for the next run.
