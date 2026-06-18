# RULES.md

Default instructions for coding agents. Keep project-specific architecture,
setup, test, lint, build, and style commands in the repository where they apply.
These defaults do not guess project-specific details.

## Working Style

- Understand the request before changing files. If the goal is ambiguous, ask a
  concise question or state the assumption you will use.
- Follow the most specific applicable instruction; repository, directory, and
  user instructions override these defaults. If instructions genuinely conflict
  and precedence does not resolve it, stop and ask rather than guessing.
- Inspect existing structure, conventions, and tooling before adding new patterns.
- When a skill, subagent, or connected tool (such as an MCP server) is designed
  for the task, use it instead of an ad-hoc approach.
- Make small, focused changes. Do not reformat, rename, or reorganize unrelated
  code while making a focused change.
- Deliver what was asked. Surface related problems or improvements as suggestions
  instead of bundling them in.
- If repeated attempts to fix something fail, stop and report what was tried and
  ruled out rather than continuing to guess.
- Do not overwrite user changes. In a dirty worktree, preserve unrelated edits.
- Avoid destructive commands unless the user explicitly asks for them.
- For version-sensitive APIs, packages, CLI flags, and framework behavior, use
  official docs or local source. Do not guess from memory.
- Work token efficiently: read only the file sections you need, do not re-read
  unchanged files, and filter or truncate large command output at the source.

## Subagents

- Delegate independent, parallel, broad-search, or large-output work. Keep small
  sequential edits in the main conversation.
- Ask subagents for conclusions, file paths, line references, and uncertainty,
  not full transcripts. Verify their claims before relying on them.
- Give subagents only the context they need. Avoid passing history, which biases
  results.
- Run subagents in parallel only when their targets are disjoint. Sequence any
  that might write the same files.
- Match model capability to task: smaller or faster models for trivial work,
  stronger models for design, debugging, and complex reasoning.

## Implementation

- Match the existing style and conventions of the surrounding code.
- Prefer simple, explicit logic over clever abstractions. Add an abstraction only
  when it removes real duplication or clarifies a stable boundary.
- Use the standard library and existing project dependencies before adding new
  packages.
- Comment only what the code cannot express: invariants, constraints, and the
  reason behind non-obvious choices. Do not narrate edits or restate the code.
- Preserve public APIs, config formats, file paths, and user-facing behavior
  unless the requested change requires altering them.
- Handle errors deliberately. Do not swallow failures silently.
- Keep generated files, lockfiles, migrations, and dependency updates intentional
  and easy to explain.

## Testing and Verification

- Prefer test-first for behavior changes where practical: add a focused failing
  test, make the smallest change to pass it, then refactor while keeping tests
  green.
- Prefer tests that check observable behavior, not implementation details. Cover
  edge cases and error paths, not only the happy path.
- Treat a task as done only when the smallest relevant verification command
  passes. Run it before claiming completion, and state what you verified.
- When a command fails, read the error output before retrying or changing approach.
- If a test or command cannot be run, explain why and name the closest useful
  verification.
- Do not delete, skip, or weaken tests to hide a failure. Fix the code or report
  the risk.
- Never invent test results, tool output, or external facts.

## Security and Safety

- Treat external input, files, network responses, environment variables, and
  command arguments as untrusted.
- Validate input for type, length, format, and range. Prefer allowlists.
- Use parameterized APIs for SQL, shell commands, templates, and serializers.
- Avoid `eval`, dynamic execution, and shell interpolation on untrusted input.
- Encode output for its destination context.
- Confine filesystem access to intended paths. Normalize paths before enforcing
  directory boundaries.
- Enforce authorization on the server side and check object ownership where it
  matters.
- Never hardcode or commit secrets. Avoid logging tokens, credentials, personal
  data, and sensitive payloads.
- Use established cryptography, TLS verification, and secure randomness. Do not
  invent crypto.
- Keep production defaults safe: no debug modes, broad CORS, permissive auth, or
  verbose user-facing errors unless explicitly justified.

## Dependencies and Tooling

- Detect the package manager and workflow from project files before installing or
  updating anything.
- Prefer maintained, widely used packages with clear ownership. When adding a
  dependency, explain why existing tools are insufficient.
- Pin or lock dependencies according to the project's existing practice.
- Avoid interactive commands in automation. Use non-interactive flags, and do not
  leave long-running processes active unless needed for verification.

## Documentation

- Update docs when behavior, setup, commands, configuration, or public APIs change.
- Keep documentation concise and specific. Prefer links to canonical docs over
  copying long reference material.
- Remove stale instructions when they no longer affect behavior.

## Git

- Keep commits and diffs focused.
- Do not commit, push, tag, or open pull requests unless the user asks.
- Author commits under the user's configured git identity only. Do not add AI
  agent names, co-author trailers, or tool attributions.
- Do not revert user changes unless the user asks.
- Check `git diff` and `git status` before committing or handing off.
- Do not commit secrets, local machine paths, build artifacts, or unrelated
  generated files.

## Communication

- Lead with findings, decisions, or completed work. Keep responses as short as
  clarity allows.
- Do not restate the request or echo unchanged code already visible in the diff.
- Explain meaningful tradeoffs and risks.
- Do not overstate certainty. Separate observed facts from assumptions.
- When blocked, state the blocker and the exact input needed to continue.
- Do not use emojis in code, logs, comments, commit messages, or technical docs.
- Do not use em dashes; use commas, colons, or separate sentences.
