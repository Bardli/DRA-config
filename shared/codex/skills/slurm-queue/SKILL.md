---
name: slurm-queue
description: Show the user's active, pending, and recent Slurm jobs with status, resource usage, and quick actions like cancel or check logs. Use when the user asks about their jobs, queue, or what's running on the cluster.
allowed-tools: Bash(squeue *), Bash(sacct *), Bash(scontrol *), Bash(scancel *), Bash(whoami), Bash(tail *), Read
---

# Slurm Job Queue

Show a clear, friendly overview of the user's current and recent Slurm jobs.

## Step 1 — Current jobs

```bash
squeue -u $(whoami) --format="%12i %25j %12P %10T %12M %12l %8D %6C %10m %25R %20V" --noheader 2>/dev/null
```

Shows: Job ID, Name, Partition, State, Elapsed, Time Limit, Nodes, CPUs, Memory, Reason/Nodelist, Submit Time.

GPU info for running jobs:

```bash
squeue -u $(whoami) --format="%12i %20b" --noheader 2>/dev/null
```

## Step 2 — Recent completed / failed (last 2 days)

```bash
sacct -u $(whoami) --starttime=now-2days --format=JobID%15,JobName%25,Partition%12,State%15,ExitCode%8,Elapsed%12,MaxRSS%12,End%20 --noheader 2>/dev/null | grep -v "\.batch\|\.extern\|\.0" | tail -15
```

## Step 3 — Present

### Active jobs

| Job ID | Name | Partition | GPUs | State | Elapsed / Limit | Memory | Node(s) |
|---|---|---|---|---|---|---|---|

For each: flag **Running** jobs at >80% of time limit (timeout risk); explain **Pending** reasons in plain language (`Priority` → "waiting in queue"; `QOSGrpMemLimit`/`AssocGrpMemLimit` → group cap hit, show who is using what):

```bash
squeue -A <account> --format="%12i %10u %12P %10m %8T %12M" --noheader 2>/dev/null
```

### Recent (last 2 days)

| Job ID | Name | State | Exit Code | Runtime | Max Memory |
|---|---|---|---|---|---|

Highlight failures (exit 137 → OOM; TIMEOUT, OUT_OF_MEMORY).

### Summary

A one-liner, e.g. "2 running, 1 pending (waiting for resources), 3 completed today" or
"No active jobs. 5 completed in the last 2 days (1 failed — use slurm-debug to investigate)".

## Step 4 — Offer relevant actions

- Pending → "Check resource availability? (slurm-status)"
- Near time limit → "Job X has used 90% — set up checkpointing?"
- Failed → "Job X failed (OOM) — diagnose? (slurm-debug)"
- Running → "Tail logs for any running job?"

**Cancellation:** if the user asks to cancel, confirm job id + name first, then `scancel <id>`.
Never cancel without confirmation.

For running-job logs, get the path with `scontrol show job <id> 2>/dev/null | grep -E "StdOut|StdErr"`, then `tail`.
