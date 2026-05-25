#!/bin/bash
# Pretty-print the user's LevelFS across all their accounts, sorted best-first.
# Use this before every `sbatch` to gauge which account will queue fastest.
# Works on any Alliance Canada cluster.
#
# Column indices are detected from the header — sshare's --parsable2 column
# order has shifted between SLURM versions, so positional ($9/$6) parsing is
# fragile. (pick-gpu-account.sh does the same dynamic detection.)

set -euo pipefail

SSHARE_OUT=$(sshare -U -l --parsable2 2>/dev/null)
HEADER=$(echo "$SSHARE_OUT" | head -1)

ACC_COL=$(echo "$HEADER" | awk -F'|' '{ for(i=1;i<=NF;i++) if($i ~ /^Account$/)      print i }')
LFS_COL=$(echo "$HEADER" | awk -F'|' '{ for(i=1;i<=NF;i++) if($i ~ /^LevelFS$/)      print i }')
EU_COL=$(echo  "$HEADER" | awk -F'|' '{ for(i=1;i<=NF;i++) if($i ~ /^EffectvUsage$/) print i }')

if [ -z "${ACC_COL:-}" ] || [ -z "${LFS_COL:-}" ] || [ -z "${EU_COL:-}" ]; then
    echo "ERROR: could not locate Account/LevelFS/EffectvUsage columns in 'sshare -U -l' output" >&2
    exit 1
fi

printf "%-22s %-10s %-12s %s\n" "Account" "LevelFS" "EffUsage" "Verdict"
printf "%-22s %-10s %-12s %s\n" "-------" "-------" "--------" "-------"

echo "$SSHARE_OUT" \
  | tail -n +2 \
  | awk -F'|' -v a="$ACC_COL" -v l="$LFS_COL" -v e="$EU_COL" '$a != "" {
      verdict = ($l+0 > 1) ? "OK — submit here" : "Low — expect queue"
      printf "%-22s %-10.3f %-12.3f %s\n", $a, $l, $e, verdict
    }' \
  | sort -k2 -rn
