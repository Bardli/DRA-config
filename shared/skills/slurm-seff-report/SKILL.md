---
name: slurm-seff-report
description: Add an inline cgroup-v2 CPU/memory snapshot to a Slurm job script. This is not a seff replacement: it can match seff for direct batch-step workloads but can under-report srun or multi-step jobs, and it cannot report GPU efficiency. Use when the user wants an immediate in-script usage snapshot or asks to print seff at the end; explain that final seff after job exit remains authoritative.
allowed-tools: Read, Edit, Write, Glob, Grep
---

# Add an Inline Cgroup Snapshot

Modify the user's existing Slurm job script so it writes a per-job usage report
(`logs/<job_name>_<jobid>_usage.txt`) at the **end** of the script, by reading the current
cgroup-v2 accounting files directly. Treat this as an **inline CPU/memory snapshot**, not as a
replacement for `seff`.

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
- Whether the workload uses `srun`, multiple Slurm steps, MPI, or other subprocess launchers. If so,
  tell the user this snapshot may under-report the real workload and should not be used alone to
  reduce resources.
- Whether a usage-report block is already present (look for the `Self-contained cgroup-based
  usage report` marker, **or** the old `seff "$SLURM_JOB_ID"` pattern that this skill used to
  insert) — replace in place rather than appending a duplicate.

### 2. Insert the report block at the end of the script

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

### 3. If the old `seff`-in-script block is found

The previous version of this skill inserted `seff "$SLURM_JOB_ID"` in-script. That pattern is
**broken** (sacct unfinalized while the job is still running). Replace any such block with the
cgroup snapshot block above — do not leave both. Tell the user this changes the report from
final `seff` accounting to an inline CPU/memory snapshot.

### 4. Tell the user what changed

- Which script was edited
- The usage-report path (`logs/<job_name>_<jobid>_usage.txt`)
- That **CPU + memory** are read from the report block's cgroup without waiting for `sacct`
- That `srun` / multi-step jobs may be under-reported by this inline snapshot
- That **GPU efficiency** is not in this report — `seff <jobid>` after the job exits is the
  source for that (cgroup does not track GPU)

## Editing Rules

- Scope edits to the report block; do not refactor unrelated job logic.
- Preserve existing comments and shell setup.
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
