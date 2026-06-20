#!/usr/bin/env node
// Codex CLI Statusline
//
// NOTE: Command-based statusline is not yet implemented in Codex CLI.
// Track: https://github.com/openai/codex/issues/17827
//
// This script is ready for when support lands. The proposed stdin JSON:
//   {
//     "model": "gpt-5.5",
//     "reasoning_effort": "high",
//     "cwd": "/repo",
//     "git_branch": "main",
//     "context": {
//       "remaining_percent": 82.4,
//       "used_percent": 17.6,
//       "used_tokens": 176000,
//       "window_tokens": 1000000
//     },
//     "limits": {
//       "five_hour": { "used_percent": 16.0, "resets_at": 1770000000 },
//       "weekly":    { "used_percent": 12.0, "resets_at": 1770300000 }
//     },
//     "run_state": "idle",
//     "fast_mode": false,
//     "codex_version": "0.x.x"
//   }
//
// Config (future): ~/.codex/config.toml
//   [tui.status_line_command]
//   command = "node ~/.codex/statusline.js"
//   refresh_interval = 10
//   timeout_ms = 1000
//   preserve_ansi = true
//
// Until then, use the enum-based config (see codex-install.sh).

const { execFileSync } = require('child_process');
const path = require('path');

// ── Visual helpers ─────────────────────────────────────────────────────────────

const R = '\x1b[0m';
function color(ansi, text) { return `${ansi}${text}${R}`; }

function bold(t)      { return color('\x1b[1m',           t); }
function white(t)     { return color('\x1b[97m',          t); }
function softBlue(t)  { return color('\x1b[38;5;111m',    t); }
function cyan(t)      { return color('\x1b[38;5;87m',     t); }
function green(t)     { return color('\x1b[38;5;120m',    t); }
function amber(t)     { return color('\x1b[38;5;214m',    t); }
function orange(t)    { return color('\x1b[38;5;208m',    t); }
function red(t)       { return color('\x1b[38;5;203m',    t); }
function blinkRed(t)  { return color('\x1b[5;38;5;196m',  t); }
function mutedGray(t) { return color('\x1b[38;5;244m',    t); }

function usageColor(pct, text) {
  if (pct <  50) return green(text);
  if (pct <  65) return amber(text);
  if (pct <  80) return orange(text);
  if (pct <  92) return red(text);
  return blinkRed(text);
}

function metricBar(label, pct, segments) {
  const filled = Math.round((Math.max(0, Math.min(100, pct)) / 100) * segments);
  const empty  = segments - filled;
  return `${cyan(bold(label))} ${usageColor(pct, '█'.repeat(filled))}${mutedGray('░'.repeat(empty))} ${bold(usageColor(pct, Math.round(pct) + '%'))}`;
}

// Cache hit-rate bar: inverted color ramp because a HIGH hit rate is healthy.
// Coloring by (100 - pct) reuses usageColor so 90% reads green, 10% reads red.
function cacheBar(label, pct, segments) {
  const clamped = Math.max(0, Math.min(100, pct));
  const filled  = Math.round((clamped / 100) * segments);
  const empty   = segments - filled;
  const inv      = 100 - clamped;
  return `${cyan(bold(label))} ${usageColor(inv, '█'.repeat(filled))}${mutedGray('░'.repeat(empty))} ${bold(usageColor(inv, Math.round(clamped) + '%'))}`;
}

// Cache hit rate: read tokens / all input tokens for the turn. Codex CLI does
// not yet emit cache token fields (statusline support itself is pending,
// openai/codex#17827); the field names below mirror Claude Code's
// context.current_usage so this lights up if/when Codex adopts the same shape.
// Guarded throughout, so it stays inert until those fields appear.
function cacheHitRate(currentUsage) {
  if (!currentUsage) return null;
  const fresh = currentUsage.input_tokens || 0;
  const read  = currentUsage.cache_read_input_tokens || 0;
  const write = currentUsage.cache_creation_input_tokens || 0;
  const total = fresh + read + write;
  if (total <= 0) return null;
  return (read / total) * 100;
}

// ── Git status ─────────────────────────────────────────────────────────────────

// execFileSync with argument arrays: no shell involved, fixed arguments only.
// --no-optional-locks is a global git flag, so it goes before the subcommand.
function getGitInfo(cwd) {
  const opts = { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] };
  const run = args => { try { return execFileSync('git', args, opts).trim(); } catch (_) { return null; } };
  if (run(['rev-parse', '--git-dir']) === null) return null;
  const branch = run(['symbolic-ref', '--short', 'HEAD']) || run(['rev-parse', '--short', 'HEAD']) || '?';
  const statusLines = run(['--no-optional-locks', 'status', '--porcelain']) || '';
  const dirtyCount  = statusLines ? statusLines.split('\n').filter(Boolean).length : 0;
  let unpushed = 0;
  let behind   = 0;
  if (run(['rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}'])) {
    unpushed = parseInt(run(['--no-optional-locks', 'rev-list', '--count', '@{u}..HEAD']), 10) || 0;
    behind   = parseInt(run(['--no-optional-locks', 'rev-list', '--count', 'HEAD..@{u}']), 10) || 0;
  }
  return { branch, dirtyCount, unpushed, behind };
}

