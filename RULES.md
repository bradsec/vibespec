# RULES.md

> These guidelines bias toward caution over speed. Apply judgment on trivial tasks.

## Behavioral Guidelines

### Think Before Coding
- State assumptions explicitly. If uncertain, ask.
- Present multiple interpretations instead of silently choosing one.
- Do not proceed when requirements are unclear.
- Inspect existing code and structure before making changes.
- Understand local conventions before modifying files.
- Consider downstream effects before modifying APIs, infrastructure, or workflows.

### Workspace Safety
- Check current file state before editing when practical.
- Do not overwrite user changes. Work with them, or ask when they block the task.
- Avoid destructive commands unless the user explicitly requests them.
- Keep generated files, lockfiles, and dependency changes intentional.

### Simplicity First
- Write the minimum code required. No speculative abstractions.
- Prefer standard library over external dependencies.
- Prefer explicit, readable logic over clever or hidden behavior.
- Avoid unnecessary frameworks, configuration systems, or build tooling.

### Surgical Changes
- Only modify what is necessary.
- Preserve existing style, structure, comments, and public APIs.
- Do not refactor unrelated code. Avoid broad rewrites unless explicitly requested.
- Keep changes isolated and reviewable.

### Goal-Driven Execution
- Convert requests into verifiable outcomes.
- Verify changes before claiming success. State what was and was not verified.
- Do not invent successful test results.
- Prefer incremental progress over large risky changes.

### Versions and Documentation
- When creating new projects or adding dependencies, use the latest stable production-safe
  release unless there is a specific reason not to (e.g. known incompatibility).
- Detect the existing package manager and dependency style from project files before
  adding or updating packages.
- Do not add dependencies for problems the standard library or existing project tools
  already solve well.
- Never guess at API signatures, CLI flags, or library interfaces from memory.
  Check official documentation or source before writing code against them.
- Do not assume a framework or tool works the same way it did at training time;
  verify anything version-sensitive before proceeding.
- State clearly when you have relied on training data rather than verified docs,
  and flag it as something the developer should confirm.
- Prefer canonical sources: official docs, release notes, and source code over
  blog posts, Stack Overflow, or AI-generated summaries.

### Agent Tools
- Use available skills, MCPs, repo tools, and official docs when they fit the task.
- Prefer local project context first, then official docs for version-sensitive facts.
- Verify that a tool, skill, or MCP resource exists before relying on it.
- Use subagents or parallel tools for independent investigation or review when available.
- Do not claim tool output, test results, or web findings unless you observed them.

## Coding Standards

### Quality
- Write clear, maintainable, production-quality code.
- Keep functions and modules focused on a single responsibility.
- Use descriptive naming. Avoid deeply nested logic.
- Favor composition over tightly coupled systems.
- Prefer deterministic and predictable behavior.
- Favor maintainability over premature optimization.

### Security
Treat security as a standing concern on every change. Identify the untrusted input, trust
boundary, and error path before changing sensitive code.

- Validate external input for type, length, format, and range. Prefer allowlists.
- Revalidate at trusted boundaries. Never rely on client-side validation alone.
- Use parameterized APIs for SQL, shell commands, templates, and serializers. Avoid `eval`
  and dynamic execution on user input.
- Encode output for its context. Prefer auto-escaping templates and `textContent`.
- Canonicalize paths and confine file access to an allowed base directory.
- Validate outbound request targets to reduce SSRF risk. Block internal, loopback, and
  metadata addresses unless explicitly intended.
- Enforce authorization server-side. Check object ownership on every access.
- Use vetted auth and session libraries. Store passwords only with slow salted hashes.
- Never hardcode or commit secrets. Avoid logging credentials, tokens, or personal data.
- Use TLS with certificate verification. Use standard crypto and CSPRNGs. No custom crypto.
- Pin dependencies and commit lockfiles. Prefer maintained packages and patch known CVEs.
- Set explicit limits for request size, uploads, recursion depth, and result counts.
- Disable debug modes and verbose user-facing errors in production.
- Explain residual security risk when it cannot be resolved in the change.

### Testing
- Write tests for new functionality unless explicitly told not to.
- Prefer writing tests before or alongside implementation, not as an afterthought.
- Run the smallest relevant verification before claiming completion.
- Prefer automated, deterministic, reproducible tests.
- Test behavior and outcomes, not implementation details or internal state.
- Cover edge cases, error paths, and boundary conditions, not just the happy path.
- Do not delete, skip, or weaken existing tests to make a build pass;
  fix the code or raise the issue explicitly.
- Avoid excessive mocking; prefer testing real behavior with real inputs where practical.
- Place test files consistently with existing project conventions.
- If tests cannot be run, explain why and what should be verified manually.
- Do not invent or fabricate test results.

### Architecture
- Prefer explicit data flow over hidden side effects.
- Keep dependency graphs simple.
- Avoid speculative architecture.
- Design for future maintainers, not hypothetical requirements.

## Go

- Prefer idiomatic Go and the standard library.
- Keep interfaces minimal; create them only when needed.
- Wrap errors with useful context. Avoid panics except for unrecoverable init failures.
- Use `context.Context` for cancellation. Prevent goroutine leaks.
- Use `gofmt`. Avoid stuttering names. Keep exported APIs minimal and stable.
- Structure: `cmd/`, `internal/`, `pkg/` (public reuse only). Separate transport, business logic, storage.
- Common default when no project-specific command exists: `go fmt ./... && go vet ./... && go test ./...`

