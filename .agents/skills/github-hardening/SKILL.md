---
name: github-hardening
description: Review or update GitHub repository hardening guidance and its Terraform implementation under config/infra, including rulesets, required checks, scanning, permissions, provider pins, and plan/apply safety. Do not use for ordinary app code, generic template adaptation, release integrity, or routine workflow validation.
---

# GitHub hardening

Review or update GitHub-side controls and their Terraform implementation for this template or its derived repositories.

## Use this skill when
- updating repository hardening documentation
- changing or reviewing `config/infra` or plan/apply and token handling in `scripts/infra.sh`
- reviewing required GitHub settings for derived repositories
- changing workflow permissions, review protections, scanning guidance, or ruleset expectations
- adding or revising guidance around branch protection, code owners, secret scanning, push protection, or Dependabot

## Do not use this skill when
- the task is ordinary application code or a script change unrelated to GitHub hardening
- the task is primarily release-integrity design
- the task is primarily template adaptation
- the task only needs ordinary workflow validation

## Goals
- Keep the default path safe for a newly created repository.
- Document controls that cannot be enforced solely through files in git.
- Keep GitHub-side guidance aligned with current platform features and repository expectations.

## Supporting guidance

Read [Terraform hardening](references/terraform.md) when the task changes or reviews `config/infra`, its documentation, or `scripts/infra.sh` plan/apply and token handling. Follow `config/infra/AGENTS.md` for local safety and verification rules.

## Method
- Distinguish clearly between controls enforced in git, CI, Docker, and manual GitHub configuration.
- Treat `config/infra` as the concrete implementation example when reviewing GitHub-side guidance.
- Prefer minimal GitHub workflow permissions.
- Treat release-related GitHub workflows as sensitive and difficult to bypass.
- Keep required repository settings documented when they cannot be enforced in-repo.
- Keep recommendations consistent with the template's secure-by-default goals.
- Label optional controls clearly as optional.
- When changing rulesets, scanning, Dependabot, or repository settings, verify version-sensitive GitHub or provider behavior against current official documentation.

## Review topics

Select the topics relevant to the requested scope:
- branch protection or rulesets
- required pull requests
- required status checks
- code owner review
- secret scanning
- push protection
- dependency graph
- Dependabot alerts and security updates
- code scanning when supported

## Output expectations
- State what GitHub-side guidance changed and why.
- Call out which controls are manual versus enforced in-repo.
- Highlight gaps that remain outside the repository's direct control.
