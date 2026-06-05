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

const { execSync } = require('child_process');
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

// ── Git status ─────────────────────────────────────────────────────────────────

function getGitInfo(cwd) {
  const opts = { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] };
  try { execSync('git rev-parse --git-dir', opts); } catch (_) { return null; }
  const run = cmd => { try { return execSync(cmd, opts).trim(); } catch (_) { return ''; } };
  const branch = run('git symbolic-ref --short HEAD') || run('git rev-parse --short HEAD') || '?';
  const statusLines = run('git status --porcelain --no-optional-locks');
  const dirtyCount  = statusLines ? statusLines.split('\n').filter(Boolean).length : 0;
  let unpushed = 0;
  const upstream = run('git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null');
  if (upstream) {
    unpushed = parseInt(run('git rev-list --count @{u}..HEAD --no-optional-locks'), 10) || 0;
  }
  return { branch, dirtyCount, unpushed };
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
    } else if (gitBranch) {
      gitPart = `${cyan(bold('GIT'))} ${white(gitBranch)}`;
    }

    // ── Assemble ─────────────────────────────────────────────────────────────
    const sep    = mutedGray(' │ ');
    const dotSep = mutedGray(' · ');

    const leftParts  = [softBlue(model) + effort, white(dirname)].filter(Boolean).join(sep);
    const rightParts = [ctxPart, fiveHourPart, weeklyPart].filter(Boolean).join(dotSep);
    const line1      = rightParts ? leftParts + sep + rightParts : leftParts;
    const line2Parts = [gitPart, tokenPart].filter(Boolean).join(dotSep);
    const output     = line2Parts ? line1 + '\n' + line2Parts : line1;

    process.stdout.write(output);
  } catch (_) {
    // Silent fail — never break the statusline
  }
});
