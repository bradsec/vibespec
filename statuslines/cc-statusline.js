#!/usr/bin/env node
// Claude Code Statusline - Enhanced Edition
// Shows pretty bars for: context usage, session (5h) usage, weekly (7d) usage
// Line 2: git status + token counts

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

// ── Visual helpers ────────────────────────────────────────────────────────────

// ANSI helpers — reset is explicit so colors never bleed across segments
const R = '\x1b[0m';

function color(ansi, text) { return `${ansi}${text}${R}`; }

// Named palette — every color defined once, used by name throughout
function bold(t)       { return color('\x1b[1m',           t); }
function white(t)      { return color('\x1b[97m',          t); }   // bright white — primary info
function softBlue(t)   { return color('\x1b[38;5;111m',    t); }   // #87afff — model name
function cyan(t)       { return color('\x1b[38;5;87m',     t); }   // bright cyan — metric labels
function yellow(t)     { return color('\x1b[38;5;220m',    t); }   // amber — active task / warnings
function green(t)      { return color('\x1b[38;5;120m',    t); }   // soft green — healthy
function amber(t)      { return color('\x1b[38;5;214m',    t); }   // orange-amber — moderate
function orange(t)     { return color('\x1b[38;5;208m',    t); }   // deep orange — elevated
function red(t)        { return color('\x1b[38;5;203m',    t); }   // soft red — high
function blink_red(t)  { return color('\x1b[5;38;5;196m',  t); }   // blinking bright red — critical
function mutedGray(t)  { return color('\x1b[38;5;244m',    t); }   // separator / secondary

// Color ramp for usage bars — green → amber → orange → red → blink
function usageColor(pct, text) {
  if (pct <  50) return green(text);
  if (pct <  65) return amber(text);
  if (pct <  80) return orange(text);
  if (pct <  92) return red(text);
  return blink_red(text);
}

// Build a labelled metric block with distinct label styling:
//   LABEL ████░░░░  nn%
//
// - Label: bright cyan, bold — immediately identifiable
// - Filled bar + percentage: usage-colored — state at a glance
// - Empty bar: muted gray — low visual weight
function metricBar(label, pct, segments) {
  const filled = Math.round((Math.max(0, Math.min(100, pct)) / 100) * segments);
  const empty  = segments - filled;
  const filledBar = usageColor(pct, '█'.repeat(filled));
  const emptyBar  = mutedGray('░'.repeat(empty));
  const pctStr    = bold(usageColor(pct, String(Math.round(pct)) + '%'));
  return `${cyan(bold(label))} ${filledBar}${emptyBar} ${pctStr}`;
}

// Cache hit-rate bar: like metricBar but the color ramp is inverted because a
// HIGH hit rate is healthy (cheap, fast) while a low one is not. Coloring by
// (100 - pct) reuses the usageColor ramp so 90% hit reads green, 10% reads red.
function cacheBar(label, pct, segments) {
  const clamped = Math.max(0, Math.min(100, pct));
  const filled  = Math.round((clamped / 100) * segments);
  const empty   = segments - filled;
  const inv      = 100 - clamped;
  const filledBar = usageColor(inv, '█'.repeat(filled));
  const emptyBar  = mutedGray('░'.repeat(empty));
  const pctStr    = bold(usageColor(inv, String(Math.round(clamped)) + '%'));
  return `${cyan(bold(label))} ${filledBar}${emptyBar} ${pctStr}`;
}

// Per-turn cache hit rate: fraction of input tokens served from the prompt
// cache for the last API call. Denominator is all input tokens (fresh + cache
// read + cache write). This is a fallback; it reflects one turn, not the
// session. Returns null when the fields are absent or no input yet.
function turnCacheHitRate(currentUsage) {
  if (!currentUsage) return null;
  const fresh = currentUsage.input_tokens || 0;
  const read  = currentUsage.cache_read_input_tokens || 0;
  const write = currentUsage.cache_creation_input_tokens || 0;
  const total = fresh + read + write;
  if (total <= 0) return null;
  return (read / total) * 100;
}

// Session cache hit rate. Claude Code v2.1.251+ sends a `prompt_cache` object
// whose `hit_ratio` (0..1) is cache-read tokens over all input tokens for the
// whole main conversation. Prefer it; fall back to the per-turn estimate on
// older clients or before the first response.
function cacheHitRate(data) {
  const ratio = data.prompt_cache?.hit_ratio;
  if (typeof ratio === 'number') return ratio * 100;
  return turnCacheHitRate(data.context_window?.current_usage);
}

