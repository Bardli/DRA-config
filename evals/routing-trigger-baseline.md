# Routing-Trigger Eval — Baseline Run (2026-05-25)

Eval set: `evals/routing-trigger.json` (18 cases). Run via a fresh `general-purpose` subagent
that received only the 9 skill descriptions + the 18 queries, with strict instructions to route
on description text alone. No tool execution. Method matches the official "Claude A writes for
Claude B" pattern (`anthropic-best-practices.md` L758).

## Score: 18/18 routed, 17 clean, 1 surfaces a real description gap

| Case | Query | Expected | Picked | Conf. | Verdict |
|---|---|---|---|---|---|
| P1 | first time configuring DRA-config on my laptop | onboard | onboard | high | ✅ |
| P2 | laptop, need to run sinfo, set up the SSH path | connect | connect | high | ✅ |
| P3 | what GPUs are currently free on fir | slurm-status | slurm-status | high | ✅ |
| P4 | write sbatch for single-GPU h100 fine-tune | slurm-job | slurm-job | high | ✅ |
| P5 | modify training script to print seff at the end | slurm-seff-report | slurm-seff-report | high | ✅ |
| P6 | submit configs/lora_r16.yaml as tracked experiment | submit-experiment | submit-experiment | high | ✅ |
| P7 | job 41290895 failed with exit code 1 | slurm-debug | slurm-debug | high | ✅ |
| P8 | collect results from finished experiments | harvest | harvest | high | ✅ |
| D1 | `/harvest --auto` | harvest, no-prompt | harvest, "would proceed without asking" | high | ✅ |
| D2 | `/harvest` | harvest, ask | harvest, "would ask" | high | ✅ |
| D3 | just registered SSH key, ssh still fails | onboard (propagation) | onboard | medium | ✅ |
| D4 | 8h ControlMaster socket expired, reconnect | connect (re-warm) | connect | high | ✅ |
| D5 | submit this script | null / ask | **slurm-job** (low), runner-up submit-experiment | low | ⚠️ see below |
| D6 | what GPU profile should I request given load | slurm-status | slurm-status | medium | ✅ |
| D7 | quick fine-tune as a one-off, not tracked | slurm-job | slurm-job | medium | ✅ |
| N1 | parse a CSV in Python | null | null | high | ✅ |
| N2 | capital of France | null | null | high | ✅ |
| N3 | review this code change | null | null | high | ✅ |

## D5 — the one real finding

Subagent reasoned: *"'submit this script' could be plain sbatch, not tracked experiment"* and
picked **slurm-job**, runner-up **submit-experiment**. The pick is wrong in a subtle way:
**`slurm-job` does not actually submit** — its description is *"Create or modify an sbatch job
script…"*. Its body merely tells the user to run `sbatch` themselves. So a query containing the
verb *submit* shouldn't route to `slurm-job` at all.

Description gap: `slurm-job` doesn't disclose that it does NOT submit. Fix applied in the same
commit as this baseline: append a clarifier to `slurm-job`'s description so the verb match for
"submit" cleanly favours `submit-experiment`.

## Re-running

Open a fresh Claude Code (or Codex) session. For each `evals/routing-trigger.json` case, either
paste the query as a user prompt and observe which skill the model invokes, or dispatch a
`general-purpose` subagent with the skill descriptions + queries (this run used the latter).
Compare against `expect` / `expect_behavior` and investigate any failures by tightening the
responsible skill's description.
