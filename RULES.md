# RULES.md

Use these as default instructions for coding agents. Keep project-specific
architecture, commands, and style rules in the repository where they apply.

## Working Style

- Understand the request before changing files. If the goal is ambiguous, ask a
  concise question or state the assumption you will use.
- Inspect the existing project structure, conventions, and tooling before adding
  new patterns.
- Prefer small, focused changes. Avoid unrelated refactors and broad rewrites.
- Do not overwrite user changes. If the worktree is dirty, preserve unrelated
  edits and work around them.
- Avoid destructive commands unless the user explicitly asks for them.
- Use official documentation or local source code for version-sensitive APIs,
  packages, CLI flags, and framework behavior. Do not guess from memory.
- State what you verified before claiming a task is complete.

## Implementation

- Write clear, maintainable code that matches the existing style.
- Prefer simple, explicit logic over clever abstractions.
- Use the standard library and existing project dependencies before adding new
  packages.
- Add an abstraction only when it removes real duplication or clarifies a stable
  boundary.
- Keep functions and modules focused. Make data flow and side effects easy to
  follow.
- Preserve public APIs, config formats, file paths, and user-facing behavior
  unless the requested change requires altering them.
- Handle errors deliberately. Do not swallow failures silently.
- Keep generated files, lockfiles, migrations, and dependency updates
  intentional and easy to explain.

## Testing and Verification

- Add or update tests for behavior changes when the project has a practical test
  path.
- Prefer tests that check observable behavior rather than implementation details.
- Cover important edge cases and error paths, not only the happy path.
- Run the smallest relevant verification command before reporting success.
- If a test or command cannot be run, explain why and name the closest useful
  verification.
- Do not delete, skip, or weaken tests to make a failure disappear. Fix the code
  or report the risk.
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

- Detect the package manager and workflow from project files before installing
  or updating anything.
- Prefer maintained, widely used packages with clear ownership.
- Pin or lock dependencies according to the project's existing practice.
- When adding a dependency, explain why existing tools are insufficient.
- Respect project formatting, linting, and build commands. If none are obvious,
  use conservative language defaults.

## Documentation

- Update docs when behavior, setup, commands, configuration, or public APIs
  change.
- Keep documentation concise and specific. Avoid tutorials in always-loaded
  instruction files.
- Prefer links to canonical docs over copying long reference material.
- Use Markdown headings and bullets to make instructions easy to scan.
- Remove stale instructions when they no longer affect behavior.

## Git

- Keep commits and diffs focused.
- Do not revert user changes unless the user asks.
- Before committing or handing off, check `git diff` and `git status`.
- Do not commit secrets, local machine paths, build artifacts, or unrelated
  generated files.

## Communication

- Be direct and concise.
- Lead with findings, decisions, or completed work rather than process detail.
- Explain meaningful tradeoffs and risks.
- Use file paths, commands, and concrete examples when they help.
- Do not overstate certainty. Separate observed facts from assumptions.
- Avoid filler language, marketing tone, and vague authority.
- Do not use emojis in code, logs, comments, commit messages, or technical docs.
- Do not use em dashes; use commas, colons, or separate sentences.
