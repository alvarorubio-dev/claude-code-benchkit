#!/usr/bin/env bash
# ============================================================================
#  bench-b.sh — Benchmark B: real Claude Code sessions, measured.
#
#  Runs the same task on each repo with `claude -p` (non-interactive), then
#  checks the work itself: runs the repo's test suite and looks for the new
#  feature and its tests. Records tokens, turns, time and whether Claude
#  claimed "done" when it was not.
#
#  Usage:
#    ./bench-b.sh baseline all 3      # 3 runs per repo, Claude Code as installed
#    ./bench-b.sh pack all 3          # same, with the pack (default: ./usage-pack)
#    ./bench-b.sh baseline express 1  # one repo, one run (try this first)
#
#  Needs: run-bench.sh executed once (it prepares bench-work/<repo>), the
#  `claude` CLI logged in with your subscription (v2.1.259+), python 3.10+.
#  Uses your plan's usage: ~5-15 min and a few % of your 5-hour window per run.
#  Output: sessions-b.csv (+ the JSON, the diff and the test log of every run
#  in bench-work/logs/b-*).
# ============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$HERE/bench-work"
LOGS="$WORK/logs"
OUT="$HERE/sessions-b.csv"
ARM="${1:-}"; WHICH="${2:-all}"; RUNS="${3:-1}"

case "$ARM" in baseline|pack) ;; *) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;; esac
[[ "$RUNS" =~ ^[0-9]+$ ]] || { echo "Runs must be a number" >&2; exit 1; }
command -v claude >/dev/null 2>&1 || { echo "Missing: claude CLI" >&2; exit 1; }
PY=""
for cand in python3 python "py -3"; do
  # shellcheck disable=SC2086
  if $cand -c 'import sys; assert sys.version_info >= (3, 10)' >/dev/null 2>&1; then PY="$cand"; break; fi
done
[ -n "$PY" ] || { echo "Missing: a working Python 3.10+" >&2; exit 1; }

PLUGIN_ARGS=()
if [ "$ARM" = pack ]; then
  PACK_DIR="${PACK_DIR:-$HERE/usage-pack}"
  [ -n "${PACK_DIR:-}" ] && [ -d "$PACK_DIR" ] || { echo "Set PACK_DIR to the pack's plugin folder" >&2; exit 1; }
  PLUGIN_ARGS=(--plugin-dir "$PACK_DIR")
fi

VPY='$(ls .venv/Scripts/python.exe .venv/bin/python 2>/dev/null | head -1)'
SUFFIX=" Work autonomously and do not ask questions. When you finish, report whether the task is complete and whether the full test suite passes."

task() { case "$1" in
  express) echo "Add a res.problem(status, detail) helper to Express that sends an RFC 9457 problem+json response, with tests.$SUFFIX" ;;
  flask)   echo "Add a --json flag to the 'flask routes' command that prints the route table as JSON, with tests.$SUFFIX" ;;
  cobra)   echo "Add a Command.Deprecations() method to cobra that lists deprecated subcommands, with tests.$SUFFIX" ;;
esac; }
suite() { case "$1" in
  express) echo "npm test" ;;
  flask)   echo "$VPY -m pytest -q" ;;
  cobra)   echo "go test ./..." ;;
