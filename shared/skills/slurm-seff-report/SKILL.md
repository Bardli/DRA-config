---
name: slurm-seff-report
description: Add resource-monitoring guidance to a Slurm job script by choosing the right strategy for the job shape. Use a simple inline cgroup-v2 CPU/memory snapshot only for direct batch-step workloads; for srun, MPI/DDP, or multi-step jobs, warn that the simple snapshot can under-report and choose step-aware instrumentation, GPU sampling, or final seff instead. Use when the user wants in-script usage reporting or asks to print seff at the end.
allowed-tools: Read, Edit, Write, Glob, Grep
---

# Add Slurm Resource Monitoring

Modify the user's existing Slurm job script so it gets the right level of resource monitoring for
its shape. Do **not** blindly append one fixed block to every script. First classify how the job
runs, then choose the least misleading monitoring pattern.

## What this is and is not

- `seff` queries `sacct`. While the job script is still running, the job is usually `RUNNING`
  and `sacct` has **not finalized** the per-step accounting (`TotalCPU`/`Elapsed`/CPU efficiency).
  In-script `seff` therefore prints incomplete or misleading data, or refuses with "Job is still
  running".
- The **cgroup-v2 files** (`memory.peak`, `cpu.stat`) are kernel-tracked **continuously**, are
  available before `sacct` finalizes, and can be useful as an immediate snapshot.
- This block reads the cgroup of the report block's own shell. On Fir, live tests on 2026-05-27
  showed it matched `seff` for a direct batch-step workload, but **under-reported an `srun`
  workload** because the real work ran in a separate Slurm step.
- GPU efficiency is **not** available from cgroup. The cluster's `seff <jobid>` after the job exits
  remains the authoritative final report for CPU, memory, and GPU accounting.

## Inputs

The user provides one of:
- A path to an existing `.sh` / `.slurm` job script
- The contents of an existing job script

If neither is given, ask.

## Workflow

### 1. Inspect the script

- `#SBATCH` directives, job name, output dir, shell conventions
- How the main workload is launched:
  - **Direct batch step**: `python train.py`, `bash run.sh`, `Rscript ...` directly in the sbatch
    shell. The simple end-of-script cgroup snapshot is acceptable.
  - **Separate Slurm step / multi-step**: `srun ...`, MPI, DDP/`torchrun` launched through `srun`,
    repeated `srun preprocess/train/eval`, or multiple job phases. The simple end-of-script block
    can under-report because it reads `step_batch`, not the workload step.
  - **GPU job**: cgroup does not expose GPU efficiency. Add GPU sampling only if useful; final GPU
    accounting still comes from post-completion `seff`/`sacct`.
- Whether a usage-report block is already present (look for the `Self-contained cgroup-based
  usage report` marker, **or** the old `seff "$SLURM_JOB_ID"` pattern that this skill used to
  insert) — replace in place rather than appending a duplicate.

### 2. Choose the monitoring strategy

| Job shape | What to do |
|---|---|
| Direct batch-step workload | Insert the simple cgroup snapshot block below. It matched `seff` in live Fir tests for direct batch-step Python. |
| `srun` / MPI / DDP / multi-step workload | Do **not** present the simple block as the job's true usage. Prefer step-aware instrumentation inside each `srun` step when you can do it safely; otherwise leave the script relying on final `seff`/`harvest` and tell the user why. |
| GPU workload | Optionally add `nvidia-smi` sampling during the workload for a runtime GPU trace. Still tell the user final GPU efficiency comes from `seff <jobid>` after exit. |
| Script uses `set -e` and failures matter | Add an `EXIT` trap only if it can be done without changing workload semantics. Otherwise say failed jobs may skip the inline snapshot. |

When you choose not to insert the simple block, still help the user by adding a final comment or
post-run instruction such as `seff <jobid>` / `/harvest` rather than adding a misleading report.

### 3. Direct batch-step pattern

Add the block **after** the main workload command, before any final `echo "End"` line if present.
Keep the marker comment exactly as written so future runs of this skill find and update the block
instead of duplicating it. If the script uses `set -e`, explain that failures before this block may
skip the snapshot unless the script adds an `EXIT` trap; do not silently promise failed-job reports.

