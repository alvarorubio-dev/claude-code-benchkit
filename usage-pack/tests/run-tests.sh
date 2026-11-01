#!/usr/bin/env bash
# Tests for usage-pack. Uses fake test runners written here; runs no external code.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/scripts/test-output-filter.mjs"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
check() { if eval "$2"; then PASS=$((PASS+1)); echo "  PASS $1"; else FAIL=$((FAIL+1)); echo "  FAIL $1"; fi; }
hook() { node -e 'console.log(JSON.stringify({tool_name:"Bash",tool_input:{command:process.argv[1],description:"x"}}))' "$1" | node "$HOOK"; }
newcmd() { hook "$1" | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>console.log(d?JSON.parse(d).hookSpecificOutput.updatedInput.command:""))'; }

echo "== rewrite decisions"
for c in "npm test" "npm run test" "pytest -q" "python -m pytest tests/" ".venv/Scripts/python.exe -m pytest" "go test ./..." "cd api && go test -v ./..." "npx vitest run" "cargo test" "npm test 2>&1" "go test ./... 2>&1"; do
  check "rewrites: $c" '[ -n "$(newcmd "$c")" ]'
done
for c in "ls -la" "npm install" "npm test | tail -20" "npm test 2>&1 | tail -50" "pytest > out.txt" "npx vitest --watch" "git commit -m 'npm test fix'x" "echo pytester"; do
  check "leaves alone: $c" '[ -z "$(newcmd "$c")" ]'
done
check "keeps other tool_input fields" 'hook "npm test" | grep -q "\"description\":\"x\""'
check "kill switch USAGE_PACK_OFF=1" '[ -z "$(USAGE_PACK_OFF=1 newcmd "npm test")" ]'
check "fail-open on invalid JSON" '[ -z "$(echo nope | node "$HOOK")" ]'
check "quotes survive" '[[ "$(newcmd "pytest -k '"'"'a and b'"'"'")" == *"'"'"'\\'"'"''"'"'"* ]]'

echo "== end to end with a fake runner"
mkdir -p "$T/bin"
cat > "$T/bin/pytest" <<'EOF'
#!/usr/bin/env bash
for i in $(seq 1 300); do echo "tests/test_x.py::test_$i PASSED"; done
if [ "${FAKE_FAIL:-0}" = 1 ]; then
  echo "___________________ test_broken ___________________"; echo "E       assert 2 == 3"
  echo "FAILED tests/test_x.py::test_broken - assert 2 == 3"; echo "=== 1 failed, 300 passed in 1.0s ==="; exit 1
fi
echo "=== 300 passed in 1.0s ==="
EOF
chmod +x "$T/bin/pytest"
cmd="$(newcmd "pytest -q")"
out="$(cd "$T" && PATH="$T/bin:$PATH" TMPDIR="$T" bash -c "$cmd")"; rc=$?
check "green: exit 0 kept" '[ $rc -eq 0 ]'
check "green: summary shown" 'grep -q "300 passed" <<<"$out"'
check "green: output is small" '[ $(wc -l <<<"$out") -le 12 ]'
out="$(cd "$T" && FAKE_FAIL=1 PATH="$T/bin:$PATH" TMPDIR="$T" bash -c "$cmd")"; rc=$?
check "red: exit 1 kept" '[ $rc -eq 1 ]'
check "red: failure shown" 'grep -q "E       assert 2 == 3" <<<"$out"'
check "red: FAILED line shown" 'grep -q "^FAILED tests/test_x.py::test_broken" <<<"$out"'
log="$(grep -o 'full log [^,]*' <<<"$out" | cut -d' ' -f3)"
check "red: full log saved with all 300 passes" '[ -f "$log" ] && [ $(grep -c PASSED "$log") -eq 300 ]'

echo "RESULT: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
