#!/bin/bash
# Warm the ControlMaster socket to an Alliance Canada host using Mode B (agent-driven login).
# The user still approves the Duo push on their phone — that second factor is never bypassed.
#
# Fails LOUDLY if the key needs a passphrase we don't have, or Duo is not approved in time.
# On failure, fall back to Mode A: the user runs `ssh <host>` themselves (with the `!` prefix
# in Claude Code, or in a separate terminal for Codex).
#
# Usage: warm-socket.sh <host>          # e.g. warm-socket.sh fir.alliancecan.ca
set -euo pipefail

HOST="${1:?usage: warm-socket.sh <host>}"

# Already warm? Reuse — nothing to do.
if ssh -O check "$HOST" 2>/dev/null; then
    echo "socket already live for $HOST"
    exit 0
fi

# Mode B askpass: answer the Duo menu with '1' (Duo Push). Return EMPTY for a passphrase prompt
# — if the key is encrypted and not in ssh-agent, auth fails cleanly. We never guess a passphrase.
ASKPASS="$(mktemp)"
trap 'rm -f "$ASKPASS"' EXIT
cat > "$ASKPASS" <<'EOF'
#!/bin/bash
case "$1" in
  *assphrase*|*assword*) printf '%s\n' '' ;;   # no passphrase available -> fail cleanly (Mode A)
  *) printf '%s\n' '1' ;;                        # Duo menu -> option 1 (Duo Push)
esac
EOF
chmod 700 "$ASKPASS"

echo ">>> Bringing up master to $HOST — APPROVE THE DUO PUSH ON YOUR PHONE now."
if ! SSH_ASKPASS="$ASKPASS" SSH_ASKPASS_REQUIRE=force \
       timeout 90 ssh -o StrictHostKeyChecking=accept-new -fN "$HOST"; then
    echo "ERROR: Mode B login failed (key may need a passphrase not in ssh-agent, or Duo timed out)." >&2
    echo "Fall back to Mode A: run  ssh $HOST  yourself ('!' prefix in Claude Code; separate terminal in Codex)." >&2
    exit 1
fi

# Fail-loud: confirm the socket actually exists — do not trust the ssh exit code alone.
if ssh -O check "$HOST" 2>/dev/null; then
    echo "socket live for $HOST"
    exit 0
fi
echo "ERROR: ssh reported success but no master socket exists for $HOST." >&2
exit 1
