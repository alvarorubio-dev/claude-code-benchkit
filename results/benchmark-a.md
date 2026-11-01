# Benchmark A — test output in context (2026-10-31)

Tokens estimated at ~4 characters per token.

| Repo | Command | State | Exit | Raw tokens | Official filter | Pack filter | Official shows result? |
|---|---|---|---|---|---|---|---|
| express | `npm test` | green | 0 | 17,723 | 0 (−100%) | 90 (−100%) | no |
| express | `npm test` | red | 1 | 17,832 | 0 (−100%) | 239 (−99%) | no |
| flask | `python -m pytest` | green | 0 | 611 | 0 (−100%) | 611 (−0%) | no |
| flask | `python -m pytest` | red | 1 | 747 | 102 (−87%) | 279 (−63%) | yes |
| flask | `python -m pytest -v` | green | 0 | 10,334 | 0 (−100%) | 210 (−98%) | no |
| flask | `python -m pytest -v` | red | 1 | 10,471 | 123 (−99%) | 280 (−98%) | yes |
| cobra | `go test ./...` | green | 0 | 19 | 0 (−100%) | 19 (−0%) | no |
| cobra | `go test ./...` | red | 1 | 1,780 | 44 (−98%) | 132 (−93%) | yes |
| cobra | `go test -v ./...` | green | 0 | 14,079 | 0 (−100%) | 101 (−100%) | no |
| cobra | `go test -v ./...` | red | 1 | 14,111 | 63 (−100%) | 684 (−96%) | yes |
