#!/usr/bin/env bash
# Unit tests for lib-filters.sh using synthetic logs written here (no external
# code runs). Formats mimic mocha, go test and pytest output.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib-filters.sh
. "$DIR/lib-filters.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
check() { if eval "$2"; then PASS=$((PASS+1)); echo "  PASS $1"; else FAIL=$((FAIL+1)); echo "  FAIL $1"; fi; }
noise() { for i in $(seq 1 "$1"); do echo "  ✓ case $i works as expected with some padding text (2ms)"; done; }

# --- mocha -------------------------------------------------------------------
{ noise 400; echo ""; echo "  400 passing (1s)"; } > "$T/mocha-green.log"
{ noise 200; echo "  1) bench"; echo "       fails on purpose:"; echo ""
  echo "      AssertionError [ERR_ASSERTION]: Expected values to be strictly equal:"; echo ""; echo "2 !== 3"; echo ""
  echo "      at Context.<anonymous> (test/zz-bench-fail.js:3:12)"; noise 200
  echo "  399 passing (1s)"; echo "  1 failing"; } > "$T/mocha-red.log"
# --- go test (non-verbose): stdout noise containing "Error:" from passing tests
{ for i in $(seq 1 60); do echo "Error: unknown command \"x$i\" for \"root\""; echo "Run 'root --help' for usage."; done
  echo "--- FAIL: TestBenchFailsOnPurpose (0.00s)"; echo "    zz_bench_fail_test.go:7: expected 3, got 2"
  echo "FAIL"; printf 'FAIL\tgithub.com/spf13/cobra\t0.412s\n'; echo "FAIL"; } > "$T/go-red.log"
printf 'ok  \tgithub.com/spf13/cobra\t0.398s\n' > "$T/go-green.log"
# --- pytest ------------------------------------------------------------------
{ for i in $(seq 1 300); do echo "tests/test_basic.py::test_case_$i PASSED                       [ $((i/3))%]"; done
  echo "=================================== FAILURES ==================================="
  echo "___________________________ test_fails_on_purpose ____________________________"
  echo "    def test_fails_on_purpose():"; echo ">       assert 1 + 1 == 3"; echo "E       assert (1 + 1) == 3"
  echo "tests/test_zz_bench_fail.py:2: AssertionError"
  echo "=========================== short test summary info ============================"
  echo "FAILED tests/test_zz_bench_fail.py::test_fails_on_purpose - assert (1 + 1) == 3"
  echo "======================== 1 failed, 300 passed in 3.21s ========================="; } > "$T/pytest-red.log"

official_mocha_red="$(filter_official "$T/mocha-red.log")"
check "official filter misses mocha failures entirely" '[ -z "$official_mocha_red" ]'
check "official filter prints nothing on a green run" '[ -z "$(filter_official "$T/mocha-green.log")" ]'

p="$(filter_pack "$T/mocha-green.log" 0)"
check "mocha green: keeps summary" 'grep -q "400 passing" <<<"$p"'
check "mocha green: reports exit code" 'grep -q "exit=0" <<<"$p"'
p="$(filter_pack "$T/mocha-red.log" 1)"
check "mocha red: keeps assertion" 'grep -q "2 !== 3" <<<"$p"'
check "mocha red: keeps location" 'grep -q "zz-bench-fail.js:3:12" <<<"$p"'
check "mocha red: keeps failing count" 'grep -q "1 failing" <<<"$p"'
check "mocha red: points to full log" 'grep -q "full log" <<<"$p"'
check "mocha red: <10% of raw" '[ $(wc -c <<<"$p") -lt $(( $(wc -c < "$T/mocha-red.log") / 10 )) ]'

p="$(filter_pack "$T/go-green.log" 0)"
check "short log passes through untouched" '[ "$p" = "$(cat "$T/go-green.log")" ]'
p="$(filter_pack "$T/go-red.log" 1)"
check "go red: keeps failing test and line" 'grep -q "zz_bench_fail_test.go:7: expected 3, got 2" <<<"$p"'
check "go red: drops passing-test Error noise" '[ $(grep -c "unknown command" <<<"$p") -le 2 ]'
check "go red: <25% of raw" '[ $(wc -c <<<"$p") -lt $(( $(wc -c < "$T/go-red.log") / 4 )) ]'

p="$(filter_pack "$T/pytest-red.log" 1)"
check "pytest red: keeps E line" 'grep -q "E       assert (1 + 1) == 3" <<<"$p"'
check "pytest red: keeps FAILED summary" 'grep -q "^FAILED tests/test_zz_bench_fail.py" <<<"$p"'
check "pytest red: keeps counts" 'grep -q "1 failed, 300 passed" <<<"$p"'
check "pytest red: <10% of raw" '[ $(wc -c <<<"$p") -lt $(( $(wc -c < "$T/pytest-red.log") / 10 )) ]'

check "est_tokens ~ chars/4" '[ "$(est_tokens "$T/mocha-green.log")" -eq $(( $(wc -c < "$T/mocha-green.log") / 4 )) ]'

echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
