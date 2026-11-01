#!/usr/bin/env bash
# run-filtered.sh "<test command>"
# Runs the command, saves the full output to a log, prints only what Claude
# needs (failures, summary, exit code, log path) and keeps the exit code.
set -u
cmd="$1"
dir="${TMPDIR:-/tmp}/claude-test-logs"
mkdir -p "$dir"
log="$dir/$(date +%Y%m%d-%H%M%S)-$$.log"
bash -c "$cmd" > "$log" 2>&1
rc=$?
# shellcheck source=lib-filters.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib-filters.sh"
filter_pack "$log" "$rc"
exit "$rc"
