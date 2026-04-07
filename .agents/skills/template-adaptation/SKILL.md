---
name: template-adaptation
description: Adapt this secure repository template to a new project while preserving the stable Makefile interface, container-first workflow, security defaults, and reproducibility guarantees. Do not use for routine bug fixes, small refactors, or pure validation work.
---

# Template adaptation

Use this skill when adapting this repository template to a new project.

## Use this skill when
- initializing a new derived repository from this template
- adapting the template for a Go, Node.js, SQL, or small polyglot project
- changing `project.env`, `Dockerfile`, `Makefile`, `scripts/`, or default project scaffolding
- changing the default customization surface for derived repositories

## Do not use this skill when
- making a routine bug fix or small refactor within the template
- only validating existing behavior without changing the adaptation model
- only updating GitHub-side settings guidance
- only changing release integrity or artifact-verification behavior

## Goals
- Preserve the secure-by-default posture of the template.
- Preserve the stable public interface unless there is a strong reason to change it.
- Keep the repository container-first, reproducible, and easy to review.
- Avoid introducing product-specific assumptions into the generic template.

## Method
- Treat `Makefile` as the primary user-facing interface.
- Treat `scripts/` as implementation details.
- Treat `project.env` as the main customization point for project-specific commands and settings.
- Keep changes small and reviewable.
- Prefer optional language-specific extensions over baking language-specific logic into the generic template.
- If a change weakens security, reproducibility, or reviewability, document the reason explicitly.
- Update documentation when the customization surface, workflow, or security posture changes.

## Output expectations
- State what was adapted and why.
- Call out any public-interface changes.
- Call out any security or reproducibility tradeoffs.
- List the documentation updated.