// ── Main ───────────────────────────────────────────────────────────────────────

let input = '';
const stdinTimeout = setTimeout(() => process.exit(0), 3000);
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => (input += chunk));
process.stdin.on('end', () => {
  clearTimeout(stdinTimeout);
  try {
    const data = JSON.parse(input);

    const model   = data.model || 'Codex';
    const effort  = data.reasoning_effort ? mutedGray(` [${data.reasoning_effort}]`) : '';
    const dir     = data.cwd || process.cwd();
    const dirname = path.basename(dir);

    // ── Context bar ─────────────────────────────────────────────────────────
    let ctxPart = '';
    const ctx = data.context;
    if (ctx?.used_percent != null) {
      ctxPart = metricBar('CTX', Math.round(ctx.used_percent), 8);
    }

    // ── Token counts ────────────────────────────────────────────────────────
    let tokenPart = '';
    if (ctx?.used_tokens != null) {
      const fmt = n => n >= 1e6 ? (n/1e6).toFixed(1)+'M' : n >= 1e3 ? (n/1e3).toFixed(1)+'k' : String(n);
      tokenPart = `${cyan(bold('TOK'))} ${white(fmt(ctx.used_tokens))} ${mutedGray('/')} ${white(fmt(ctx.window_tokens ?? 0))}`;
    }

    // ── Cache hit rate (current turn) ─────────────────────────────────────────
    let cachePart = '';
    const hitRate = cacheHitRate(ctx?.current_usage);
    if (hitRate != null) {
      cachePart = cacheBar('CACHE', hitRate, 6);
    }

    // ── Rate limits ──────────────────────────────────────────────────────────
    let fiveHourPart = '';
    let weeklyPart   = '';

    const fiveHour = data.limits?.five_hour;
    const weekly   = data.limits?.weekly;

    if (fiveHour != null) {
      const pct = Math.round(fiveHour.used_percent);
      let resetStr = '';
      if (fiveHour.resets_at != null) {
        const d  = new Date(fiveHour.resets_at * 1000);
        const hh = String(d.getHours()).padStart(2, '0');
        const mm = String(d.getMinutes()).padStart(2, '0');
        resetStr = mutedGray(` ↺ ${hh}:${mm}`);
      }
      fiveHourPart = metricBar('5H', pct, 6) + resetStr;
    }

    if (weekly != null) {
      const pct = Math.round(weekly.used_percent);
      let resetStr = '';
      if (weekly.resets_at != null) {
        const d    = new Date(weekly.resets_at * 1000);
        const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
        resetStr = mutedGray(` ↺ ${days[d.getDay()]} ${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')}`);
      }
      weeklyPart = metricBar('7D', pct, 6) + resetStr;
    }

    // ── Git (may come from stdin or detected from cwd) ────────────────────
    let gitPart = '';
    const gitBranch = data.git_branch;
    const git = getGitInfo(dir);
    if (git) {
      gitPart = `${cyan(bold('GIT'))} ${white(git.branch)}`;
      if (git.dirtyCount > 0) {
        gitPart += ` ${mutedGray('·')} ${cyan(bold('~'))}${white(String(git.dirtyCount))}`;
      } else {
        gitPart += ` ${mutedGray('·')} ${mutedGray('clean')}`;
      }
      if (git.unpushed > 0) {
        gitPart += ` ${mutedGray('·')} ${cyan(bold('↑'))}${white(String(git.unpushed))}`;
      }
      if (git.behind > 0) {
        gitPart += ` ${mutedGray('·')} ${cyan(bold('↓'))}${white(String(git.behind))}`;
      }
    } else if (gitBranch) {
      gitPart = `${cyan(bold('GIT'))} ${white(gitBranch)}`;
    }

    // ── Assemble ─────────────────────────────────────────────────────────────
    const sep    = mutedGray(' │ ');
    const dotSep = mutedGray(' · ');

    const leftParts  = [softBlue(model) + effort, white(dirname)].filter(Boolean).join(sep);
    const rightParts = [ctxPart, fiveHourPart, weeklyPart].filter(Boolean).join(dotSep);
    const line1      = rightParts ? leftParts + sep + rightParts : leftParts;
    const line2Parts = [gitPart, tokenPart, cachePart].filter(Boolean).join(dotSep);
    const output     = line2Parts ? line1 + '\n' + line2Parts : line1;

    process.stdout.write(output);
  } catch (_) {
    // Silent fail — never break the statusline
  }
});
