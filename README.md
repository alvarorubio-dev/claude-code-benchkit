# claude-code-benchkit

Reproducible benchmarks for two common Claude Code "fixes": filtering test output to save tokens, and stopping Claude from saying "done" when it isn't. Three public repos pinned to exact commits, scripted sessions, and a checker that runs the tests itself instead of trusting Claude's word.

**Result (2026-10-31, Claude Code 2.1.316, Sonnet 5.5):** neither problem showed up.

| Question | Finding |
|---|---|
| How big is raw test output? | 10,000–18,000 tokens per full run; a summary-keeping filter cuts the large runs by 93–99% ([results/benchmark-a.md](results/benchmark-a.md)) |
| Does Claude read it raw? | No. In 3 of 3 logged sessions it ran the suite with `\| tail -15` or `\| tail -30`; 586–938 characters reached its context ([results/commands/](results/commands/)) |
| Does Claude claim "done" when it isn't? | 0 of 13 valid sessions ([results/benchmark-b-sessions.csv](results/benchmark-b-sessions.csv)) |

Small study: one model, one machine, small well-scoped tasks. Read it as "did not show up here", not "does not exist". Rerun it and send your numbers, especially if they disagree.

## Repos

| Repo | Runner | Commit |
|---|---|---|
| [expressjs/express](https://github.com/expressjs/express) | `npm test` (Mocha) | `1c6f1b0fe4000977b9a7b4f34097e4d527dd9824` |
| [pallets/flask](https://github.com/pallets/flask) | `pytest` | `49943b5a94413a530761350f04e896f76e8d620e` |
| [spf13/cobra](https://github.com/spf13/cobra) | `go test ./...` | `adbc8813901bba65827259daa8e22ff94ec1f30e` |

## Run it

Needs git, node + npm, Python 3.10+, Go 1.21+, bash (Git Bash on Windows). Benchmark B also needs the `claude` CLI (v2.1.259+) logged in; it uses your plan.

```bash
tests/test-filters.sh            # 18 checks of the filters, synthetic logs
./run-bench.sh                   # Benchmark A: output size, ~5 min, no Claude needed
./bench-b.sh baseline all 3      # Benchmark B: 9 real sessions as installed
./bench-b.sh pack all 3          # same, with usage-pack/ loaded via --plugin-dir
```

**Benchmark A** runs each suite green and with one failing test added, and compares raw output, the example filter from the [Claude Code cost docs](https://code.claude.com/docs/en/costs) and the filter in `lib-filters.sh`.

**Benchmark B** runs one task per repo with `claude -p --permission-mode auto`, asks Claude to report completion in a JSON schema, then runs the full suite and greps for the new code and its test. Every session leaves its JSON stream, the list of Bash commands, the diff and the test log in `bench-work/logs/`.

## What's in here

| Path | What |
|---|---|
| `run-bench.sh`, `lib-filters.sh` | Benchmark A and the filters |
| `bench-b.sh` | Benchmark B session runner and checker |
| `usage-pack/` | The test-output filter as a Claude Code plugin (experiment; 30 tests) |
| `results/` | The data behind the findings, including 3 runs discarded for a checker bug (marked `valid=no`) |

## Notes

- Raw-output tokens are estimates at ~4 characters per token. Session tokens come from Claude Code's own JSON output.
- The discarded runs: an early version of `bench-b.sh` deleted Flask's virtualenv before checking, so the suite could not start and every run looked like a false "done". Verify your checker before you trust its verdicts.

Unofficial. Not affiliated with or endorsed by Anthropic. MIT licensed.
