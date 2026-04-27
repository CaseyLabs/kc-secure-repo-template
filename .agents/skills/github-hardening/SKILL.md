---
name: github-hardening
description: Use when updating or reviewing GitHub-side hardening guidance for derived repositories, including required settings, rulesets, scanning, review protections, and workflow permissions. Use terraform-hardening instead for Terraform-backed changes under config/infra. Do not use for ordinary in-repo implementation changes unless the task is primarily about documented GitHub controls.
---

# GitHub hardening

Use this skill when working on GitHub-side hardening guidance for this template or its derived repositories.

## Use this skill when
- updating repository hardening documentation
- reviewing required GitHub settings for derived repositories
- changing workflow permissions, review protections, scanning guidance, or ruleset expectations
- adding or revising guidance around branch protection, code owners, secret scanning, push protection, or Dependabot

## Do not use this skill when
- the task is primarily an in-repo code or script change
- the task is primarily release-integrity design
- the task is primarily template adaptation
- the task is primarily Terraform-backed GitHub repository hardening under `config/infra`; use `terraform-hardening`
- the task only needs ordinary workflow validation

## Goals
- Keep the default path safe for a newly created repository.
- Document controls that cannot be enforced solely through files in git.
- Keep GitHub-side guidance aligned with current platform features and repository expectations.

## Method
- Distinguish clearly between controls enforced in git, CI, Docker, and manual GitHub configuration.
- Treat `config/infra` as the concrete implementation example when reviewing GitHub-side guidance, but use `terraform-hardening` for direct infra edits.
- Prefer minimal GitHub workflow permissions.
- Treat release-related GitHub workflows as sensitive and difficult to bypass.
- Keep required repository settings documented when they cannot be enforced in-repo.
- Keep recommendations consistent with the template's secure-by-default goals.
- Label optional controls clearly as optional.
- When changing rulesets, scanning, Dependabot, or repository settings, verify version-sensitive GitHub or provider behavior against current official documentation.

## Minimum topics to review
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
