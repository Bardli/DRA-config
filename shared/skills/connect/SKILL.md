---
name: connect
description: Decide whether cluster work runs locally or over SSH, and establish/verify the SSH path to an Alliance Canada cluster (Fir). Assumes the one-time key setup was done by /onboard. Use when you need to run Slurm commands but may be on a laptop.
allowed-tools: Bash(ssh *), Bash(hostname *), Bash(whoami), Bash(grep *), Bash(test *), Bash(ls *), Bash(sinfo *), Bash(${CLAUDE_SKILL_DIR}/scripts/*), Read
---

# SSH Connect (Alliance Canada)

Decide whether cluster work should run locally on this host or remotely over SSH, and make sure
the SSH path is live. The **one-time** key setup (generate key, upload the public key to CCDB,
write `~/.ssh/config`) is done by the `onboard` skill — this skill only **reuses** it and never
re-uploads anything.

## Step 1: Detect the current environment

```bash
hostname -f
whoami
```

- If the hostname ends in `.alliancecan.ca` (e.g. `fir.alliancecan.ca` — a login node), you are
  **on the cluster**. Run Slurm commands **locally** here; do a quick check and stop:
  ```bash
  hostname -f && whoami && sinfo --version 2>&1
  ```
- Otherwise treat this as a **local machine / laptop**: Fir work runs **remotely** (Step 2).

## Step 2: Establish / verify the remote path (local machine -> Fir)

Access is key-based through the `fir.alliancecan.ca` host in `~/.ssh/config`. Confirm it exists:

```bash
grep -qE "^Host[[:space:]]+fir.alliancecan.ca" ~/.ssh/config && echo "host OK" || echo "host MISSING"
```

**If MISSING** → the one-time setup hasn't been done. Stop and tell the user to run `/onboard`
(generates/uploads the key, writes the host entry). Don't generate keys or collect passwords/Duo here.

**If host OK**, check the ControlMaster socket — this is the key step. Fir requires **Duo 2FA on
every fresh login**, so the agent can only connect when a warm socket already exists:

```bash
ssh -O check fir.alliancecan.ca 2>&1   # "Master running (pid=...)" = socket live
```

- **Socket live** → reuse it directly (no prompt):
  ```bash
  ssh fir.alliancecan.ca "hostname -f && whoami && sinfo --version 2>&1"
  ```
- **No master / socket expired** (ControlPersist elapsed, or first connect this session) → the
  agent has no tty for the passphrase/Duo, so default to **Mode B** (agent-driven): bring the
  socket up yourself and have the user approve the Duo push on their phone. Tell the user a push
  is coming, then run:
  ```bash
  ${CLAUDE_SKILL_DIR}/scripts/warm-socket.sh fir.alliancecan.ca
  ```
  The script is **fail-loud**: it only succeeds once the master socket truly exists. If it exits
  non-zero (the key needs a passphrase not in `ssh-agent`, or Duo timed out), fall back to
  **Mode A** — have the user run it themselves; in Claude Code:
  ```
  ! ssh fir.alliancecan.ca "hostname -f && whoami"
  ```
  Either way the 8h socket then lets the agent reuse the connection. This is **not** an onboarding
  failure — only send the user to `/onboard` if the host entry is MISSING or the key itself is
  rejected (`Permission denied (publickey)` **before** any Duo prompt). For key/format problems
  see the onboard skill's `references/fir-ssh-setup.md`.

Once the socket is live, run all Fir Slurm control, file inspection, and submissions remotely:

```bash
ssh fir.alliancecan.ca "<command>"
```

## Wrap up

Summarize in one of these forms:

### On the cluster
```text
## Fir: Operate Locally
- [x] Current host is the Fir login node
- [x] Slurm commands run locally here
```

### Remote path established
```text
## Local Machine -> Fir: Connected
- [x] Key-based SSH via ~/.ssh/config
- [x] Remote shell + Slurm: OK
- [x] Fir commands wrapped in ssh
```

### Socket cold (already onboarded, just needs re-login)
```text
## Local Machine -> Fir: Re-warm needed
- [ ] ControlMaster socket expired — ran warm-socket.sh (Mode B); user approved the Duo push
- [x] Key + ~/.ssh/config already set up (no /onboard needed)
```

### Not set up yet
```text
## Local Machine -> Fir: Needs onboarding
- [ ] No ~/.ssh/config host entry, or key rejected — run /onboard first (one-time key upload to CCDB)
```
