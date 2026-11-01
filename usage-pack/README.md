# usage-pack 0.1.0 (Claude Code plugin)

Keeps test-runner output out of Claude's context. When Claude runs `npm test`, `pytest`, `go test`, `cargo test`, `vitest`, `jest` or `mocha`, the hook routes the command through `scripts/run-filtered.sh`:

- **green run:** Claude sees the runner's last 10 lines (the summary) and the exit code;
- **red run:** Claude sees the failure blocks, the summary and the exit code;
- **short output (≤ 40 lines):** passed through untouched;
- **always:** the full log is saved under `$TMPDIR/claude-test-logs/` and its path is printed, so nothing is lost.

**Status: experiment, not recommended as a token saver.** It cuts a raw run from 10,000–18,000 tokens to 90–684 (Benchmark A), but in real sessions Claude already ran tests with `| tail`, so the hook had nothing to filter (see the repo README).

## Install

```bash
claude --plugin-dir /path/to/usage-pack        # one session
```

## Behaviour you can rely on

- The rewritten command is plain text: permission rules and auto mode see exactly what runs.
- Commands that already pipe or redirect (`| tail`, `> file`) and `--watch` runs are left alone.
- Fail-open: if the hook errors, the original command runs unchanged.
- Off switch: `USAGE_PACK_OFF=1`.
- Needs `node` and `bash` (Git Bash on Windows).

## Tests

```bash
tests/run-tests.sh      # 30 checks, fake runners only
```
