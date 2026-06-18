# vibespec

Quick-start setup for AI coding environments on Debian/Ubuntu-style Linux systems.

Installs AI coding CLI tools, deploys shared coding rules, and sets up statuslines.

The included `RULES.md` reflects personal coding preferences. Review it before installing: those rules may not suit every developer, project, or task.

## Quick start

```bash
git clone https://github.com/bradsec/vibespec.git
cd vibespec
bash vibespec.sh
```

Or run directly without cloning (scripts load from GitHub):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bradsec/vibespec/main/vibespec.sh)
```

> Review scripts before running: `less vibespec.sh`

## What it does

| Menu option | What it installs |
|-------------|-----------------|
| Install AI Coding CLI Tools | nvm, Claude Code, Codex, Antigravity CLI, plus verify, replace, and full-removal actions |
| Configure AI Coding Rules | Deploys `RULES.md` to each tool's config path with the correct filename header |
| Install Status Lines | Installs or resets statusline configuration for Claude Code, Codex, and Antigravity CLI |

The menu uses local scripts when the repo is cloned. When run directly from GitHub, it fetches helper scripts from the `main` branch as needed.

## AI coding rules (`RULES.md`)

`RULES.md` is the source-of-truth instruction file deployed to all AI coding tools. It is written to be model-agnostic and deliberately lean: short, concrete directives that steer for the best results without burning the limited instruction budget that every model and project shares. It covers: working style, implementation, testing and verification, security and safety, dependencies and tooling, documentation, Git, and communication.

Each tool receives a copy with its first line set to `# <filename>` (e.g. `# CLAUDE.md`, `# AGENTS.md`).

Rule installation fetches the current `RULES.md` from GitHub when possible, then falls back to the local file. Existing config files are compared before replacement. When a change is needed, the old file is backed up with a dated `.bak` suffix and the script prints both SHA256 hashes.

Cross-tool config paths:

| Tool | Config path |
|------|------------|
| Claude Code | `~/.claude/CLAUDE.md` |
| Codex | `~/.codex/AGENTS.md` |
| Antigravity CLI | `~/.gemini/AGENTS.md` |

## Requirements

- Debian/Ubuntu Linux
- `bash` 4+
- `curl` or `wget`
- `python3` for install-state tracking and some config file edits
- `node` for Node-based CLIs and command-backed statusline formatters

The direct run command uses `curl` and Bash process substitution.

Node.js can be installed via nvm from the tools setup. Restart your terminal and run `nvm install --lts && nvm use --delete-prefix --lts` before installing Node-based CLIs.

If an old or broken Node.js install is being detected, use `Replace Node.js/nvm` from the tools menu. It removes apt-managed `nodejs`/`npm`, removes `~/.nvm`, reinstalls nvm, then installs and uses the LTS Node release.

`Verify installers (no install)` checks each installer source without installing anything. It confirms the install functions are present, queries the npm registry for the Claude Code package, and sends a read-only request to the Codex and Antigravity CLI installer URLs, reporting the HTTP status for each. The individual install options also run this check first and stop with `<tool> installer not available` rather than attempt an install whose source cannot be reached.

`Remove ALL agents + wipe all config (DESTRUCTIVE)` is a full teardown gated behind a typed `CONFIRM`. It uninstalls the npm packages and command shims for Claude Code, Codex, and Antigravity CLI, then deletes `~/.claude` (agents, skills, settings, chat history, projects, and saved memory), `~/.claude.json`, `~/.gemini/antigravity-cli`, the vibespec rule files in `~/.codex` and `~/.gemini`, the Codex statusline script and config entry, and the vibespec install state in `~/.config/vibespec`. It does not remove Node.js or nvm. There is no backup and the action cannot be undone.

## Install state

Successful tool, rules, and statusline installs are recorded in:

```text
~/.config/vibespec/installs.json
```

Set `VIBESPEC_STATE_DIR` to write that file somewhere else. If `python3` is not available, the installer continues and skips state recording.

## Status lines

All statusline scripts live in `statuslines/`.

| Tool | Current behavior |
|------|------------------|
| Claude Code | Installs a documented command-backed statusline showing context usage, rate limits, git status, and token counts. |
| Codex | Installs the local formatter script and configures supported built-in `tui.status_line` items in `~/.codex/config.toml`. Command-backed custom statuslines are not supported yet. |
| Antigravity CLI | Installs a documented command-backed statusline showing context usage, agent state, git status, and token counts. |

The statusline menu also includes reset actions to restore each tool's original statusline behavior. Resets remove only the statusline-related setting for the selected tool and leave unrelated config keys intact.

## Development

Run the test suite:

```bash
bash tests/config-rules.sh
bash tests/install-state.sh
bash tests/statusline-installers.sh
```

Lint the shell scripts:

```bash
shellcheck vibespec.sh src/*.sh statuslines/*.sh tests/*.sh
```

## License

MIT
