---
name: template-validation
description: Validate that this repository template still works as intended through Docker-first Makefile workflows, regression checks, smoke tests, and documentation alignment. Do not use for template redesign or GitHub-policy-only changes.
---

# Template validation

Use this skill when validating changes to this repository template.

## Use this skill when
- changing `Makefile`, `Dockerfile`, `scripts/`, tests, packaging manifests, or workflows
- changing the default developer interface
- modifying CI or release behavior
- reviewing whether a template change is complete
- checking whether implementation and documentation still match

## Do not use this skill when
- the task is primarily about adapting the template to a new project shape
- the task is only about GitHub-side settings guidance
- the task is only about release-integrity design without running validation
- the task is a small documentation-only edit with no workflow impact

## Goals
- Confirm that the template still works end to end.
- Catch regressions in build, test, example, CI, release, packaging, and reproducibility behavior.
- Ensure documentation matches actual repository behavior.

## Method
- Prefer Docker-driven validation through the repository's public `Makefile` targets.
- Run the smallest relevant set of checks first, then expand if risk is higher.
- Verify that the documented public interface still matches the real workflow.
- Check that local and GitHub Actions paths still align where expected.
- Check that packaging manifests and shipped files remain aligned.
- When a real bug lacks regression coverage, add or update a targeted test.

## Minimum expectations
Validate the relevant subset of:
- `make build`
- `make test`
- `make example`
- documented CI helper scripts
- documented release helper scripts
- smoke or regression tests
- documentation affected by the change

## Output expectations
- List the checks run.
- List failures, risks, or skipped checks.
- State whether the change meets the repository's definition of done.
- Call out mismatches between docs and implementation.
