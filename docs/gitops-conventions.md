# GitOps Naming Conventions

Use these conventions for branches, issues, pull requests, labels, and release
references in repositories derived from this template. The goal is to keep
changes easy to audit, safe to automate, and predictable for both humans and
GitHub tooling.

## General Rules

- Use lowercase kebab-case for machine-facing names:
  - branches
  - labels
  - environment names
  - release channels
- Keep names ASCII-only.
- Avoid spaces, shell metacharacters, emojis, and personal names.
- Prefer stable scope names that match repository paths or workflows:
  - `docs`
  - `github`
  - `release`
  - `deps`
  - `infra`
  - `k8s`
  - `src`
- Keep titles human-readable and imperative.
- Put traceability in the description instead of overloading the title.

## Branches

Branch names should follow this pattern:

```text
<type>/<optional-issue>-<short-kebab-summary>
```

Recommended branch types:

- `feat/`: user-visible feature or capability.
- `fix/`: bug fix or broken workflow repair.
- `docs/`: documentation-only change.
- `ci/`: GitHub Actions, checks, or automation behavior.
- `deps/`: dependency, tool, image, or lockfile update.
- `security/`: security hardening or vulnerability remediation.
- `release/`: release preparation.
- `infra/`: Terraform or repository infrastructure change.
- `k8s/`: Kubernetes or Helm scaffold change.
- `refactor/`: behavior-preserving cleanup.
- `test/`: test-only or validation-only change.
- `chore/`: maintenance that does not fit a narrower type.

Examples:

```text
docs/gitops-naming-conventions
fix/42-release-tag-ancestry-check
ci/pin-workflow-action-shas
deps/update-renovate-cooldowns
infra/restrict-default-branch-ruleset
k8s/render-derived-release-name
security/harden-release-artifact-validation
```

Rules:

- Prefer one logical change per branch.
- Include the issue number when it exists and helps traceability.
- Do not reuse long-lived feature branches as deployment environments.
- Keep the default branch as the reconciled source of truth unless a specific
  GitOps controller requires a different protected branch model.

## Pull Requests

PR titles should follow this pattern:

```text
[<type>] <scope>: <imperative summary>
```

Use the same type vocabulary as branch names. Keep scopes short and tied to
paths, workflows, or repo areas.

Examples:

```text
[docs] github: add GitOps naming conventions
[fix] release: require tags to point at default-branch history
[ci] scan: pin workflow action dependencies
[deps] renovate: delay routine dependency update PRs
[infra] rulesets: require repository scan checks
[k8s] chart: derive release names from project config
[security] dist: include checksums for release evidence
```

PR descriptions should use this structure:

```markdown
## Why

- ...

## Changes

- ...

## Validation

- ...
```

Add these sections only when relevant:

- `## Risk`
  - for security, release, workflow, infrastructure, or migration changes
- `## Rollback`
  - when reverting needs more than a normal GitHub revert
- `## Follow-up`
  - for intentionally deferred work

Rules:

- Keep descriptions grounded in the actual diff.
- List only validation that was actually run.
- Link related issues with `Closes #123`, `Fixes #123`, or `Refs #123`.
- Call out security or release-integrity effects explicitly.
- Keep draft PR descriptions accurate as the branch changes.

## Issues

Issue titles should follow this pattern:

```text
<type>(<scope>): <problem or outcome>
```

Examples:

```text
bug(release): tag validation fails on protected release branches
task(docs): document derived repository setup steps
security(workflows): audit write permissions in release automation
deps(docker): refresh pinned scanner image digests
```

Use issue descriptions to capture:

- problem statement
- affected path, workflow, or environment
- expected behavior
- acceptance criteria
- validation notes
- links to logs, runs, PRs, or prior decisions

Prefer issue types such as:

- `bug`
- `task`
- `feature`
- `security`
- `maintenance`
- `docs`

## Labels

Use namespaced labels so filters stay consistent:

- `type:bug`
- `type:feature`
- `type:docs`
- `type:security`
- `type:maintenance`
- `area:github`
- `area:release`
- `area:deps`
- `area:infra`
- `area:k8s`
- `area:src`
- `priority:high`
- `priority:medium`
- `priority:low`
- `status:blocked`
- `status:needs-review`
- `risk:security`
- `risk:release`
- `risk:workflow`

Rules:

- Prefer labels for filtering, not branch names or title prefixes.
- Keep label names lowercase.
- Do not encode assignee names or temporary dates in labels.

## Commits

Commit subjects should follow the same title format as pull requests:

```text
[<type>] <scope>: <imperative summary>
```

Examples:

```text
[docs] github: add GitOps naming conventions
[fix] scan: reject privileged pull request workflow triggers
[deps] docker: update scanner image digests
```

Rules:

- Keep the subject under about 72 characters when practical.
- Use the body for rationale, tradeoffs, and reviewer context.
- Mention issue or PR numbers when they help future archaeology.

## Releases And Tags

Use semantic version tags for published releases:

```text
v<major>.<minor>.<patch>
```

Examples:

```text
v1.4.0
v1.4.1
v2.0.0
```

Rules:

- Protect `refs/tags/v*`.
- Publish releases from default-branch history.
- Use release branch names only for short-lived release preparation, such as
  `release/v1.4.0`.
- Keep release notes focused on user-visible changes, security notes, upgrade
  impact, and validation evidence.

## GitOps-Specific Notes

- Keep desired state in the repository, not in PR titles or branch names.
- Prefer path-based ownership and review rules over naming-only policy.
- Treat branch, PR, and issue text as untrusted input in workflows.
- Do not trigger privileged automation from PR titles, issue comments, or branch
  names without a reviewed allowlist.
- Keep deployment or reconciliation names stable and boring:
  - `dev`
  - `staging`
  - `prod`
  - `preview`
