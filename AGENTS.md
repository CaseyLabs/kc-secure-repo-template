# AGENTS.md

Instructions for coding agents working in this repository.

## Project overview

This repository is a secure-by-default GitHub repository template for new projects.

It is intended to remain:

- container-first for build, test, lint, and release
- easy to adapt without weakening security, reproducibility, or review quality

## Project defaults

- Use TDD by default for new features, bug fixes, and behavior changes
  - However, write tests for **code** only, do not write tests for written content/filenames/directory structures, etc.

## Public interface

Use `make help` as the source of truth for available root targets. Prefer a small stable root `Makefile` interface, with this core set when supported by the repository:

```shell
make build
make test
make run
make stop
make status
make logs
make clean
make update
make example
```

Use `make scan` for template security and workflow checks, and `make dist` for release artifact and integrity outputs when those areas are affected. Treat specialized targets such as `make shell` and `make infra` as task-specific conveniences rather than the core public interface.

Rules:

1. Keep the root public interface condensed and easy to remember.
2. Hide extra complexity behind `scripts/`, `config/project.cfg`, and compatibility targets when needed.

## Skill routing

Use a repo-local skill only when a matching skill actually exists in `.agents/skills/` and its description matches the task.

Typical routing:

- Use `template-adaptation` when adapting this template to a new project or revising customization points.
- Use `template-validation` when changing `Makefile`, `Dockerfile`, `scripts/`, tests, packaging manifests, CI, or release workflows.
- Use `github-hardening` when updating GitHub-side hardening guidance or required repository settings.
- Use `template-infra-hardening` when changing or reviewing the Terraform-backed GitHub repository hardening workspace under `config/infra`.
- Use `release-integrity` when working on SBOMs, attestations, artifact scanning, signing guidance, or release workflow safety.
- Use `language-profile-guidance` when adding or revising optional Go, Node.js, SQL, or polyglot guidance.

If no matching skill exists, follow this file and the repository itself.

## Before making changes

- Read the relevant files before editing.
- Identify the affected workflow from the repository itself before choosing checks or commands.
- For complex, ambiguous, multi-step, or high-risk work, inspect the repository first, then make a short plan and ask clarifying questions only for unresolved intent or tradeoffs.
- If the task depends on tool versions, commands, flags, APIs, package versions, or installation steps, verify them against the latest official documentation before acting.
- Prefer targeted changes over broad rewrites.

## Repository rules

- `scripts/` contains implementation details for build, test, lint, release, and security checks.
- `config/project.cfg` is the main customization point.
- `Dockerfile` provides the development and CI runtime baseline.
- `.github/workflows/` should call `make` targets instead of duplicating project logic inline.
- Keep template packaging and release manifests aligned.
- Follow the repository's existing structure, naming, and style.
- Do not introduce new dependencies unless necessary and justified.
- Preserve intended behavior unless the task explicitly requires a change.
- Preserve backwards compatibility unless the task explicitly allows a breaking change.
- Do not add broad error handling that hides failures.
- Prefer explicit error propagation or clear surfaced failures over silent fallbacks.
- When behavior changes, update or add the relevant tests.
- Keep secrets, tokens, and credentials out of code, logs, fixtures, examples, and documentation.

## Security and reproducibility

- Build, test, lint, and release through non-root Docker-based workflows unless the task explicitly requires a host-only action.
- Do not require host-installed language toolchains for normal use.
- Keep Dockerfiles deterministic and easy to audit.
- Prefer lockfiles, checksums, pinned versions, and pinned GitHub Actions where practical.
- Verify checksums or signatures for downloads when feasible.
- Keep generated artifacts and caches out of the Docker build context.
- Ensure local and GitHub Actions workflows call the same `make` targets.

## Verification

Run the smallest relevant verification stack that gives high confidence for the files changed.

Minimum expectations:

- For documentation-only changes, verify that examples, commands, paths, and references still match the repository.
- For code, test, Docker, script, packaging, CI, security, or release changes, run the relevant existing `make` targets and any directly affected checks.
- Do not claim success without verification.
- If a needed check cannot be run, state that clearly and explain why.

## Review

When reviewing changes or using `/review`:

1. Read `.agents/code_review.md` first for repository-wide review criteria.
2. Apply any more specific guidance from the closest active `AGENTS.md`.
3. Prioritize the risks named there, especially template security, reproducibility, workflow drift, public-interface stability, and documentation accuracy.

## Documentation

- Update documentation when code changes materially affect setup, usage, behavior, configuration, security posture, or developer workflows.
- Keep documentation changes tightly scoped to the task.
- Ensure documentation reflects the actual workflow.
- Avoid changing the root `README.md` unless it is factually wrong or behavior has changed; prefer focused subfolder `README.md` files for new detail.
- When the same mistake, review comment, or workflow confusion appears more than once, propose a targeted update to `AGENTS.md` or the relevant `.agents/skills/*/SKILL.md`, but do not change instruction files unless the task explicitly asks for it.
- Add or update a subtree `AGENTS.md` only when that subtree has real local rules, hazards, or verification needs.
- Add code comments for non-obvious workflow, security, reproducibility, or template-adaptation decisions; avoid comments that restate obvious code.

## Definition of done

A change is done when:

1. the requested change is implemented cleanly
2. relevant documentation and workflow references are updated when behavior changes
3. relevant checks were run, or any verification gap is clearly stated
4. documented workflows are preserved unless intentionally revised
5. generic template boundaries remain intact
