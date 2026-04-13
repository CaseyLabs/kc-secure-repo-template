---
name: template-infra-hardening
description: Use when changing or reviewing the Terraform-backed GitHub repository hardening workspace under config/infra, including provider pins, rulesets, default branch protection, required checks, secret scanning, Dependabot security updates, token handling, plan/apply behavior, and infra documentation. Do not use for ordinary app code, generic release integrity, generic template adaptation, or non-infra GitHub Actions changes unless they directly affect hardening expectations.
---

# Template infra hardening

Use this skill when working on the Terraform-backed GitHub repository hardening workspace in `config/infra`.

## Use this skill when
- changing Terraform resources, variables, provider pins, lockfiles, or documentation under `config/infra`
- reviewing branch rulesets, required status checks, merge protections, signed commits, or default branch handling
- changing secret scanning, push protection, Dependabot security updates, vulnerability alerts, or repository security settings
- changing `scripts/infra.sh` behavior that affects plan/apply safety or GitHub token handling
- aligning infra hardening guidance with the root `Makefile`, GitHub Actions jobs, or template documentation

## Do not use this skill when
- the task is ordinary application code, release integrity, or generic template adaptation
- the task is only GitHub Actions workflow implementation with no infra hardening impact
- the task is only validating existing behavior; use `template-validation`
- the task is only general GitHub hardening documentation with no Terraform workspace change; use `github-hardening`

## Goals
- Keep the Terraform example safe for derived repositories to adapt.
- Preserve clear plan-before-apply behavior and explicit token requirements.
- Keep GitHub-side controls aligned with the template's secure-by-default goals.
- Avoid making solo-maintainer defaults look stronger than they are.

## Method
- Treat `config/infra` as a reviewed example, not a universal policy for every repository.
- Verify version-sensitive Terraform provider and GitHub ruleset behavior against current official documentation before changing resource semantics or documented settings.
- Keep provider versions, lockfiles, Docker image pins, and generated-state exclusions aligned.
- Keep required status checks aligned with real workflow job names, especially `build`, `test`, and `scan`.
- Keep secrets and tokens out of Terraform files, examples, plans, logs, and documentation.
- Prefer explicit variables and reviewed defaults over hidden fallbacks.
- Pair with `template-validation` when changes require `make infra`, workflow alignment, or packaging-manifest checks.

## Review priorities
- GitHub token exposure or overbroad token expectations
- destructive apply or destroy behavior
- ruleset bypass or weaker-than-documented protections
- drift between required checks and actual workflow job names
- provider, lockfile, Docker image, or documentation mismatch
- repository-specific assumptions that should stay configurable

## Output expectations
- State what infra hardening behavior changed and why.
- Call out any GitHub-side controls that remain manual or environment-dependent.
- List the validation run, especially `make infra` or targeted Terraform checks when applicable.
