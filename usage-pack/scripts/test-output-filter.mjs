#!/usr/bin/env node
// test-output-filter — PreToolUse hook for Bash.
// When Claude runs a test suite, rewrite the command so it runs through
// run-filtered.sh: Claude then sees failures, the summary and the exit code,
// and the full log stays on disk. The rewritten command is plain text (no
// encoding), so permission rules and auto mode still see what will run.
// Fail-open: any error means "no change".

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const RUNNER = /(^|[\s;&(])(npm( run)? test|yarn test|pnpm( run)? test|npx (vitest|jest|mocha)|vitest( run)?|jest|mocha|(\S*python[0-9.]*(\.exe)?|py( -3)?) -m pytest|pytest|go test|cargo test)(\s|$)/;

export function rewrite(command, scriptsDir) {
  if (typeof command !== 'string' || !command.trim()) return null;
  if (process.env.USAGE_PACK_OFF === '1') return null;
  if (!RUNNER.test(command)) return null;
  const probe = command.replace(/\s*2>&1/g, '');      // merging stderr is fine
  if (/[|>]/.test(probe)) return null;               // Claude already pipes or redirects
  if (/--watch\b/.test(command)) return null;         // long-running watchers stay untouched
  if (command.includes('run-filtered.sh')) return null;
  const quoted = `'${command.replace(/'/g, `'\\''`)}'`;
  const script = join(scriptsDir, 'run-filtered.sh').replace(/\\/g, '/');
  return `bash "${script}" ${quoted}`;
}

function main() {
  let data;
  try { data = JSON.parse(readFileSync(0, 'utf8') || '{}'); } catch { return; }
  const input = data.tool_input || {};
  const scriptsDir = dirname(fileURLToPath(import.meta.url));
  const next = rewrite(input.command, scriptsDir);
  if (!next) return;
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      updatedInput: { ...input, command: next },
    },
  }));
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith('test-output-filter.mjs')) {
  try { main(); } catch { /* fail-open */ }
}
