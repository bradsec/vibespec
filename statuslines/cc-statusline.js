#!/usr/bin/env node
// Claude Code Statusline - Enhanced Edition
// Shows pretty bars for: context usage, session (5h) usage, weekly (7d) usage
// Line 2: git status + token counts

const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

// ── Visual helpers ────────────────────────────────────────────────────────────

// ANSI helpers — reset is explicit so colors never bleed across segments.
// NO_COLOR (https://no-color.org): any non-empty value turns colors off.
const R = '\x1b[0m';
const NO_COLOR = !!process.env.NO_COLOR;

function color(ansi, text) { return NO_COLOR ? String(text) : `${ansi}${text}${R}`; }

// Named palette — every color defined once, used by name throughout
function bold(t)       { return color('\x1b[1m',           t); }
function white(t)      { return color('\x1b[97m',          t); }   // bright white — primary info
function softBlue(t)   { return color('\x1b[38;5;111m',    t); }   // #87afff — model name
function cyan(t)       { return color('\x1b[38;5;87m',     t); }   // bright cyan — metric labels
function yellow(t)     { return color('\x1b[38;5;220m',    t); }   // amber — session name / warnings
function green(t)      { return color('\x1b[38;5;120m',    t); }   // soft green — healthy
function amber(t)      { return color('\x1b[38;5;214m',    t); }   // orange-amber — moderate
function orange(t)     { return color('\x1b[38;5;208m',    t); }   // deep orange — elevated
function red(t)        { return color('\x1b[38;5;203m',    t); }   // soft red — high
function critical(t)   { return color('\x1b[1;38;5;196m',  t); }   // blinking bright red — critical
function mutedGray(t)  { return color('\x1b[38;5;244m',    t); }   // separator / secondary

// Color ramp for usage bars — green → amber → orange → red → bold red.
// No blink: it distracts and not every terminal supports it.
function usageColor(pct, text) {
  if (pct <  50) return green(text);
  if (pct <  65) return amber(text);
  if (pct <  80) return orange(text);
  if (pct <  92) return red(text);
  return critical(text);
}

// Build a labelled metric block with distinct label styling:
//   LABEL ████░░░░  nn%
//
// - Label: bright cyan, bold — immediately identifiable
// - Filled bar + percentage: usage-colored — state at a glance
// - Empty bar: muted gray — low visual weight
function metricBar(label, pct, segments) {
  if (!Number.isFinite(pct)) return '';
  const shownPct = Math.max(0, pct);
  pct = Math.min(100, shownPct);
  const filled = Math.round((pct / 100) * segments);
  const empty  = segments - filled;
  const filledBar = usageColor(pct, '█'.repeat(filled));
  const emptyBar  = mutedGray('░'.repeat(empty));
  const pctStr    = bold(usageColor(pct, String(Math.round(shownPct)) + '%'));
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
  if (!currentUsage || currentUsage.cache_read_input_tokens == null) return null;
  const fresh = currentUsage.input_tokens ?? 0;
  const read  = currentUsage.cache_read_input_tokens ?? 0;
  const write = currentUsage.cache_creation_input_tokens ?? 0;
  if (![fresh, read, write].every(n => Number.isFinite(n) && n >= 0)) return null;
  const total = fresh + read + write;
  if (!Number.isFinite(total) || total <= 0) return null;
  return (read / total) * 100;
}

// Session cache hit rate. Claude Code v2.1.251+ sends a `prompt_cache` object
// whose `hit_ratio` (0..1) is cache-read tokens over all input tokens for the
// whole main conversation. Prefer it; fall back to the per-turn estimate on
// older clients or before the first response.
function cacheHitRate(data) {
  const ratio = data.prompt_cache?.hit_ratio;
  if (Number.isFinite(ratio) && ratio >= 0 && ratio <= 1) return ratio * 100;
  return turnCacheHitRate(data.context_window?.current_usage);
}