```bash
# ---- Inline cgroup snapshot (CPU/memory only; not a seff replacement) ----
REPORT_DIR="${SLURM_SUBMIT_DIR:-$PWD}/logs"
mkdir -p "$REPORT_DIR"
USAGE_REPORT="${REPORT_DIR}/${SLURM_JOB_NAME:-job}_${SLURM_JOB_ID}_usage.txt"

# Resolve the job's own cgroup-v2 path (the "0::/..." line in /proc/self/cgroup)
JOB_CG=$(awk -F: '/^0::/{print $3; exit}' /proc/self/cgroup 2>/dev/null)

# Peak memory in bytes and total CPU microseconds (both kernel-tracked continuously)
MEM_PEAK="unavailable"; CPU_USEC="unavailable"
[ -n "$JOB_CG" ] && [ -r "/sys/fs/cgroup${JOB_CG}/memory.peak" ] && \
  MEM_PEAK=$(cat "/sys/fs/cgroup${JOB_CG}/memory.peak")
[ -n "$JOB_CG" ] && [ -r "/sys/fs/cgroup${JOB_CG}/cpu.stat" ] && \
  CPU_USEC=$(awk '/^usage_usec/{print $2}' "/sys/fs/cgroup${JOB_CG}/cpu.stat")

# Format the report in seff-like style: GB / HH:MM:SS / efficiency lines
awk -v jid="$SLURM_JOB_ID" -v jname="${SLURM_JOB_NAME:-?}" \
    -v host="$(hostname)" -v gen="$(date -Iseconds)" \
    -v cpus="${SLURM_CPUS_PER_TASK:-1}" -v mem_req_mb="${SLURM_MEM_PER_NODE:-0}" \
    -v gpu_req="${SLURM_GPUS_PER_NODE:-?}" \
    -v mem_peak="$MEM_PEAK" -v cpu_usec="$CPU_USEC" -v wall_sec="${SECONDS:-0}" \
'function hms(s,    h,m,ss){ h=int(s/3600); m=int((s%3600)/60); ss=int(s%60);
  return sprintf("%02d:%02d:%02d", h, m, ss) }
 BEGIN{
  print "Slurm job usage snapshot (cgroup-direct, end-of-script)"
  printf "  Job ID    : %s\n  Job name  : %s\n  Host      : %s\n  Generated : %s\n\n", \
    jid, jname, host, gen
  print "== Resources requested =="
  printf "  --cpus-per-task : %s\n  --mem (per node): %s MB\n  --gpus-per-node : %s\n\n", \
    cpus, mem_req_mb, gpu_req
  print "== Cgroup measurements (kernel-direct; accurate at end of script) =="
  if (mem_peak == "unavailable") {
    print "  Memory Utilized  : unavailable (cgroup v1 / EL7 cluster?)"
  } else {
    mb = mem_peak/1048576; gb = mb/1024
    if (gb >= 1) printf "  Memory Utilized  : %.2f GB\n", gb
    else         printf "  Memory Utilized  : %.2f MB\n", mb
    if (mem_req_mb+0 > 0)
      printf "  Memory Efficiency: %.1f%% of %.2f GB (requested)\n", mb/mem_req_mb*100, mem_req_mb/1024
  }
  if (cpu_usec == "unavailable") {
    print "  CPU Utilized     : unavailable"
  } else {
    printf "  CPU Utilized     : %s\n", hms(cpu_usec/1000000)
  }
  if (wall_sec+0 > 0) printf "  Wall-clock time  : %s\n", hms(wall_sec)
  if (cpu_usec != "unavailable" && wall_sec+0 > 0 && cpus+0 > 0) {
    cw  = wall_sec * cpus
    eff = (cpu_usec/1000000) / cw * 100
    printf "  CPU Efficiency   : %.2f%% of %s core-walltime (wall * %s cpus)\n", eff, hms(cw), cpus
  }
  print ""
  print "Note: this is an inline cgroup snapshot, not a seff replacement. It may"
  print "under-report srun/multi-step jobs. For finalized accounting including GPU"
  print "efficiency, run after the job exits:"
  printf "  seff %s\n", jid
}' > "$USAGE_REPORT"
echo "Usage report -> $USAGE_REPORT"
# ---- End cgroup snapshot ----
```

### 4. If the old `seff`-in-script block is found

The previous version of this skill inserted `seff "$SLURM_JOB_ID"` in-script. That pattern is
**broken** (sacct unfinalized while the job is still running). Remove or replace any such block
rather than leaving both. For direct batch-step scripts, replace it with the cgroup snapshot block
above. For `srun` / multi-step scripts, replace it with the safer strategy selected in step 2 and
tell the user why final `seff` remains the authoritative source.

### 5. Tell the user what changed

- Which script was edited
- Which job-shape strategy you selected and why
- The usage-report path (`logs/<job_name>_<jobid>_usage.txt`) if a snapshot block was inserted
- That **CPU + memory** are read from the report block's cgroup without waiting for `sacct`
- That `srun` / multi-step jobs may be under-reported unless you added step-aware instrumentation
- That **GPU efficiency** is not provided by cgroup — `seff <jobid>` after the job exits is the
  source for finalized accounting

## Editing Rules

- Scope edits to the report block; do not refactor unrelated job logic.
- Preserve existing comments and shell setup.
- Do not wrap complex `srun`, MPI, or DDP commands unless the quoting and exit-status preservation
  are straightforward. A correct final `seff` instruction is better than fragile instrumentation.
- If the user pasted contents (not a path), return the full modified script.
- If a file path was given, edit in place.

## Limitations

- **Not a `seff` replacement.** Use this only as an immediate CPU/memory snapshot. Final resource
  tuning should still use `seff <jobid>` after completion.
- **`srun` / multi-step jobs can be under-reported.** The block reads its own shell's cgroup, not a
  guaranteed aggregate of every Slurm step in the job.
- **Failure paths may skip the block.** Scripts with `set -e` will not reach this block if the main
  workload exits non-zero unless the script uses a trap.
- **GPU efficiency** is not in this report — see the footer note that points the user to
  `seff <jobid>` after the job exits.
- **Cgroup v1** systems (older Alliance clusters on EL7/CentOS 7) do not expose
  `memory.peak` / `cpu.stat` at the documented v2 paths. On those systems the report will say
  `unavailable` for affected fields and otherwise still produce a useful skeleton. Fir, Trillium,
  Rorqual, Killarney (all EL9, cgroup v2) are fully supported. Verified on Fir 2026-05.
