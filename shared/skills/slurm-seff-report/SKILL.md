---
name: slurm-seff-report
description: Modify a Slurm job script so it runs `seff` at the end of the existing script and writes a usage report file when the job finishes.
allowed-tools: Read, Edit, Write, Glob, Grep
---

# Add an Inline `seff` Usage Report

Use this skill when the user wants an existing Slurm job script to automatically generate a usage or efficiency report after the job finishes.

The goal is to modify the user's existing job script so the script itself writes a durable report near the end of the batch run.

## Why this pattern

Do not create a separate dependent follow-up job for this workflow. The report generation should be added directly to the end of the existing bash script.

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
- Whether the script already contains a `seff` block or a post-job report block

Do not duplicate an existing reporting mechanism. If one exists, update it instead of appending a second copy.

### 2. Add an inline report block near the end of the script

Add a small block after the main workload command and near the end of the script, before any final `echo "End"` line if needed, or immediately after it if that is the cleaner local style.

The block should:

- use the current job id from `SLURM_JOB_ID`
- write a report to a stable path such as `logs/<job_name>_<jobid>_usage.txt`
- run `seff "$SLURM_JOB_ID"`
- also run a concise `sacct` command for extra accounting context
- avoid changing the main workload command unless needed

Recommended pattern:

```bash
# Write a post-run usage report for this job.
REPORT_DIR="${SLURM_SUBMIT_DIR:-$PWD}/logs"
mkdir -p "$REPORT_DIR"
SEFF_REPORT_PATH="${REPORT_DIR}/${SLURM_JOB_NAME:-job}_${SLURM_JOB_ID}_usage.txt"

{
  echo "Usage report for Slurm job ${SLURM_JOB_ID}"
  echo "Generated: $(date)"
  echo
  echo "== seff =="
  seff "${SLURM_JOB_ID}"
  echo
  echo "== sacct =="
  sacct -j "${SLURM_JOB_ID}" \
    --format=JobID%15,JobName%28,Partition%12,State%12,ExitCode%10,Elapsed%12,TotalCPU%12,ReqMem%12,MaxRSS%12,AllocTRES%40 \
    --noheader
} | tee "${SEFF_REPORT_PATH}"
```

Guidelines:

- Use a clear comment so future readers know why the block exists.
- Keep the insertion idempotent. If the block already exists, update it rather than duplicating it.
- Use `SLURM_SUBMIT_DIR` when possible so reports land near the submission context.
- Preserve the script's existing structure and comments where possible.

### 3. Generate a usage report path that is easy to find

Default to:

```text
logs/<job_name>_<jobid>_usage.txt
```

If the script already uses another report or artifact directory, align with that local pattern instead of inventing a new one.

### 4. Explain what changed

After editing:

- Tell the user which main script was changed
- Tell them where the final usage report will be written
- Mention that the existing script now runs `seff` and `sacct` itself near the end of the batch job

## Editing Rules

- Keep edits scoped. Do not refactor unrelated job logic.
- Preserve existing comments and environment setup unless they conflict with the new reporting logic.
- If the user pasted a script instead of giving a path, return the full modified script.
- If the user gave a real file path, edit the file in place.

## Final reminder to the user

Tell the user that future jobs submitted with the modified script will produce:

- the normal job logs, and
- a post-job usage report driven by `seff`

If appropriate, mention that the resulting report can be used to reduce over-requested `--mem`, `--time`, CPU, or GPU resources for the next run.
