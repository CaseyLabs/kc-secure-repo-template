# Template infra hardening

Use this reference when working on the Terraform-backed GitHub repository hardening workspace in `config/infra`.

## Read this reference when
- changing Terraform resources, variables, provider pins, lockfiles, or documentation under `config/infra`
- reviewing branch rulesets, required status checks, merge protections, signed commits, or default branch handling
- changing secret scanning, push protection, Dependabot security updates, vulnerability alerts, or repository security settings
- changing `scripts/infra.sh` behavior that affects plan/apply safety or GitHub token handling
- aligning infra hardening guidance with the root `Makefile`, GitHub Actions jobs, or template documentation

## Goals
- Keep the Terraform example safe for derived repositories to adapt.
- Preserve clear plan-before-apply behavior and explicit token requirements.
- Keep GitHub-side controls aligned with the template's secure-by-default goals.
- Avoid making solo-maintainer defaults look stronger than they are.

## Method
- Read `config/infra/AGENTS.md` before working on the workspace or its companion `scripts/infra.sh`.
- Treat `config/infra` as a reviewed example, not a universal policy for every repository.
- Preserve plan-before-apply behavior. Apply only when the user explicitly requests it and supplies the required token context.
- Verify version-sensitive Terraform provider and GitHub ruleset behavior against current official documentation before changing resource semantics or documented settings.
- Keep provider versions, lockfiles, Docker image pins, and generated-state exclusions aligned.
- Keep required status checks aligned with real workflow job names, using the names in `.github/workflows/` and `config/infra/variables.tf` (currently `test-code`, `test-repo`, and `scan-repo`).
- Keep secrets and tokens out of Terraform files, examples, plans, logs, and documentation.
- Prefer explicit variables and reviewed defaults over hidden fallbacks.
- Pair with `workflow-validation` when changes require `make infra`, workflow alignment, or packaging-manifest checks.

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