// ── Git status ────────────────────────────────────────────────────────────────
// Returns null when cwd is not inside a git repo (or git is not available).
// execFileSync with argument arrays: no shell involved, fixed arguments only.
// --no-optional-locks is a global git flag, so it goes before the subcommand.
// Pass { skipRemote: true } to skip the remote-URL lookup when the caller
// already has repo identity from the statusline payload.
function getGitInfo(cwd, { skipRemote = false, sessionId = '' } = {}) {
  const cacheKey = crypto.createHash('sha256')
    .update(`${sessionId}\0${cwd}\0${skipRemote}`)
    .digest('hex');
  const cachePath = path.join(os.tmpdir(), `vibespec-cc-status-${cacheKey}.json`);
  try {
    const cached = JSON.parse(fs.readFileSync(cachePath, 'utf8'));
    const ageMs = Date.now() - fs.statSync(cachePath).mtimeMs;
    if (ageMs >= 0 && ageMs < 5000 &&
        typeof cached.branch === 'string' &&
        Number.isInteger(cached.dirtyCount) &&
        Number.isInteger(cached.unpushed) &&
        Number.isInteger(cached.behind) &&
        (cached.remote === null || typeof cached.remote === 'string')) {
      return cached;
    }
  } catch (_) {}

  const opts = { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 1000 };

  const run = args => {
    try { return execFileSync('git', args, opts).trim(); } catch (_) { return null; }
  };

  // One call gives branch, upstream ahead/behind and the changed files; it
  // fails outside a repo or without git. Each extra git process adds lag in
  // large repos, and the statusline re-runs every few seconds.
  const status = run(['--no-optional-locks', 'status', '--porcelain=v2', '--branch']);
  if (status === null) return null;
  const { branch, dirtyCount, unpushed, behind } = parseGitStatus(status);

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
      // Display repository identity without URL credentials, query, or fragment.
      if (remoteUrl.includes('://')) {
        try {
          const url = new URL(remoteUrl);
          remote = `${url.host}${url.pathname.replace(/\.git$/, '')}`;
        } catch (_) {
          remote = null;
        }
      } else {
        remote = remoteUrl.replace(/^[^@/]+@([^:]+):/, '$1/').replace(/\.git$/, '');
      }
    }
  }

  const result = { branch, dirtyCount, unpushed, behind, remote };
  const tempPath = `${cachePath}.${crypto.randomBytes(8).toString('hex')}.tmp`;
  try {
    fs.writeFileSync(tempPath, JSON.stringify(result), { mode: 0o600, flag: 'wx' });
    fs.renameSync(tempPath, cachePath);
  } catch (_) {
    try { fs.unlinkSync(tempPath); } catch (_) {}
  }
  return result;
}

// Parses `git status --porcelain=v2 --branch` output.
function parseGitStatus(status) {
  let oid = null;
  let head = null;
  let unpushed = 0;
  let behind = 0;
  let dirtyCount = 0;
  for (const line of status.split('\n')) {
    if (!line) continue;
    if (!line.startsWith('# ')) { dirtyCount++; continue; }
    const [key, ...rest] = line.slice(2).split(' ');
    if (key === 'branch.oid') oid = rest[0];
    else if (key === 'branch.head') head = rest[0];
    else if (key === 'branch.ab') {
      unpushed = Math.abs(parseInt(rest[0], 10)) || 0;
      behind   = Math.abs(parseInt(rest[1], 10)) || 0;
    }
  }
  // Detached HEAD shows the short SHA, like `git rev-parse --short`.
  const branch = head && head !== '(detached)'
    ? head
    : (oid && oid !== '(initial)' ? oid.slice(0, 7) : '?');
  return { branch, dirtyCount, unpushed, behind };
}

// ── Account / plan ──────────────────────────────────────────────────────────
// Account name and subscription plan are NOT in the statusLine JSON payload
// (open feature requests anthropics/claude-code#24679, #26219). They live in
// the global config file ~/.claude.json under `oauthAccount`. Read it directly:
// docs warn that shelling out to `claude auth whoami` from hooks hangs.
// Honors CLAUDE_CONFIG_DIR. The field is internal/undocumented, so every access
// is guarded and a missing file or shape is treated as "no account info".
function getAccountInfo() {
  // An explicit CLAUDE_CONFIG_DIR wins outright so a different account root
  // never leaks the home account.
  const configFile = process.env.CLAUDE_CONFIG_DIR
    ? path.join(process.env.CLAUDE_CONFIG_DIR, '.claude.json')
    : path.join(os.homedir(), '.claude.json');

  // ~/.claude.json grows with project history, so keep the result in a temp
  // file keyed on the config file's size and mtime and parse it again only
  // when it changes.
  let stat;
  try { stat = fs.statSync(configFile); } catch (_) { return null; }
  const key = `${stat.size}:${stat.mtimeMs}`;
  const cachePath = path.join(os.tmpdir(),
    `vibespec-cc-account-${crypto.createHash('sha256').update(configFile).digest('hex')}.json`);
  try {
    const cached = JSON.parse(fs.readFileSync(cachePath, 'utf8'));
    if (cached.key === key) return cached.info;
  } catch (_) {}
  const info = readAccountInfo(configFile);
  const tempPath = `${cachePath}.${crypto.randomBytes(8).toString('hex')}.tmp`;
  try {
    fs.writeFileSync(tempPath, JSON.stringify({ key, info }), { mode: 0o600, flag: 'wx' });
    fs.renameSync(tempPath, cachePath);
  } catch (_) {
    try { fs.unlinkSync(tempPath); } catch (_) {}
  }
  return info;
}

