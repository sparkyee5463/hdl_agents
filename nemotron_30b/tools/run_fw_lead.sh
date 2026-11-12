#!/bin/bash
# Run fw_lead non-interactively, resuming the session with "continue" when
# the model stops with no final report (max 3 times).
#
#   usage: PROJECT_ROOT=<project root> nemotron_30b/tools/run_fw_lead.sh <log_prefix> <prompt_file> [session_id]
#   writes <log_prefix>.jsonl (opencode events), .err, .meta, .autocontinue
#
# XDG_CONFIG_HOME points opencode at nemotron_30b/opencode/opencode.json only,
# so your global opencode config is not mixed in.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
: "${PROJECT_ROOT:?set PROJECT_ROOT to the project the agents work in}"
export XDG_CONFIG_HOME=$here
prefix=$(realpath -m "$1"); pf=$(realpath "$2"); sid=${3:-}
[ -s "$pf" ] || { echo "missing or empty prompt file $pf"; exit 2; }
mkdir -p "$(dirname "$prefix")"
cd "$PROJECT_ROOT"
out=$prefix.jsonl; : > "$out"
start=$(date +%s)
msg="$(cat "$pf")"
for attempt in 0 1 2 3; do
  OPENCODE_EXPERIMENTAL_OUTPUT_TOKEN_MAX=${OUTPUT_TOKEN_MAX:-32000} \
    opencode run --agent fw_lead --auto --format json ${sid:+--session $sid} "$msg" \
    < /dev/null >> "$out" 2>> "$prefix.err"
  rc=$?
  read -r sid empty < <(python3 - "$out" <<'PY'
import json, sys
sid = ''; last_text = ''; after_tool = True
for line in open(sys.argv[1]):
    try:
        e = json.loads(line)
    except ValueError:
        continue
    sid = e.get('sessionID', sid)
    p = e.get('part', {})
    if p.get('type') == 'tool':
        after_tool = True; last_text = ''
    elif p.get('type') == 'text' and p.get('text', '').strip():
        last_text = p['text']; after_tool = False
print(sid or '-', 1 if (after_tool or len(last_text) < 200) else 0)
PY
)
  [ "$empty" = "1" ] && [ $rc -eq 0 ] || break
  echo "$(date +%T) empty stop -> auto-continue #$((attempt+1)) session $sid" >> "$prefix.autocontinue"
  msg="You stopped without a final report. Read the IP's STATE.md and git log, then continue from where you left off. Do not stop until the final report the original task asked for."
done
echo "rc=$rc secs=$(( $(date +%s)-start )) session=$sid" > "$prefix.meta"