// ── Git status ────────────────────────────────────────────────────────────────
// Returns null when cwd is not inside a git repo (or git is not available).
// execFileSync with argument arrays: no shell involved, fixed arguments only.
// --no-optional-locks is a global git flag, so it goes before the subcommand.
// Pass { skipRemote: true } to skip the remote-URL lookup when the caller
// already has repo identity from the statusline payload.
function getGitInfo(cwd, { skipRemote = false } = {}) {
  const opts = { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] };

  const run = args => {
    try { return execFileSync('git', args, opts).trim(); } catch (_) { return null; }
  };

  // Confirm we're in a git repo (also fails when git is not installed)
  if (run(['rev-parse', '--git-dir']) === null) return null;

  // Branch name (or short SHA when detached HEAD)
  const branch = run(['symbolic-ref', '--short', 'HEAD']) ||
                 run(['rev-parse', '--short', 'HEAD']) ||
                 '?';

  // Dirty file count: modified + added + deleted (tracked changes only + untracked)
  const statusLines = run(['--no-optional-locks', 'status', '--porcelain']) || '';
  const dirtyCount  = statusLines ? statusLines.split('\n').filter(Boolean).length : 0;

  // Commits ahead of / behind @{upstream}
  let unpushed = 0;
  let behind   = 0;
  if (run(['rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}'])) {
    unpushed = parseInt(run(['--no-optional-locks', 'rev-list', '--count', '@{u}..HEAD']), 10) || 0;
    behind   = parseInt(run(['--no-optional-locks', 'rev-list', '--count', 'HEAD..@{u}']), 10) || 0;
  }

  // Remote URL for origin (or first remote if origin absent)
  let remote = null;
  if (!skipRemote) {
    const remoteUrl = run(['remote', 'get-url', 'origin']) ||
                      (() => {
                        const remotes = run(['remote']);
                        if (!remotes) return null;
                        const first = remotes.split('\n').find(Boolean);
                        return first ? run(['remote', 'get-url', first]) : null;
                      })();
    if (remoteUrl) {
      // Strip trailing .git and protocol prefix for brevity
      remote = remoteUrl
        .replace(/\.git$/, '')
        .replace(/^https?:\/\//, '')
        .replace(/^git@([^:]+):/, '$1/');
    }
  }

  return { branch, dirtyCount, unpushed, behind, remote };
}

// ── Account / plan ──────────────────────────────────────────────────────────
// Account name and subscription plan are NOT in the statusLine JSON payload
// (open feature requests anthropics/claude-code#24679, #26219). They live in
// the global config file ~/.claude.json under `oauthAccount`. Read it directly:
// docs warn that shelling out to `claude auth whoami` from hooks hangs.
// Honors CLAUDE_CONFIG_DIR. The field is internal/undocumented, so every access
// is guarded and a missing file or shape is treated as "no account info".
function getAccountInfo() {
  // Single config root, mirroring the todos lookup: an explicit CLAUDE_CONFIG_DIR
  // wins outright so a different account root never leaks the home account.
  const configFile = process.env.CLAUDE_CONFIG_DIR
    ? path.join(process.env.CLAUDE_CONFIG_DIR, '.claude.json')
    : path.join(os.homedir(), '.claude.json');

  try {
    const acct = JSON.parse(fs.readFileSync(configFile, 'utf8')).oauthAccount;
    if (!acct) return null;

    const name = acct.displayName || null;

    // organizationType is e.g. "claude_max" / "claude_pro" -> "Max" / "Pro"
    let plan = null;
    const t = acct.organizationType;
    if (typeof t === 'string' && t.startsWith('claude_')) {
      const word = t.slice('claude_'.length);
      plan = word.charAt(0).toUpperCase() + word.slice(1);
    }

    return name || plan ? { name, plan } : null;
  } catch (_) {
    return null;
  }
}

// ── Context window normalization ──────────────────────────────────────────────
// Fallback only. Newer Claude Code sends a pre-calculated
// context_window.used_percentage; use that when present. This path runs on
// older clients that send only remaining_percentage: Claude Code reserves
// ~16.5% for the autocompact buffer, so normalize to show 100% when that
// buffer is reached.
const AUTO_COMPACT_BUFFER_PCT = 16.5;

