# AGENTS.md

Instructions for coding agents working under `config/infra/`.

## Scope

This subtree is a Terraform-backed example for GitHub repository hardening. Treat
it as an adaptable example, not a universal policy for every repository.

Use the root `Makefile` as the public interface:

- `make infra` builds the infra image, formats, validates, and writes a reviewable
  plan
- `APPLY=true GITHUB_TOKEN=... make infra` applies only when the caller
  explicitly opts in

Companion changes in `scripts/infra.sh` should follow the same safety rules even
though that script lives outside this subtree.

## Local Rules

- Preserve plan-before-apply behavior. Do not make apply or destroy implicit.
- Keep tokens, credentials, state files, plan files, and provider caches out of
  code, examples, logs, and committed files.
- Keep `archive_on_destroy` behavior and any destructive semantics explicit in
  variables and documentation.
- Keep required status checks aligned with real GitHub Actions job names such as
  `test-code`, `test-repo`, and `scan-repo`.
- Keep provider versions, Docker image pins, lockfiles, generated-state
  exclusions, and documentation aligned.
- Verify version-sensitive Terraform provider and GitHub ruleset behavior
  against current official documentation before changing resource semantics or
  documented settings.
- Do not overstate GitHub-side controls that depend on repository visibility,
  organization policy, plan level, or manual settings outside Terraform.
- Preserve the solo-maintainer default posture unless the requested change
  intentionally changes review requirements.

## Documentation

Update `docs/terraform.md` when Terraform behavior, variables, provider
expectations, token handling, plan/apply behavior, or GitHub-side control
coverage changes.

Avoid expanding the root `README.md` unless the root workflow or public command
surface changes.

## Verification

For documentation-only changes, verify commands, paths, variable names, and
workflow job names against the current files.

For Terraform, Dockerfile, provider, variable, plan/apply, or infra script
changes, run:

```sh
make infra
```

Only run `APPLY=true make infra` when the user explicitly asks for a real apply
and provides the required GitHub token context. If a relevant check cannot be
run, state why.
