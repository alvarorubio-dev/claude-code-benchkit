#!/usr/bin/env bash
# ============================================================================
#  run-bench.sh — Benchmark A (deterministic): how much test output enters
#  Claude's context with no filter, with the official docs filter and with the
#  pack filter. Three public repos pinned to exact commits, so anyone can
#  reproduce the numbers.
#
#  Requires: git, node + npm, python 3.10+, go 1.21+. ~5 minutes.
#  Windows: run it from Git Bash.
#  Usage:    ./run-bench.sh [workdir]      (default: ./bench-work)
#  Output:   results.csv + results.md in the current folder.
#
#  Runs each repo's own test suite twice: as published (green) and with ONE
#  failing test added (red). Nothing is pushed anywhere.
# ============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-filters.sh
. "$HERE/lib-filters.sh"
WORK="${1:-$PWD/bench-work}"
OUT="$PWD"
mkdir -p "$WORK/logs"

for bin in git npm node go; do
  command -v "$bin" >/dev/null 2>&1 || { echo "Missing: $bin" >&2; exit 1; }
done
# Pick the first Python that actually runs (Windows can have broken
# python3 shims pointing to removed installs).
PY=""
for cand in python3 python "py -3"; do
  # shellcheck disable=SC2086
  if $cand -c 'import sys; assert sys.version_info >= (3, 10)' >/dev/null 2>&1; then PY="$cand"; break; fi
done
[ -n "$PY" ] || { echo "Missing: a working Python 3.10+ (tried python3, python, py -3)" >&2; exit 1; }
echo "Using Python: $PY"
# Venv interpreter: Scripts/ on Windows, bin/ elsewhere (resolved inside the repo).
VPY='$(ls .venv/Scripts/python.exe .venv/bin/python 2>/dev/null | head -1)'

# name | repo | pinned commit | install | test commands (;; separated)
REPOS=(
  "express|https://github.com/expressjs/express.git|1c6f1b0fe4000977b9a7b4f34097e4d527dd9824|npm install --no-audit --no-fund|npm test"
  "flask|https://github.com/pallets/flask.git|49943b5a94413a530761350f04e896f76e8d620e|PYBIN -m venv .venv && VPY -m pip install -q -e . pytest asgiref python-dotenv|VPY -m pytest;;VPY -m pytest -v"
  "cobra|https://github.com/spf13/cobra.git|adbc8813901bba65827259daa8e22ff94ec1f30e|go mod download|go test ./...;;go test -v ./..."
)

inject_failure() { # inject_failure <name> <dir>
  case "$1" in
    express) printf "var assert = require('node:assert')\ndescribe('bench', function () {\n  it('fails on purpose', function () { assert.strictEqual(1 + 1, 3) })\n})\n" > "$2/test/zz-bench-fail.js" ;;
    flask)   printf "def test_fails_on_purpose():\n    assert 1 + 1 == 3\n" > "$2/tests/test_zz_bench_fail.py" ;;
    cobra)   printf "package cobra\n\nimport \"testing\"\n\nfunc TestBenchFailsOnPurpose(t *testing.T) {\n\tif 1+1 != 3 {\n\t\tt.Fatalf(\"expected 3, got %%d\", 1+1)\n\t}\n}\n" > "$2/zz_bench_fail_test.go" ;;
  esac
}
remove_failure() { rm -f "$2/test/zz-bench-fail.js" "$2/tests/test_zz_bench_fail.py" "$2/zz_bench_fail_test.go"; }

echo "repo,command,state,exit,lines_raw,tokens_raw,tokens_official,tokens_pack,saving_official_pct,saving_pack_pct,official_shows_result" > "$OUT/results.csv"

for entry in "${REPOS[@]}"; do
  IFS='|' read -r name url sha install cmds <<<"$entry"
  install="${install//PYBIN/$PY}"; install="${install//VPY/$VPY}"; cmds="${cmds//VPY/$VPY}"
  dir="$WORK/$name"
  echo "== $name @ ${sha:0:7}"
  if [ ! -d "$dir/.git" ]; then
    git init -q "$dir" && git -C "$dir" remote add origin "$url"
  fi
  git -C "$dir" fetch -q --depth 1 origin "$sha" && git -C "$dir" checkout -q FETCH_HEAD || { echo "  fetch failed" >&2; continue; }
  (cd "$dir" && bash -c "$install") > "$WORK/logs/$name-install.log" 2>&1 || { echo "  install failed, see logs/$name-install.log" >&2; continue; }

  IFS=';;' read -r -a cmd_list <<<"${cmds//;;/;}"
  for cmd in "${cmd_list[@]}"; do
    [ -z "$cmd" ] && continue
    for state in green red; do
      remove_failure "$name" "$dir"
      [ "$state" = red ] && inject_failure "$name" "$dir"
      label="${cmd//$VPY/python}"
      slug="$name-$(echo "$label" | tr -c 'a-zA-Z0-9' '_')-$state"
      log="$WORK/logs/$slug.log"
      (cd "$dir" && bash -c "$cmd") > "$log" 2>&1; rc=$?
      filter_official "$log" > "$WORK/logs/$slug.official.txt"
      filter_pack "$log" "$rc" > "$WORK/logs/$slug.pack.txt"
      raw=$(est_tokens "$log"); off=$(est_tokens "$WORK/logs/$slug.official.txt"); pk=$(est_tokens "$WORK/logs/$slug.pack.txt")
      s_off=$(( raw > 0 ? 100 - 100 * off / raw : 0 )); s_pk=$(( raw > 0 ? 100 - 100 * pk / raw : 0 ))
      shows=no; [ "$state" = green ] && [ -n "$(tr -d '[:space:]' < "$WORK/logs/$slug.official.txt")" ] && shows=yes
      [ "$state" = red ] && grep -qiE 'fail|error' "$WORK/logs/$slug.official.txt" && shows=yes
      echo "$name,\"$label\",$state,$rc,$(wc -l < "$log" | tr -d ' '),$raw,$off,$pk,$s_off,$s_pk,$shows" >> "$OUT/results.csv"
      printf "  %-22s %-5s exit=%-3s raw=%6s tok  official=%5s  pack=%5s\n" "$label" "$state" "$rc" "$raw" "$off" "$pk"
    done
  done
  remove_failure "$name" "$dir"
done

PYTHONIOENCODING=utf-8 $PY - "$OUT/results.csv" "$OUT/results.md" <<'PY'
import csv, sys, datetime
rows = list(csv.DictReader(open(sys.argv[1], encoding="utf-8")))
with open(sys.argv[2], "w", encoding="utf-8") as f:
    f.write(f"# Benchmark A — test output in context ({datetime.date.today()})\n\n")
    f.write("Tokens estimated at ~4 characters per token.\n\n")
    f.write("| Repo | Command | State | Exit | Raw tokens | Official filter | Pack filter | Official shows result? |\n|---|---|---|---|---|---|---|---|\n")
    for r in rows:
        f.write(f"| {r['repo']} | `{r['command']}` | {r['state']} | {r['exit']} | {int(r['tokens_raw']):,} | {int(r['tokens_official']):,} (−{r['saving_official_pct']}%) | {int(r['tokens_pack']):,} (−{r['saving_pack_pct']}%) | {r['official_shows_result']} |\n")
print(f"Wrote {sys.argv[2]}")
PY
echo "Done: results.csv, results.md · logs in $WORK/logs"
