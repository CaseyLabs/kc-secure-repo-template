# AGENTS.md

Instructions for coding agents working in this repository.

## Project overview

This repository is a secure-by-default GitHub repository template for new projects.

It is intended to remain:

- language-agnostic by default
- container-first for build, test, lint, and release
- small in public interface
- safe for GitHub-hosted CI by default
- easy to adapt without weakening security, reproducibility, or review quality

It must not become:

- a product-specific app template
- a monorepo framework
- a kitchen-sink dev environment
- a host-tooling-first workflow
- a substitute for GitHub organization policy or repository settings

## Instruction layering

- Follow the most specific active `AGENTS.md` for the directory you are working in.
- Keep repo-wide rules in this file.
- Keep task-specific guidance in dedicated files when that is more precise than expanding this file.
- Use nested `AGENTS.md` files only when a subdirectory genuinely needs different instructions.

## Read first

Before making changes, read the files most relevant to the task. Start with:

- `AGENTS.md`
- `README*`
- `Makefile`
- `project.env`
- `Dockerfile`
- `.github/workflows/`
- any files directly touched by the task
- `.agents/skills/` when the task matches an existing skill

## Project defaults

- This is a container-first repository. Use Docker-based workflows for build, test, lint, and release unless the task explicitly requires a host-only action.
- Prefer non-root containers unless the task explicitly requires elevated privileges.
- Use the root `Makefile` as the main developer entrypoint.
- Keep the public `Makefile` interface small and stable.
- Use TDD by default for new features, bug fixes, and behavior changes when practical.
- Prefer deterministic and reproducible workflows. Pin versions, images, and GitHub Actions where practical.

## Public interface

Prefer a small stable root `Makefile` interface. Use the applicable subset of these targets when supported by the repository:

```shell
make build
make test
make run
make stop
make status
make logs
make clean
make shell
make update
make example
```

Rules:

1. Keep the root public interface condensed and easy to remember.
2. Hide extra complexity behind `scripts/`, `project.env`, and compatibility targets when needed.
3. Keep the interface consistent across derived repositories when practical.
4. Do not add new public root targets unless there is a clear recurring need.

## Skill routing

Use a repo-local skill only when a matching skill actually exists in `.agents/skills/` and its description matches the task.

Typical routing:

- Use `template-adaptation` when adapting this template to a new project or revising customization points.
- Use `template-validation` when changing `Makefile`, `Dockerfile`, `scripts/`, tests, packaging manifests, CI, or release workflows.
- Use `github-hardening` when updating GitHub-side hardening guidance or required repository settings.
- Use `release-integrity` when working on SBOMs, attestations, artifact scanning, signing guidance, or release workflow safety.
- Use `language-profile-guidance` when adding or revising optional Go, Node.js, SQL, or polyglot guidance.

If no matching skill exists, follow this file and the repository itself.

## Before making changes

- Read the relevant files before editing.
- Identify the existing build, test, lint, format, type-check, CI, and release workflow from the repository itself.
- If the task depends on tool versions, commands, flags, APIs, package versions, or installation steps, verify them against the latest official documentation before acting.
- Prefer official documentation and primary sources over third-party summaries.
- Prefer targeted changes over broad rewrites.

## Repository rules

- `Makefile` is the stable public interface.
- `scripts/` contains implementation details for build, test, lint, release, and security checks.
- `project.env` is the main customization point.
- `Dockerfile` provides the development and CI runtime baseline.
- `.github/workflows/` should call `make` targets instead of duplicating project logic inline.
- Keep template packaging and release manifests aligned.
- Follow the repository's existing structure, naming, and style.
- Do not introduce new dependencies unless necessary and justified.
- Do not rewrite large areas of code when a targeted fix is sufficient.
- Preserve intended behavior unless the task explicitly requires a change.
- Preserve backwards compatibility unless the task explicitly allows a breaking change.
- Do not add broad error handling that hides failures.
- Prefer explicit error propagation or clear surfaced failures over silent fallbacks.
- When behavior changes, update or add the relevant tests.
- Keep secrets, tokens, and credentials out of code, logs, fixtures, examples, and documentation.
- Do not change CI, infrastructure, or release workflows unless the task requires it.

## Security and reproducibility

- Build, test, lint, and release through Docker-based workflows only.
- Do not require host-installed language toolchains for normal use.
- Keep Dockerfiles deterministic and easy to audit.
- Prefer lockfiles, checksums, pinned versions, and pinned GitHub Actions where practical.
- Keep secret scanning enabled in the default CI path.
- Prefer minimal GitHub workflow permissions.
- Treat release workflows as sensitive and difficult to bypass.
- Verify checksums or signatures for downloads when feasible.
- Keep generated artifacts and caches out of the Docker build context.
- If a change weakens a default, document the reason explicitly.
- Ensure local and GitHub Actions workflows call the same `make` targets.

## Verification

Run the smallest relevant verification stack that gives high confidence for the files changed.

Minimum expectations:

- For documentation-only changes, verify that examples, commands, paths, and references still match the repository.
- For code, test, Docker, script, packaging, CI, security, or release changes, run the relevant existing `make` targets and any directly affected checks.
- Prefer Docker-driven verification through the repository's `Makefile` targets.
- Do not claim success without verification.
- If a needed check cannot be run, state that clearly and explain why.

## Review

When reviewing changes or using `/review`:

1. Read `./code_review.md` first for repository-wide review criteria.
2. Apply any more specific guidance from the closest active `AGENTS.md`.
3. Prioritize findings involving:
   - correctness or regressions
   - weakened security defaults
   - reduced reproducibility
   - drift between local, CI, and release workflows
   - unnecessary expansion of the public interface
   - documentation that no longer matches implementation

## Documentation

- Update documentation when code changes materially affect setup, usage, behavior, configuration, security posture, or developer workflows.
- Keep documentation changes tightly scoped to the task.
- Ensure documentation reflects the actual Docker and `Makefile` workflow.
- When the same mistake, review comment, or workflow confusion appears more than once, propose a targeted update to `AGENTS.md` or the relevant `.agents/skills/*/SKILL.md`, but do not change instruction files unless the task explicitly asks for it.

## Definition of done

A change is done when:

1. the requested change is implemented cleanly
2. the relevant `make` targets and documented workflows still work, unless intentionally revised
3. documentation is updated for any changed workflow or control
4. tests or other relevant checks were run, or any verification gap is clearly stated
5. the change does not introduce product-specific assumptions into the generic template
