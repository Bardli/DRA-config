---
name: submit-experiment
description: Submit a SLURM experiment on Alliance Canada (Fir) with a per-run folder, a metadata.yaml single source of truth (status + git provenance + objective), and a config/script snapshot. Use when launching a tracked experiment.
argument-hint: "<job_type> <run_config_or_script> [purpose description]"
allowed-tools: Bash(sbatch *), Bash(squeue *), Bash(tail *), Bash(ssh *), Bash(git *), Bash(ls *), Bash(cat *), Bash(cp *), Bash(mkdir *), Bash(hostname *), Bash(date *), Read, Edit, Write, Glob, Grep
---

# Submit Experiment

Submit a SLURM job with a reproducible record. Each run gets its own folder containing a config
snapshot, the submit script, and a `metadata.yaml` that is the **single source of truth** for
status, git provenance, and the experiment's objective. Human-readable indexes are *derived*
from `metadata.yaml` (by `/harvest`), never the other way around.

## Arguments

- `$1` — job type (e.g. `sft`, `eval`, `pretrain` — project-defined).
- `$2` — run config or job-script path.
- Remaining text — free-form purpose.

If args are missing, ask. (This is an interactive assistant — asking is fine.)

## Step 0 — Discover project context

Read the project's `CLAUDE.md` and scan for: the submit script / `sbatch` entry, the config
directory (`configs/`, `runs/`, …), and the experiment root. Default experiment root is
`experiment/`. If it does not exist, this is a fresh project — create `experiment/` and an empty
`docs/experiments.md` (the derived index, written by `/harvest`).

## Step 1 — Read prior runs (naming + dedup)

```bash
ls experiment/*/metadata.yaml 2>/dev/null
```

Note the naming convention already in use and avoid collisions.

## Step 2 — Read the run config

Read `$2` and extract: task/model, key hyperparameters, and resource requests (GPU profile,
count, mem, time). For Fir, the GPU is `--gpus-per-node=<gpu_type>:<count>` (full `h100` or a MIG
slice); see the `slurm-job` / `ccdb-clusters` skills.

## Step 3 — Local vs remote execution

```bash
hostname -f
```

- On the target cluster login node (`*.alliancecan.ca`) → submit **locally**.
- On a laptop / local machine → submit **remotely** over `ssh fir.alliancecan.ca "<command>"`
  (the `~/.ssh/config` host + key set up once by `/onboard`). If `ssh fir.alliancecan.ca` is not
  working, stop and have the user run `/connect` (or `/onboard` for first-time setup). Do not
  collect passwords / Duo in chat.

## Step 4 — Generate run code + tags

`run_code`: a unique, filesystem-safe identifier following the project's existing convention
(scan `experiment/*/`). Default `<job_type>-<descriptor>-<slug>` (lowercase, hyphens). `tags`: a
YAML list of job type + descriptor + purpose keywords.

## Step 5 — Capture git provenance (do NOT skip)

```bash
git rev-parse HEAD                 # full commit SHA
git status --porcelain            # empty => clean; non-empty => dirty
```

Record both. If the working tree is **dirty**, warn the user in Step 6 — the recorded commit
will not fully reproduce the run unless they commit first. (Record `dirty: true`; never claim a
clean provenance when it is not.)

## Step 6 — Confirm (the gate)

Show: `run_code`, tags, cluster, execution mode, account, GPU/resources, the objective, the
decision rule, and a **⚠ dirty working tree** warning if applicable. Wait for explicit user
confirmation before submitting. This confirmation is the safety gate (the skill stays
model-invocable by design — the gate, not metadata, prevents unwanted submits).

## Step 7 — Create the run folder + write metadata.yaml

```bash
RUN_DIR="experiment/<run_code>"
mkdir -p "$RUN_DIR"
cp "$2" "$RUN_DIR/config.yaml"            # snapshot the config
cp "<job_script>" "$RUN_DIR/slurm.sh"     # snapshot the submit script (if separate)
```

Write `$RUN_DIR/metadata.yaml` (the SSOT):

```yaml
run_code: <run_code>
status: submitted          # submitted|running|completed|failed|timeout|cancelled|oom
tags: [<job_type>, <descriptor>, <keywords>]
parent_run: null           # set to a prior run_code if this forks one (lineage)
cluster: fir
account: <account>
git:
  commit: <full SHA>
  dirty: true|false
slurm_job_ids: []          # filled in Step 8
started_at: <ISO 8601>
finished_at: null
objective:
  goal: <one-line goal>
  expected_result: { metric: <name>, value: <number>, rationale: <why> }
decision_rule: <what each outcome (above/at/below expected) will mean>
notes: <free text — purpose, key hyperparameters, anything for a human reader>
best_metric: { name: null, value: null }
```

## Step 8 — Submit

Local: `cd <project_root> && sbatch <job_script>`. Remote: sync code if the remote is a git
checkout (`git push`; `ssh fir.alliancecan.ca "cd <remote_path> && git pull"`), then
`ssh fir.alliancecan.ca "cd <remote_path> && sbatch <job_script>"`. Capture the job id from
`Submitted batch job <id>` and append it to `slurm_job_ids` in `metadata.yaml`.

## Step 9 — Report

Print `run_code`, job id, cluster, execution mode, `metadata.yaml` path, and the log-tail command
(`tail -f <RUN_DIR>/exp_log/logs/*.out`, or the `ssh fir.alliancecan.ca "tail …"` form when remote).

## Notes

- **`sbatch` runs on a login/submit node** — never a compute node, never locally for a cluster
  target (use the remote SSH path).
- **markdown is derived**: `/harvest` regenerates `docs/experiments.md` from all `metadata.yaml`
  files. Do not hand-edit the index as if it were the source.
- Optional discipline hook (reminds users to use `/submit-experiment` instead of bare `sbatch`)
  can live in `~/.claude/settings.local.json`; re-run `./setup.sh` after editing.
