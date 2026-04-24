# code_review.md

Review changes for this repository as a secure-by-default, generic GitHub repository template.

## Review objective

Prioritize findings that could cause:

- incorrect behavior
- regressions
- weakened security defaults
- reduced reproducibility
- drift between local, CI, and release workflows
- unnecessary expansion of the public interface
- product-specific assumptions in a generic template

Prefer high-signal findings over broad commentary.

## Local `/review` scope

Treat `/review` runs as reviewer-only passes: inspect the selected diff, report prioritized and actionable findings, and do not edit the working tree during the review.

Choose the review target deliberately:

- use a base-branch review for PR-style feedback before opening or updating a pull request
- use an uncommitted-changes review for staged, unstaged, and untracked local work
- use a commit review when a specific SHA is the review unit
- use custom review instructions for a narrow focus such as release integrity, accessibility, or template portability

## Severity guidance

Use these priorities when deciding what to flag:

### High

Flag as high priority when a change:

- introduces a likely bug or regression
- weakens a security control or safe default
- makes builds, tests, or releases less reproducible
- causes local and CI behavior to diverge
- breaks the documented `Makefile` workflow
- adds a likely secret-handling, credential, permission, or supply-chain risk
- bypasses or weakens release integrity controls
- introduces a breaking public interface change without clear justification

### Medium

Flag as medium priority when a change:

- increases maintenance cost or complexity without clear benefit
- duplicates logic between `Makefile`, scripts, and CI
- creates documentation or configuration drift
- adds dependencies, targets, or workflow steps that are not clearly necessary
- weakens auditability, clarity, or failure visibility
- makes the template more product-specific or less reusable

### Low

Flag as low priority when a change:

- has minor clarity, consistency, or style issues
- could be simplified without changing behavior
- is correct but slightly misaligned with repository conventions

Do not inflate severity for minor style preferences.

## Repository-specific review rules

### 1. Public interface stability

Review whether the change preserves a small and stable root `Makefile` interface.

Flag when a change:

- adds root `Makefile` targets without clear recurring need
- exposes internal implementation details that should remain behind `scripts/` or configuration
- changes the expected behavior of existing public targets without updating documentation and verification

### 2. Container-first workflow

This repository is container-first.

Flag when a change:

- requires host-installed language toolchains for normal use
- moves build, test, lint, or release logic out of Docker-based workflows without strong justification
- causes local developer workflows and CI workflows to stop using the same underlying commands

### 3. Security defaults

Prefer secure-by-default behavior.

Flag when a change:

- weakens secret scanning, artifact scanning, or other default checks
- expands GitHub Actions permissions without clear need
- introduces unpinned or weakly controlled external dependencies where pinning is practical
- downloads tools or artifacts without checksum or signature verification when verification is feasible
- adds secrets, tokens, credentials, or sensitive data to code, logs, fixtures, examples, docs, or tests
- makes privileged containers or elevated execution the default without clear need

### 4. Reproducibility and auditability

Prefer deterministic and easy-to-audit workflows.

Flag when a change:

- removes version pinning, lockfiles, or integrity controls without reason
- makes Dockerfiles or scripts less deterministic
- introduces hidden fallbacks that make failures harder to understand
- adds broad error handling that masks real failures
- makes releases harder to trace, verify, or reproduce

### 5. Generic template boundaries

This repository is a generic secure repository template, not a product scaffold.

Flag when a change:

- introduces app- or company-specific assumptions into generic paths, docs, defaults, examples, or workflows
- expands the template into a monorepo framework or kitchen-sink environment
- couples the template to a specific language or stack without clear optional boundaries

### 6. CI and release integrity

Workflows should remain thin wrappers around repository logic.

Flag when a change:

- duplicates build, test, lint, release, or security logic inline in `.github/workflows/` instead of calling `make` targets or scripts
- changes release behavior without corresponding verification and documentation
- weakens protections around signing, attestations, SBOMs, provenance, or artifact validation when those controls exist

### 7. Documentation accuracy

Documentation must match the real workflow.

Flag when a change:

- updates code, scripts, CI, Docker, or configuration without updating affected documentation
- leaves commands, paths, target names, or examples out of sync with the repository
- claims verification or support that the repository does not actually provide

## What to verify during review

When relevant, check whether the change remains aligned across:

- `Makefile`
- `scripts/`
- `Dockerfile`
- `project.env`
- `.github/workflows/`
- packaging and release manifests
- README and setup or usage docs
- tests and verification steps

## Preferred review style

- Be concise, specific, and evidence-based.
- Focus on actionable findings.
- Explain the concrete risk or regression.
- Point to the exact file, behavior, or workflow involved.
- Prefer findings over style commentary.
- Prefer fewer high-confidence comments over many speculative ones.

## Avoid low-value comments

Do not comment only to suggest:

- personal naming preferences
- minor formatting changes with no functional impact
- optional refactors unless they materially improve safety, correctness, or maintainability
- adding abstractions or dependencies without a clear repository need

Do not ask for broad rewrites when a targeted fix is sufficient.

## Suggested review comment structure

Use this structure when possible:

- Finding: what is wrong
- Why it matters: concrete risk, regression, or inconsistency
- Scope: where it appears
- Suggested direction: the smallest reasonable fix

## Approval standard

A change is generally acceptable when:

- it satisfies the request
- it preserves or improves security defaults
- it preserves or improves reproducibility
- it keeps local, CI, and release behavior aligned
- it does not unnecessarily expand the public interface
- it does not introduce product-specific assumptions into the template
- documentation and verification remain credible
