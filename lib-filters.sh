#!/usr/bin/env bash
# ============================================================================
#  lib-filters.sh — Output filters compared by the benchmark.
#  Each filter reads a saved test log ($1) and its exit code ($2) and prints
#  what Claude would see in its context.
# ============================================================================

# Pattern from the official Claude Code docs ("Manage costs"): keep failure
# lines with 5 lines of context, cap at 100 lines. On a green run it prints
# nothing; on runners that never print FAIL/ERROR (Mocha) it hides failures.
filter_official() {
  local log="$1"
  grep -A 5 -E '(FAIL|ERROR|error:)' "$log" | head -100
}

# Failure markers per runner. Deliberately NOT the bare word "Error": many
# suites print it from tests that pass (CLI usage errors, expected errors).
#   go test : "--- FAIL:", "FAIL<tab>pkg", "file_test.go:12:", "panic:"
#   mocha   : "  1) suite", "AssertionError", "N failing"
#   jest/vitest: "✕", "×", "FAIL  path"
#   pytest  : "FAILED path::test", "ERROR path", "E   assert ...", "___ test_x ___"
PACK_FAIL_RE='(^--- FAIL|^FAIL([[:space:]]|$)|_test\.go:[0-9]+:|^panic:|^ +[0-9]+\) |AssertionError|[0-9]+ failing|✕|×|^FAILED |^ERROR |^E +|^_{3,} .+ _{3,}$)'

# Pack filter (test-output-filter v1):
#   - short logs (<= 40 lines) pass through untouched: filtering would only add text;
#   - green: last 10 lines (the runner's summary) + exit code;
#   - red: failure blocks (runner-specific markers, 1 line before / 10 after),
#     capped at 120 lines, then the summary;
#   - always: exit code and the path of the full log, so nothing is lost.
filter_pack() {
  local log="$1" rc="$2" lines
  lines=$(wc -l < "$log" | tr -d ' ')
  if [ "$lines" -le 40 ]; then
    cat "$log"
    return
  fi
  if [ "$rc" -eq 0 ]; then
    tail -n 10 "$log"
  else
    grep -B 1 -A 10 -E "$PACK_FAIL_RE" "$log" | head -n 120
    echo "--- summary ---"
    tail -n 10 "$log"
  fi
  echo "[filtered: exit=$rc, full log $log, $lines lines]"
}

# Rough token estimate: ~4 characters per token for English text and code.
est_tokens() { echo $(( $(wc -c < "$1") / 4 )); }