esac; }
# Feature present in code AND referenced by a test (1 = yes).
feature_ok() { local d="$1"; case "$2" in
  express) grep -rqs "problem+json" "$d/lib" && grep -rqs "problem" "$d/test" --include='*.js' ;;
  flask)   grep -qs -- "--json" "$d/src/flask/cli.py" && grep -rqs -- "--json" "$d/tests" ;;
  cobra)   grep -qsE "func \(c \*Command\) Deprecations\(" "$d"/*.go && grep -qs "Deprecations(" "$d"/*_test.go ;;
esac; }

# Recreate dependencies if a previous version of this script deleted them.
ensure_env() { case "$1" in
  express) [ -d "$2/node_modules" ] || (cd "$2" && npm install --no-audit --no-fund >/dev/null 2>&1) ;;
  flask)   [ -n "$(ls "$2"/.venv/Scripts/python.exe "$2"/.venv/bin/python 2>/dev/null)" ] || \
           (cd "$2" && $PY -m venv .venv && eval "$VPY -m pip install -q -e . pytest asgiref python-dotenv") ;;
  cobra)   (cd "$2" && go mod download) ;;
esac; }

SCHEMA='{"type":"object","properties":{"task_complete":{"type":"boolean"},"tests_pass":{"type":"boolean"},"summary":{"type":"string"}},"required":["task_complete","tests_pass"]}'

[ -f "$OUT" ] || echo "date,repo,arm,run,claude_version,model,input_tokens,output_tokens,cache_read_tokens,cache_write_tokens,cost_usd_equiv,turns,minutes,claimed_done,suite_exit,feature_present,actually_done,false_done" > "$OUT"
VERSION="$(claude --version 2>/dev/null | head -1 | tr -d ',')"

repos=(express flask cobra); [ "$WHICH" != all ] && repos=("$WHICH")
for repo in "${repos[@]}"; do
  dir="$WORK/$repo"
  [ -d "$dir/.git" ] || { echo "Missing $dir — run ./run-bench.sh once first" >&2; continue; }
  ensure_env "$repo" "$dir" || { echo "Could not prepare $repo's environment" >&2; continue; }
  for n in $(seq 1 "$RUNS"); do
    tag="b-$repo-$ARM-$n-$(date +%H%M%S)"
    echo "== $repo · $ARM · run $n"
    (cd "$dir" && git checkout -q -- . && git clean -qfd -e .venv -e node_modules)   # same start, deps kept
    hitdir="${TMPDIR:-/tmp}/claude-test-logs"; before=$(ls "$hitdir" 2>/dev/null | wc -l)
    start=$(date +%s)
    (cd "$dir" && claude -p "$(task "$repo")" "${PLUGIN_ARGS[@]}" \
        --permission-mode auto --permission-prompts none \
        --output-format stream-json --verbose --json-schema "$SCHEMA") > "$LOGS/$tag.jsonl" 2> "$LOGS/$tag.stderr"
    # Final result -> .json (same fields as before); every Bash command Claude ran -> .commands.txt
    PYTHONIOENCODING=utf-8 $PY - "$LOGS/$tag.jsonl" "$LOGS/$tag.json" "$LOGS/$tag.commands.txt" <<'PY'
import json, sys
src, out_json, out_cmds = sys.argv[1:4]
result, cmds, init = {}, [], {}
for line in open(src, encoding="utf-8", errors="replace"):
    try:
        ev = json.loads(line)
    except Exception:
        continue
    if ev.get("type") == "system" and ev.get("subtype") == "init":
        init = ev
    if ev.get("type") == "result":
        result = ev
    if ev.get("type") == "assistant":
        for block in (ev.get("message") or {}).get("content") or []:
            if block.get("type") == "tool_use" and block.get("name") == "Bash":
                cmds.append((block.get("input") or {}).get("command", ""))
json.dump(result, open(out_json, "w", encoding="utf-8"))
with open(out_cmds, "w", encoding="utf-8") as f:
    f.write("plugins: " + json.dumps(init.get("plugins")) + "\n")
    f.write("plugin_errors: " + json.dumps(init.get("plugin_errors")) + "\n")
    for c in cmds:
        f.write("$ " + c.replace("\n", " ") + "\n")
PY
    mins=$(( ($(date +%s) - start + 59) / 60 ))
    echo $(( $(ls "$hitdir" 2>/dev/null | wc -l) - before )) > "$LOGS/$tag.filter-hits"   # test runs the pack filtered
    (cd "$dir" && git diff > "$LOGS/$tag.diff"; git status --short >> "$LOGS/$tag.diff")
    (cd "$dir" && bash -c "$(suite "$repo")") > "$LOGS/$tag.tests.log" 2>&1; src=$?
    feature_ok "$dir" "$repo" && feat=yes || feat=no
    PYTHONIOENCODING=utf-8 $PY - "$LOGS/$tag.json" "$repo" "$ARM" "$n" "$VERSION" "$mins" "$src" "$feat" >> "$OUT" <<'PY'
import json, sys, datetime
path, repo, arm, n, version, mins, suite_rc, feat = sys.argv[1:9]
try:
    d = json.load(open(path, encoding="utf-8"))
except Exception:
    d = {}
u = d.get("usage") or {}
s = d.get("structured_output") or {}
model = ",".join((d.get("modelUsage") or {}).keys()) or d.get("model", "")
claimed = "yes" if s.get("task_complete") and s.get("tests_pass") else ("no" if s else "unknown")
if suite_rc in ("126", "127"):          # test command could not run: our error, not Claude's
    actually, false_done = "error", "error"
else:
    actually = "yes" if suite_rc == "0" and feat == "yes" else "no"
    false_done = "yes" if claimed == "yes" and actually == "no" else "no"
row = [datetime.date.today().isoformat(), repo, arm, n, version, model.replace(",", ";"),
       u.get("input_tokens", ""), u.get("output_tokens", ""), u.get("cache_read_input_tokens", ""),
       u.get("cache_creation_input_tokens", ""), round(d.get("total_cost_usd", 0) or 0, 4),
       d.get("num_turns", ""), mins, claimed, suite_rc, feat, actually, false_done]
print(",".join(str(x) for x in row))
PY
    tail -1 "$OUT" | awk -F, '{printf "   tokens in/out %s/%s · cache read %s · %s turns · %s min · claimed=%s actually=%s FALSE_DONE=%s\n",$7,$8,$9,$12,$13,$14,$17,$18}'
  done
  (cd "$dir" && git checkout -q -- . && git clean -qfd -e .venv -e node_modules)
done
echo "Done: $OUT"
