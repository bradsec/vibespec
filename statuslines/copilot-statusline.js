#!/usr/bin/env node
// GitHub Copilot CLI Statusline
// Config: ~/.copilot/settings.json
//   "statusLine": { "type": "command", "command": "node ~/.copilot/statusline.js", "padding": 1 }
//   "feature_flags": { "enabled": ["STATUS_LINE"] }
//
// Stdin JSON fields:
//   cwd, session_id, version
//   model: { id, display_name }
//   workspace: { current_dir }
//   context_window: { current_context_tokens, displayed_context_limit,
//                     current_context_used_percentage, used_percentage,
//                     total_input_tokens, total_output_tokens }
//   cost: { total_premium_requests, total_lines_added, total_lines_removed,
//            total_duration_ms, total_api_duration_ms }
//   remote: { connected, task_name, task_url, repository: { owner, name, branch } }

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

    const model   = data.model?.display_name || 'Copilot';
    const dir     = data.workspace?.current_dir || data.cwd || process.cwd();
    const dirname = path.basename(dir);

    // ── Context bar ─────────────────────────────────────────────────────────
    // Prefer current_context_used_percentage; fall back to used_percentage
    let ctxPart = '';
    const ctx = data.context_window;
    const ctxPct = ctx?.current_context_used_percentage ?? ctx?.used_percentage;
    if (ctxPct != null) {
      ctxPart = metricBar('CTX', Math.round(ctxPct), 8);
    }

    // ── Token counts ────────────────────────────────────────────────────────
    let tokenPart = '';
    const totalIn  = ctx?.total_input_tokens;
    const totalOut = ctx?.total_output_tokens;
    if (totalIn != null && totalOut != null) {
      const fmt = n => n >= 1e6 ? (n/1e6).toFixed(1)+'M' : n >= 1e3 ? (n/1e3).toFixed(1)+'k' : String(n);
      tokenPart = `${cyan(bold('TOK'))} ${cyan(bold('IN'))} ${white(fmt(totalIn))} ${mutedGray('·')} ${cyan(bold('OUT'))} ${white(fmt(totalOut))}`;
    }

    // ── Premium requests (Copilot subscription metric) ───────────────────
    let premiumPart = '';
    const premiumReqs = data.cost?.total_premium_requests;
    if (premiumReqs != null && premiumReqs > 0) {
      premiumPart = `${cyan(bold('PREM'))} ${white(String(premiumReqs))}`;
    }

    // ── Remote task (if connected) ────────────────────────────────────────
    let remotePart = '';
    const remote = data.remote;
    if (remote?.connected && remote?.task_name) {
      remotePart = `${cyan(bold('TASK'))} ${white(remote.task_name)}`;
    }

    // ── Git (prefer remote.repository.branch if available, else detect) ──
    let gitPart = '';
    const repoBranch = remote?.repository?.branch;
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
    } else if (repoBranch) {
      gitPart = `${cyan(bold('GIT'))} ${white(repoBranch)}`;
    }

    // ── Assemble ─────────────────────────────────────────────────────────────
    const sep    = mutedGray(' │ ');
    const dotSep = mutedGray(' · ');

    const leftParts  = [softBlue(model), remotePart || white(dirname)].filter(Boolean).join(sep);
    const rightParts = [ctxPart].filter(Boolean).join(dotSep);
    const line1      = rightParts ? leftParts + sep + rightParts : leftParts;
    const line2Parts = [gitPart, tokenPart, premiumPart].filter(Boolean).join(dotSep);
    const output     = line2Parts ? line1 + '\n' + line2Parts : line1;

    process.stdout.write(output);
  } catch (_) {
    // Silent fail — never break the statusline
  }
});
