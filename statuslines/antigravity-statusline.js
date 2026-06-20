#!/usr/bin/env node
// Antigravity CLI Statusline
// Config: ~/.gemini/antigravity-cli/settings.json
//   "statusLine": { "type": "command", "command": "node ~/.gemini/antigravity-cli/statusline.js" }
//
// Stdin JSON fields (same schema as Claude Code):
//   model.display_name, workspace.current_dir, session_id,
//   context_window.{remaining_percentage, total_input_tokens, total_output_tokens},
//   rate_limits.{five_hour, seven_day}

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

// Cache hit rate for the current turn: read tokens / all input tokens. Per-turn
// (current_usage), not cumulative. Returns null when fields are absent.
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

// ── Context normalization ──────────────────────────────────────────────────────
// Mirror Claude Code's 16.5% autocompact buffer normalization

const AUTO_COMPACT_BUFFER_PCT = 16.5;

function normalizeCtx(remaining_pct) {
  const usableRemaining = Math.max(
    0,
    ((remaining_pct - AUTO_COMPACT_BUFFER_PCT) / (100 - AUTO_COMPACT_BUFFER_PCT)) * 100
  );
  return Math.max(0, Math.min(100, Math.round(100 - usableRemaining)));
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

    const modelRaw = data.model;
    const model    = (typeof modelRaw === 'object' ? modelRaw?.display_name : modelRaw) || 'Antigravity';
    const dir      = data.workspace?.current_dir || data.cwd || process.cwd();
    const dirname  = path.basename(dir);

    // ── Context bar ─────────────────────────────────────────────────────────
    let ctxPart = '';
    const remaining = data.context_window?.remaining_percentage;
    if (remaining != null) {
      const used = normalizeCtx(remaining);
      ctxPart = metricBar('CTX', used, 8);
    }

    // ── Token counts ────────────────────────────────────────────────────────
    let tokenPart = '';
    const totalIn  = data.context_window?.total_input_tokens;
    const totalOut = data.context_window?.total_output_tokens;
    if (totalIn != null && totalOut != null) {
      const fmt = n => n >= 1e6 ? (n/1e6).toFixed(1)+'M' : n >= 1e3 ? (n/1e3).toFixed(1)+'k' : String(n);
      tokenPart = `${cyan(bold('TOK'))} ${cyan(bold('IN'))} ${white(fmt(totalIn))} ${mutedGray('·')} ${cyan(bold('OUT'))} ${white(fmt(totalOut))}`;
    }

    // ── Cache hit rate (current turn) ─────────────────────────────────────────
    let cachePart = '';
    const hitRate = cacheHitRate(data.context_window?.current_usage);
    if (hitRate != null) {
      cachePart = cacheBar('CACHE', hitRate, 6);
    }

    // ── Rate limits (subscription) or G1 credits ────────────────────────────
    let fiveHourPart = '';
    let sevenDayPart = '';

    const fiveHour = data.rate_limits?.five_hour;
    const sevenDay = data.rate_limits?.seven_day;

    if (fiveHour != null) {
      const pct = Math.round(fiveHour.used_percentage);
      let resetStr = '';
      if (fiveHour.resets_at != null) {
        const d  = new Date(fiveHour.resets_at * 1000);
        const hh = String(d.getHours()).padStart(2, '0');
        const mm = String(d.getMinutes()).padStart(2, '0');
        resetStr = mutedGray(` ↺ ${hh}:${mm}`);
      }
      fiveHourPart = metricBar('5H', pct, 6) + resetStr;
    }

    if (sevenDay != null) {
      const pct = Math.round(sevenDay.used_percentage);
      let resetStr = '';
      if (sevenDay.resets_at != null) {
        const d    = new Date(sevenDay.resets_at * 1000);
        const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
        resetStr = mutedGray(` ↺ ${days[d.getDay()]} ${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')}`);
      }
      sevenDayPart = metricBar('7D', pct, 6) + resetStr;
    }

    // G1 credits (Antigravity v1.0.3+): field shape TBD, handle gracefully
    let creditsPart = '';
    const credits = data.credits;
    if (credits != null && credits.used_percentage != null) {
      creditsPart = metricBar('G1', Math.round(credits.used_percentage), 6);
    }

    // ── Git info ─────────────────────────────────────────────────────────────
    let gitPart = '';
    const git = getGitInfo(data.cwd || dir);
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
    }

    // ── Assemble ─────────────────────────────────────────────────────────────
    const sep    = mutedGray(' │ ');
    const dotSep = mutedGray(' · ');

    const leftParts = [softBlue(model), white(dirname)].filter(Boolean).join(sep);
    const rightParts = [ctxPart, fiveHourPart, sevenDayPart, creditsPart]
      .filter(Boolean)
      .join(dotSep);

    const line1 = rightParts ? leftParts + sep + rightParts : leftParts;
    const line2Parts = [gitPart, tokenPart, cachePart].filter(Boolean).join(dotSep);
    const output = line2Parts ? line1 + '\n' + line2Parts : line1;

    process.stdout.write(output);
  } catch (_) {
    // Silent fail — never break the statusline
  }
});