## Python

- Follow PEP8. Use type hints where useful. Prefer virtual environments.
- Prefer `pathlib` over string path handling. Use explicit imports; avoid wildcards.
- Catch specific exceptions. Avoid broad exception swallowing or silent failures.
- Separate configuration, logic, and IO. Avoid circular imports.
- Common default when no project-specific command exists: `python -m pytest && ruff check .`

## JavaScript (Vanilla)

- Prefer clean vanilla JS before reaching for frameworks. Use ES modules where practical.
- Use `const` by default, `let` when needed, never `var`.
- Prefer `async/await` over complex promise chains. Avoid global mutable state.
- Always handle fetch errors. Check `response.ok`. Handle timeouts and retries.
- Prefer `textContent` over `innerHTML`. Never expose secrets in frontend code.

## Front-End Design

Avoid patterns that produce generic, AI-generated-looking interfaces. Design intentionally, not by default.

### Layout
- Do not center everything. Left-aligned content and asymmetric layouts signal intent.
- Avoid the hero-section default: large centered heading, subtext, single call-to-action button.
- Do not default to card grids for all content types. Match layout to content structure.
- Apply whitespace deliberately; uniform padding on every element signals template thinking.

### Color and Visual Treatment
- Avoid purple or blue gradients as a default design direction.
- Do not apply gradients decoratively. Use them only when they carry visual meaning.
- Limit the palette. Two or three intentional colors outperform a multi-stop gradient.
- Avoid glassmorphism (backdrop blur, semi-transparent panels) as a default surface treatment.
- Do not stack multiple box shadows for depth. Use one or none.

### Typography
- Do not default to Inter. Consider a system font stack, a serif, or a more purposeful choice.
- Avoid large hero text in thin or light weights.
- Establish typographic hierarchy through scale and weight, not decoration.
- Match line-height and measure to the reading context, not a design system's defaults.

### Components
- Do not apply uniform `border-radius` to every element. Vary it by purpose, or omit it entirely.
- Avoid icon-plus-label on every interactive element unless navigation genuinely benefits from it.
- Do not import a component library just to have styled elements. Write focused, minimal CSS.

### General
- Prefer purposeful constraints: a limited palette, a single typeface family, a clear grid.
- If the result looks like a Tailwind UI demo or a Shadcn starter, stop and reconsider.

## Shell

- Prefer POSIX `sh` for portability; use Bash only for Bash-specific features.
- For Bash scripts, use `#!/usr/bin/env bash` and `set -euo pipefail`.
- Quote variables (`"$var"`). Use `mktemp` for temp files. Use `trap` for cleanup.
- Keep scripts idempotent. Fail with clear error messages. Support dry-run for destructive ops.
- Never pass unvalidated input to `eval`, `bash -c`, or a subshell. Validate names against a
  strict pattern before using them in paths or commands.
- When fetching remote scripts, prefer pinning to a known revision and verifying a checksum
  over piping straight to a shell. Document the trust assumption where you cannot.
- Run `shellcheck` before committing.

## Git & GitHub

- Keep commits atomic and focused. Write meaningful messages. No secrets or generated artifacts.
- Prefer feature branches. Avoid direct commits to protected branches.
- Keep PRs small, focused, and reviewable. Note breaking changes.
- Before committing: `git diff && git status`.

## Docker & Infrastructure

- Prefer small images. Use multi-stage builds. Avoid unnecessary packages.
- Preserve existing volumes, labels, ports, and networking unless intentionally changing them.
- Prefer deterministic, repeatable deployments. Avoid accidental exposure of internal services.
- Assume Debian Linux and CLI-first workflows unless specified otherwise.

## AI / Automation

- Prefer composable systems. Avoid unnecessary agent complexity or orchestration layers.
- Keep automation understandable and debuggable.
- Prefer deterministic workflows. Preserve workflow logic unless intentionally refactoring.

## Output Style

### Prose and Documentation
- Do not use em dashes; use commas, colons, or restructure the sentence.
- Do not use AI-overused words: delve, underscore, harness, leverage, transformative,
  pivotal, realm, tapestry, robust, seamless, streamline, elevate, or similar corporate filler.
- Do not reflexively group adjectives or actions into triplets.
- Avoid contrast framing structures like "It's not just X, it's also Y."
- Vary sentence length naturally. Mix short sentences with longer ones; avoid uniform rhythm.
- Do not randomly bold phrases within prose for emphasis.
- Avoid rigid paragraph structure: topic sentence → evidence → "thus/ultimately" conclusion.
- Do not use vague authority: no "studies show", "experts agree", or similar unsourced claims.
- Do not use circular arguments that restate the premise as the conclusion.

### Code
- No emojis in code, comments, log output, or commit messages.
- No decorative comments or AI-style section headers (e.g. `// Main logic here`).
- No filler comments that restate what the code obviously does.
- Write comments that explain why, not what.

## Output Preferences

- Provide complete working examples. Avoid placeholders unless unavoidable.
- Keep explanations concise. Explain risky operations before suggesting them.
- Preserve existing project conventions unless intentionally changing them.
