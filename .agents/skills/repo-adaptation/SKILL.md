---
name: repo-adaptation
description: Use when adapting or customizing this repository to meet the needs of the source code under `src/`, including language and framework needs, dependencies, runtime behavior, Docker, Makefile targets, and customization surfaces. Do not use for routine bug fixes, small refactors, pure workflow validation, GitHub-settings-only work, or release-integrity-only work.
---

# Repo adaptation

Use this skill when adapting or customizing this repository to meet the needs of the source code under `src/`.

## Use this skill when
- inspecting `src/` to identify the project language, framework, dependency, runtime, build, test, Docker, and Makefile needs
- adapting the repository for a new Go, Node.js, SQL, or small polyglot project
- changing `config/project.cfg`, `Dockerfile`, `Makefile`, `scripts/`, or default project scaffolding
- changing the default customization surface for derived repositories

## Do not use this skill when
- making a routine bug fix or small refactor within the repository
- only validating existing behavior without changing the adaptation model or workflow surface
- only updating GitHub-side settings guidance
- only changing release integrity or artifact-verification behavior
- only changing the Terraform-backed GitHub hardening workspace under `config/infra`

## Goals
- Preserve the secure-by-default posture of the repository.
- Preserve the stable public interface unless there is a strong reason to change it.
- Keep the repository container-first, reproducible, and easy to review.
- Keep fork-specific behavior explicit and reviewable.

## Method
- Treat `Makefile` as the primary user-facing interface.
- Treat `scripts/` as implementation details.
- Treat `config/project.cfg` as the main customization point for project-specific commands and settings.
- Inspect inserted project code before choosing workflow changes:
  - identify the primary language and framework
  - identify package managers, lockfiles, dependency manifests, and runtime entrypoints
  - identify build, test, lint, format, smoke-test, and release commands
  - identify Docker image, port, volume, and environment-variable needs
  - identify whether root `Makefile` targets should call existing project commands or add thin wrappers
- Keep changes small and reviewable.
- For Terraform-backed GitHub hardening changes under `config/infra`, use `terraform-hardening` instead.
- If a change weakens security, reproducibility, or reviewability, document the reason explicitly.
- Update documentation when the customization surface, workflow, or security posture changes.

## Output expectations
- State what was adapted and why.
- Call out any public-interface changes.
- Call out any security or reproducibility tradeoffs.
- List the documentation updated.