function normalizeContextUsed(remaining_pct) {
  const usableRemaining = Math.max(
    0,
    ((remaining_pct - AUTO_COMPACT_BUFFER_PCT) / (100 - AUTO_COMPACT_BUFFER_PCT)) * 100
  );
  return Math.max(0, Math.min(100, Math.round(100 - usableRemaining)));
}

// ── Main ──────────────────────────────────────────────────────────────────────

let input = '';
const stdinTimeout = setTimeout(() => process.exit(0), 3000);
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => (input += chunk));
process.stdin.on('end', () => {
  clearTimeout(stdinTimeout);
  try {
    const data = JSON.parse(input);

    const model    = data.model?.display_name || 'Claude';
    const effort   = data.effort?.level ? mutedGray(` [${data.effort.level}]`) : '';
    const dir      = data.workspace?.current_dir || process.cwd();
    const session  = data.session_id || '';
    const dirname  = path.basename(dir);
    const cw       = data.context_window || {};

    const homeDir   = os.homedir();
    const claudeDir = process.env.CLAUDE_CONFIG_DIR || path.join(homeDir, '.claude');

    function fmtTokens(n) {
      if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + 'M';
      if (n >= 1_000)     return (n / 1_000).toFixed(1)     + 'k';
      return String(n);
    }

    // ── Context bar ────────────────────────────────────────────────────────
    // Prefer the pre-calculated used_percentage; fall back to normalizing
    // remaining_percentage on older clients that do not send it.
    let ctxPart = '';
    if (cw.used_percentage != null) {
      ctxPart = metricBar('CTX', Math.round(cw.used_percentage), 8);
    } else if (cw.remaining_percentage != null) {
      ctxPart = metricBar('CTX', normalizeContextUsed(cw.remaining_percentage), 8);
    }

    // ── Context occupancy tokens ────────────────────────────────────────────
    // context_window.total_* are the tokens currently in the window (from the
    // most recent API response), not session cumulative. Pair with the window
    // size so the ratio is meaningful.
    let tokenPart = '';
    const totalIn  = cw.total_input_tokens;
    const totalOut = cw.total_output_tokens;
    const winSize  = cw.context_window_size;
    if (totalIn != null) {
      tokenPart = `${cyan(bold('TOK'))} ${cyan(bold('IN'))} ${white(fmtTokens(totalIn))}`;
      if (winSize) tokenPart += ` ${mutedGray('/')} ${white(fmtTokens(winSize))}`;
      if (totalOut != null) {
        tokenPart += ` ${mutedGray('·')} ${cyan(bold('OUT'))} ${white(fmtTokens(totalOut))}`;
      }
    }

    // ── Cost (session) ─────────────────────────────────────────────────────
    let costPart = '';
    const costUsd = data.cost?.total_cost_usd;
    if (typeof costUsd === 'number' && costUsd > 0) {
      costPart = `${cyan(bold('$'))} ${white(costUsd.toFixed(2))}`;
    }

    // ── Cache hit rate ─────────────────────────────────────────────────────
    // Session-wide when prompt_cache is present, else the per-turn estimate.
    let cachePart = '';
    const hitRate = cacheHitRate(data);
    if (hitRate != null) {
      cachePart = cacheBar('CACHE', hitRate, 6);
    }

    // ── Rate limit bars (claude.ai subscription only) ──────────────────────
    let fiveHourPart = '';
    let sevenDayPart = '';

    const fiveHour  = data.rate_limits?.five_hour;
    const sevenDay  = data.rate_limits?.seven_day;

    if (fiveHour != null) {
      const pct = Math.round(fiveHour.used_percentage);
      let resetStr = '';
      if (fiveHour.resets_at != null) {
        const d = new Date(fiveHour.resets_at * 1000);
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
        const d = new Date(sevenDay.resets_at * 1000);
        const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
        const day = days[d.getDay()];
        const hh = String(d.getHours()).padStart(2, '0');
        const mm = String(d.getMinutes()).padStart(2, '0');
        resetStr = mutedGray(` ↺ ${day} ${hh}:${mm}`);
      }
      sevenDayPart = metricBar('7D', pct, 6) + resetStr;
    }

    // ── Current task from todos ────────────────────────────────────────────
    let task = '';
    const todosDir = path.join(claudeDir, 'todos');
    if (session && fs.existsSync(todosDir)) {
      try {
        const files = fs.readdirSync(todosDir)
          .filter(f => f.startsWith(session) && f.includes('-agent-') && f.endsWith('.json'))
          .map(f => ({ name: f, mtime: fs.statSync(path.join(todosDir, f)).mtime }))
          .sort((a, b) => b.mtime - a.mtime);

        if (files.length > 0) {
          const todos = JSON.parse(fs.readFileSync(path.join(todosDir, files[0].name), 'utf8'));
          const inProgress = todos.find(t => t.status === 'in_progress');
          if (inProgress) task = inProgress.activeForm || '';
        }
      } catch (_) {}
    }

    // ── Git info ───────────────────────────────────────────────────────────
    // repo identity comes from the payload when available, so skip the extra
    // `git remote` calls in that case.
    let gitPart = '';
    const gitCwd = data.cwd || dir;
    const repo   = data.workspace?.repo;
    const git    = getGitInfo(gitCwd, { skipRemote: !!repo });
    let remoteLabel = null;
    if (repo && (repo.owner || repo.name)) {
      remoteLabel = [repo.host, repo.owner, repo.name].filter(Boolean).join('/');
    } else if (git?.remote) {
      remoteLabel = git.remote;
    }
    if (git) {
      // Branch: always shown
      gitPart = `${cyan(bold('GIT'))} ${white(git.branch)}`;

      // Dirty indicator: show count when there are changes, "clean" when not
      if (git.dirtyCount > 0) {
        gitPart += ` ${mutedGray('·')} ${cyan(bold('~'))}${white(String(git.dirtyCount))}`;
      } else {
        gitPart += ` ${mutedGray('·')} ${mutedGray('clean')}`;
      }

      // Unpushed / behind commits
      if (git.unpushed > 0) {
        gitPart += ` ${mutedGray('·')} ${cyan(bold('↑'))}${white(String(git.unpushed))}`;
      }
      if (git.behind > 0) {
        gitPart += ` ${mutedGray('·')} ${cyan(bold('↓'))}${white(String(git.behind))}`;
      }
    }

    // ── Assemble output ────────────────────────────────────────────────────
    // Line 1: Name · Plan │ ModelName [effort] │ active task │ CTX ████░░░░ nn% · 5H ████░░ nn% ↺HH:MM · 7D ████░░ nn%
    // Line 2: dirname · remote · GIT branch · ~n · ↑n · ↓n · TOK IN nn.nk / nnnk · OUT nn.nk · $ n.nn · CACHE ████░░ nn%
    //
    // Visual hierarchy:
    //   - Model: soft blue (ambient context)
    //   - Task: bold amber (most important left-side info when present)
    //   - Dir: bright white (primary navigation anchor)
    //   - Separators: muted gray (structural, low weight)
    //   - Metric labels: bold cyan (scannable right-side anchors)
    //   - Bars + percentages: usage-colored (state at a glance)
    //   - Git branch/counts: bright white values, cyan labels

    const sep    = mutedGray(' │ ');
    const dotSep = mutedGray(' · ');

    // Account segment: "Mark · Max" (name white, plan soft green). Leading
    // position so identity/plan is the first thing read on line 1.
    const acct = getAccountInfo();
    const acctPart = acct
      ? [acct.name ? white(acct.name) : null, acct.plan ? green(acct.plan) : null]
          .filter(Boolean)
          .join(dotSep)
      : null;

    const leftParts = [
      acctPart,
      softBlue(model) + effort,
      task ? bold(yellow(task)) : null,
    ].filter(Boolean).join(sep);

    const rightParts = [ctxPart, fiveHourPart, sevenDayPart]
      .filter(Boolean)
      .join(dotSep);

    const line1 = rightParts
      ? leftParts + sep + rightParts
      : leftParts;

    // Line 2: dir (+ remote) · git · tokens · cost · cache
    let dirPart = white(dirname);
    if (remoteLabel) {
      dirPart += dotSep + mutedGray(remoteLabel);
    }

    const line2Parts = [dirPart, gitPart, tokenPart, costPart, cachePart].filter(Boolean).join(dotSep);
    const output     = line2Parts
      ? line1 + '\n' + line2Parts
      : line1;

    process.stdout.write(output);
  } catch (_) {
    // Silent fail — never break the statusline
  }
});
