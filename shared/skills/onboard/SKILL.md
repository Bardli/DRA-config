---
name: onboard
description: One-time setup to get a lab member onto Alliance Canada (DRAC) with this shared Claude Code config. Sets up key-based SSH with ControlMaster reuse (one interactive Duo login, then passwordless), detects the Slurm allocation account, writes saved values, and runs setup.sh. Use when first configuring a machine.
allowed-tools: Bash(git *), Bash(hostname *), Bash(whoami), Bash(which *), Bash(cat *), Bash(ls *), Bash(mkdir *), Bash(chmod *), Bash(ssh-keygen *), Bash(ssh *), Bash(sinfo *), Bash(sshare *), Bash(sacctmgr *), Bash(*/setup.sh *), Bash(${CLAUDE_SKILL_DIR}/scripts/*), Read, Edit, Write
---

# Alliance Canada Setup — Onboarding (one-time)

You are helping a lab member do the **one-time** setup that connects this Claude Code
config to an Alliance Canada (DRAC / CCDB) cluster — Fir by default. Walk them through it
interactively; be concise. Greet with **"Welcome onboard, Foreseer!"** then explain: this
sets up key-based SSH with ControlMaster reuse (one interactive Duo login, then passwordless),
records the user's Slurm allocation account, and installs the lab config so Claude understands
the cluster.

Two things are distinct and both needed: **(A) SSH login access** (username + a registered
SSH key) and **(B) a Slurm allocation account** (the `--account=` value, e.g. `def-<pi>_gpu`).

## Pre-flight

1. `ls -ld ~/.claude 2>/dev/null` — if missing, ask the user to run `claude` once first.
2. Confirm the repo is cloned: `ls -d ~/DRA-config 2>/dev/null`. If not:
   ```bash
   git clone https://github.com/ATATC/DRA-config.git ~/DRA-config
   ```
3. `which jq` — needed for Claude's statusline.

## Step A — SSH access (one-time; skip if already on a cluster login node)

If `hostname -f` already ends in `.alliancecan.ca`, you are on the cluster — skip to Step B.
Otherwise set up key-based access from this local machine. **Done once per machine** — `connect`
reuses it afterward and never re-uploads.

**Read first — the agent cannot log in for the user.** Fir requires **Duo 2FA on every fresh
login, even with a registered key** (the key is only factor 1). The agent has no tty / no
ssh-askpass, so the **user** runs the interactive login; the agent only writes files and reuses
the connection afterward. Full detail (existing/encrypted keys, key-format conversion, Windows,
agent-driven Mode B, troubleshooting) is in `references/fir-ssh-setup.md` — read it if anything
below fails.

1. **Find or create a key.** Check for an existing one first (the user may already have a key in
   any format — see the reference):
   ```bash
   ls ~/.ssh/*.pub 2>/dev/null
   ```
   If none, create one:
   ```bash
   ssh-keygen -t ed25519 -C "<user-email-or-label>" -f ~/.ssh/id_ed25519
   ```
2. **Register the PUBLIC key with CCDB** (one-time MFA on the website):
   ```bash
   cat ~/.ssh/id_ed25519.pub   # or the user's existing <key>.pub
   ```
   Have the user paste that line at <https://ccdb.alliancecan.ca/ssh_authorized_keys>
   (CCDB → Manage SSH Keys). **Propagation takes ~10–30 min** — failing right after upload is
   normal. Never handle the user's password or Duo passcode in chat.
3. **Add a `~/.ssh/config` host entry** (ask for the Alliance username if it differs from local
   `whoami`; use the user's key path if not `id_ed25519`):
   ```text
   Host fir.alliancecan.ca
       User <ccdb_username>
       IdentityFile ~/.ssh/id_ed25519
       IdentitiesOnly yes
       AddKeysToAgent yes
       ServerAliveInterval 60
       ControlMaster auto
       ControlPath ~/.ssh/cm-%r@%h:%p
       ControlPersist 8h
   ```
   ControlMaster is **essential, not optional**: it is the only path to passwordless reuse, because
   Duo is required on every fresh login. (Windows has no multiplexing — see the reference.)
   ```bash
   chmod 600 ~/.ssh/config
   ```
4. **First connection — default Mode B.** Run `/connect`: the agent brings up the ControlMaster
   socket itself and you just approve the Duo push on your phone (the 8h socket then makes reuse
   passwordless). If the key has a passphrase not in `ssh-agent`, `/connect` is fail-loud and falls
   back to **Mode A** — you run the login yourself; in Claude Code:
   ```
   ! ssh fir.alliancecan.ca "hostname -f && whoami"
   ```
   (enter the passphrase, pick `1` at the Duo menu, approve the push).
5. **Verify (agent).** Once the user reports success, reuse the socket:
   ```bash
   ssh -O check fir.alliancecan.ca          # "Master running" = socket live
   ssh fir.alliancecan.ca "hostname -f && whoami"
   ```
   - `Permission denied (publickey)` **before** any Duo prompt = real key problem (not propagated,
     or local/CCDB keys not a pair) → see the reference's troubleshooting.
   - Reaching the Duo prompt = the key works; that's normal 2FA — have the user complete it in their
     Mode A login above, not a failure to debug.

## Step B — Detect the Slurm allocation account

Run on the cluster (directly if on a login node, else over the SSH from Step A). Don't make the
user look things up — run it yourself:

```bash
ssh fir.alliancecan.ca "whoami; sshare -U -l --parsable2 | head"
```

Pick the best GPU account with the bundled helper (ranks by FairShare, prefers RRG/RPP):

```bash
ssh fir.alliancecan.ca "bash -s" < ${CLAUDE_SKILL_DIR}/../ccdb-clusters/scripts/pick-gpu-account.sh
```

(or run `pick-gpu-account.sh` directly when on the cluster). Alliance accounts look like
`def-<pi>_gpu`, `rrg-<pi>_gpu` (RAC-allocated), `rpp-<pi>`. Use `def-<pi>_cpu` for CPU jobs.

## Step C — Confirm and save

Show a short, plain-language summary: username, cluster (Fir), and the GPU account you'll
record. After the user confirms, write `~/DRA-config/build/.env.local` with the Fir values:

```bash
# Lab Claude Config - saved template variables
FIR_USERNAME=<ccdb_username>
FIR_ACCOUNT=<def-or-rrg account>
FIR_GPU_TYPE=h100
```

## Step D — Run setup

```bash
cd ~/DRA-config && ./setup.sh --modules fir --non-interactive
```

(Add `--targets claude,codex` if configuring Codex too.)

## Post-setup

1. Read and briefly summarize `~/.claude/CLAUDE.md` so the user sees what was installed.
2. Ask if they want personal notes appended **below** the `<!-- END: lab-config -->` marker
   (e.g. project paths, framework preferences). Their content outside the markers is never
   touched by `setup.sh`.
3. Mention: `/slurm-status` checks cluster availability; `/connect` re-establishes the SSH
   path in later sessions (no re-upload needed); update with
   `cd ~/DRA-config && git pull && ./setup.sh --modules fir`.

## If setup fails

Read the error and help debug. Common issues: missing `jq`, key not yet propagated, wrong
account name, `~/.claude` missing. `setup.sh` is idempotent — safe to re-run.