function readAccountInfo(configFile) {
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

// Width of a rendered line in terminal columns: ANSI codes take none, and
// every character used here (including the bar and arrow glyphs) takes one.
function visibleWidth(text) {
  return [...text.replace(/\x1b\[[0-9;]*m/g, '')].length;
}

// The first layout that fits the terminal, else the most compact one.
// Claude Code sets COLUMNS for statusline commands; without it, the first.
function fitLine(layouts) {
  const cols = parseInt(process.env.COLUMNS, 10);
  if (!Number.isFinite(cols) || cols <= 0) return layouts[0];
  return layouts.find((l) => visibleWidth(l) <= cols) || layouts[layouts.length - 1];
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
    const dir      = data.workspace?.current_dir || data.cwd || process.cwd();
    const sessionId = data.session_id || '';
    const sessionName = data.session_name || '';
    const dirname  = path.basename(dir);
    const cw       = data.context_window || {};

    function fmtTokens(n) {
      if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + 'M';
      if (n >= 1_000)     return (n / 1_000).toFixed(1)     + 'k';
      return String(n);
    }

    // ── Context bar ────────────────────────────────────────────────────────
    // Prefer used_percentage; otherwise use the complement of
    // remaining_percentage on older clients that do not send it.
    // Built per layout (see fitLine): compact layouts use shorter bars.
    const ctxPct = Number.isFinite(cw.used_percentage) ? Math.round(cw.used_percentage)
      : Number.isFinite(cw.remaining_percentage) ? 100 - cw.remaining_percentage : null;
    const ctxPart = (segments) => (ctxPct === null ? '' : metricBar('CTX', ctxPct, segments));

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
    // Built per layout, like the context bar; compact layouts can also drop
    // the reset times.
    const fiveHour  = data.rate_limits?.five_hour;
    const sevenDay  = data.rate_limits?.seven_day;
    const spendLimit = data.rate_limits?.spend_limit;

    const resetSuffix = (epochSec, withDay) => {
      if (!Number.isFinite(epochSec) || Math.abs(epochSec) > 8.64e12) return '';
      const d = new Date(epochSec * 1000);
      const hh = String(d.getHours()).padStart(2, '0');
      const mm = String(d.getMinutes()).padStart(2, '0');
      const day = withDay ? `${['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][d.getDay()]} ` : '';
      return mutedGray(` ↺ ${day}${hh}:${mm}`);
    };
    const windowPart = (label, w, withDay, segments, resets) => (Number.isFinite(w?.used_percentage)
      ? metricBar(label, Math.round(w.used_percentage), segments) + (resets ? resetSuffix(w.resets_at, withDay) : '')
      : '');
    const spendLimitPart = (segments) => (Number.isFinite(spendLimit?.used_percentage)
      ? metricBar('SPEND', spendLimit.used_percentage, segments)
      : '');

    // ── Git info ───────────────────────────────────────────────────────────
    // repo identity comes from the payload when available, so skip the extra
    // `git remote` calls in that case.
    let gitPart = '';
    const gitCwd = data.cwd || dir;
    const repo   = data.workspace?.repo;
    const git    = getGitInfo(gitCwd, { skipRemote: !!repo, sessionId });
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
    // Line 1: Name · Plan │ ModelName [effort] │ session name │ CTX ████░░░░ nn% · 5H ████░░ nn% ↺HH:MM · 7D ████░░ nn%
    // Line 2: dirname · remote · GIT branch · ~n · ↑n · ↓n · TOK IN nn.nk / nnnk · OUT nn.nk · $ n.nn · CACHE ████░░ nn%
    //
    // Visual hierarchy:
    //   - Model: soft blue (ambient context)
    //   - Session name: bold amber (most important left-side info when present)
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

    const line1For = ({ account, bars, resets }) => {
      const leftParts = [
        account ? acctPart : null,
        softBlue(model) + effort,
        sessionName ? bold(yellow(sessionName)) : null,
      ].filter(Boolean).join(sep);
      const rightParts = [
        ctxPart(bars ? 8 : 4),
        windowPart('5H', fiveHour, false, bars ? 6 : 3, resets),
        windowPart('7D', sevenDay, true, bars ? 6 : 3, resets),
        spendLimitPart(bars ? 6 : 3),
      ].filter(Boolean).join(dotSep);
      return rightParts ? leftParts + sep + rightParts : leftParts;
    };
    // Narrow terminals: drop the account first, then shorten the bars, then
    // the reset times.
    const line1 = fitLine([
      { account: true, bars: true, resets: true },
      { account: false, bars: true, resets: true },
      { account: false, bars: false, resets: true },
      { account: false, bars: false, resets: false },
    ].map(line1For));

    // Line 2: dir (+ remote) · git · tokens · cost · cache; the remote goes
    // first when it doesn't fit.
    const line2For = (withRemote) => {
      const dirPart = white(dirname) + (withRemote && remoteLabel ? dotSep + mutedGray(remoteLabel) : '');
      return [dirPart, gitPart, tokenPart, costPart, cachePart].filter(Boolean).join(dotSep);
    };
    const line2Parts = fitLine([line2For(true), line2For(false)]);
    const output     = line2Parts
      ? line1 + '\n' + line2Parts
      : line1;

    process.stdout.write(output);
  } catch (_) {
    // Silent fail — never break the statusline
  }
});
