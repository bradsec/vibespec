#!/usr/bin/env node
// Claude Code Statusline - Enhanced Edition
// Shows pretty bars for: context usage, session (5h) usage, weekly (7d) usage
// Line 2: git status + token counts

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync } = require('child_process');

// ── Visual helpers ────────────────────────────────────────────────────────────

// Build a segmented bar using block characters.
// segments: total bar width; pct: 0-100
function makeBar(pct, segments, filled_char, empty_char) {
  const n = Math.round((Math.max(0, Math.min(100, pct)) / 100) * segments);
  return filled_char.repeat(n) + empty_char.repeat(segments - n);
}

// ANSI helpers — reset is explicit so colors never bleed across segments
const R = '\x1b[0m';

function color(ansi, text) { return `${ansi}${text}${R}`; }

// Named palette — every color defined once, used by name throughout
function dim(t)        { return color('\x1b[2m',           t); }
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

// ── Git status ────────────────────────────────────────────────────────────────
// Returns null when cwd is not inside a git repo (or git is not available).
// All commands use --no-optional-locks to avoid touching lock files.
function getGitInfo(cwd) {
  const opts = { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] };
  try {
    // Confirm we're in a git repo; get the root so relative paths are correct
    execSync('git rev-parse --git-dir', opts);
  } catch (_) {
    return null; // Not a git repo
  }

  const run = cmd => {
    try { return execSync(cmd, opts).trim(); } catch (_) { return ''; }
  };

  // Branch name (or short SHA when detached HEAD)
  const branch = run('git symbolic-ref --short HEAD') ||
                 run('git rev-parse --short HEAD') ||
                 '?';

  // Dirty file count: modified + added + deleted (tracked changes only + untracked)
  const statusLines = run('git status --porcelain --no-optional-locks');
  const dirtyCount  = statusLines ? statusLines.split('\n').filter(Boolean).length : 0;

  // Unpushed commits (commits on HEAD not on @{upstream})
  let unpushed = 0;
  const upstreamCheck = run('git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null');
  if (upstreamCheck) {
    const countStr = run('git rev-list --count @{u}..HEAD --no-optional-locks');
    unpushed = parseInt(countStr, 10) || 0;
  }

  return { branch, dirtyCount, unpushed };
}

// ── Context window normalization ──────────────────────────────────────────────
// Claude Code reserves ~16.5% for autocompact buffer; normalize to show 100%
// when that buffer is reached (consistent with the existing GSD statusline).
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
    const dir      = data.workspace?.current_dir || process.cwd();
    const session  = data.session_id || '';
    const dirname  = path.basename(dir);

    const homeDir   = os.homedir();
    const claudeDir = process.env.CLAUDE_CONFIG_DIR || path.join(homeDir, '.claude');

    // ── Context bar ────────────────────────────────────────────────────────
    let ctxPart = '';
    const remaining = data.context_window?.remaining_percentage;
    if (remaining != null) {
      const used = normalizeContextUsed(remaining);

      // Write bridge file for context-monitor PostToolUse hook
      if (session) {
        try {
          const bridgePath = path.join(os.tmpdir(), `claude-ctx-${session}.json`);
          fs.writeFileSync(bridgePath, JSON.stringify({
            session_id: session,
            remaining_percentage: remaining,
            used_pct: used,
            timestamp: Math.floor(Date.now() / 1000),
          }));
        } catch (_) {}
      }

      ctxPart = metricBar('CTX', used, 8);
    }

    // ── Token counts (session cumulative) ────────────────────────────────────
    let tokenPart = '';
    const totalIn  = data.context_window?.total_input_tokens;
    const totalOut = data.context_window?.total_output_tokens;
    if (totalIn != null && totalOut != null) {
      function fmtTokens(n) {
        if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + 'M';
        if (n >= 1_000)     return (n / 1_000).toFixed(1)     + 'k';
        return String(n);
      }
      tokenPart = `${cyan(bold('TOK'))} ${cyan(bold('IN'))} ${white(fmtTokens(totalIn))} ${mutedGray('·')} ${cyan(bold('OUT'))} ${white(fmtTokens(totalOut))}`;
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

    // ── GSD update available? ──────────────────────────────────────────────
    // Rendered as a distinct badge before the left section — never merged
    // into model name so it's visually separate and easy to spot.
    let gsdBadge = '';
    const cacheFile = path.join(claudeDir, 'cache', 'gsd-update-check.json');
    if (fs.existsSync(cacheFile)) {
      try {
        const cache = JSON.parse(fs.readFileSync(cacheFile, 'utf8'));
        if (cache.update_available) {
          // Bold yellow badge with clear separator after it
          gsdBadge = bold(yellow('⬆ /gsd:update')) + mutedGray(' ╱ ');
        }
      } catch (_) {}
    }

    // ── Git info ───────────────────────────────────────────────────────────
    let gitPart = '';
    const gitCwd = data.cwd || dir;
    const git    = getGitInfo(gitCwd);
    if (git) {
      // Branch: always shown
      gitPart = `${cyan(bold('GIT'))} ${white(git.branch)}`;

      // Dirty indicator: show count when there are changes, "clean" when not
      if (git.dirtyCount > 0) {
        gitPart += ` ${mutedGray('·')} ${cyan(bold('~'))}${white(String(git.dirtyCount))}`;
      } else {
        gitPart += ` ${mutedGray('·')} ${mutedGray('clean')}`;
      }

      // Unpushed commits
      if (git.unpushed > 0) {
        gitPart += ` ${mutedGray('·')} ${cyan(bold('↑'))}${white(String(git.unpushed))}`;
      }
    }

    // ── Assemble output ────────────────────────────────────────────────────
    // Line 1: [⬆ /gsd:update ╱ ] ModelName │ active task │ dirname  ║  CTX ████░░░░  nn%  5H ████░░  nn% ↺HH:MM  7D ████░░  nn%
    // Line 2: GIT branch  ~ n  ↑ n  ·  IN nn.nk  OUT nn.nk
    //
    // Visual hierarchy:
    //   - GSD badge: bold amber (attention-grabbing)
    //   - Model: soft blue (ambient context)
    //   - Task: bold amber (most important left-side info when present)
    //   - Dir: bright white (primary navigation anchor)
    //   - Separators: muted gray (structural, low weight)
    //   - Metric labels: bold cyan (scannable right-side anchors)
    //   - Bars + percentages: usage-colored (state at a glance)
    //   - Git branch/counts: bright white values, cyan labels

    const sep      = mutedGray(' │ ');
    const thickSep = mutedGray(' │ ');
    const dotSep   = mutedGray(' · ');

    const leftParts = [
      gsdBadge + softBlue(model),
      task ? bold(yellow(task)) : null,
      white(dirname),
    ].filter(Boolean).join(sep);

    const rightParts = [ctxPart, fiveHourPart, sevenDayPart]
      .filter(Boolean)
      .join(dotSep);

    const line1 = rightParts
      ? leftParts + thickSep + rightParts
      : leftParts;

    // Line 2: git + tokens (only rendered when there is something to show)
    const line2Parts = [gitPart, tokenPart].filter(Boolean).join(dotSep);
    const output     = line2Parts
      ? line1 + '\n' + line2Parts
      : line1;

    process.stdout.write(output);
  } catch (_) {
    // Silent fail — never break the statusline
  }
});
