# GitHub Configuration

This project's `.github` folder contains the GitHub Actions CI configs and workflows:

```
.
└── .github/
    ├── dependabot.yml
    ├── renovate
    │   └── setup-github-app.sh
    ├── renovate.json
    └── workflows
    ├── build.yml
    ├── renovate.yml
    ├── scan.yml
    └── test.yml
```

## Folder Contents

- `workflows/`
  - pull request checks
  - security scans
  - release publishing
  - scheduled/manual maintenance
- `dependabot.yml`
  - GitHub Actions updates
  - Dockerfile dependency updates
- `renovate.json`
  - self-hosted Renovate settings
  - updates for tool and image values in `config/project.cfg`
- `renovate/setup-github-app.sh`
  - helper for creating the Renovate GitHub App
  - uses narrow app credentials instead of a broad personal token

Workflow rules:

- Call `make` targets instead of duplicating project logic inline.
- Pin external GitHub Actions by full commit SHA.
- Keep the reviewed release tag comment beside each pinned action.
- Follow [`docs/gitops-conventions.md`](gitops-conventions.md) for branch, PR,
  issue, label, commit, and release naming.

## Supply Chain Hardening

A supply chain attack compromises something a project depends on instead of
attacking the final application directly. In a GitHub repository, common paths
include:

- malicious pull request workflow execution
- compromised GitHub Actions or container images
- leaked automation credentials
- mutable release assets or tags
- dependency update automation with excessive permissions
- maintainer or organization settings that allow unsafe workflow runs

This template reduces those risks by making sensitive automation explicit,
container-first, pinned, scanned, and reviewable.

## How This Template Helps

- Pull request code stays untrusted:
  - PR checks use `pull_request`.
  - `make scan` rejects privileged triggers such as `pull_request_target`,
    `issue_comment`, and unreviewed `workflow_run` handoffs.
  - workflows use explicit minimal permissions.
- Workflow definitions get security-audited:
  - `actionlint` checks syntax and expression mistakes.
  - `zizmor` checks GitHub Actions security footguns.
  - repo policy checks enforce template-specific hard fails.
- Workflow dependencies stay pinned:
  - external Actions use full commit SHAs.
  - `make scan` enforces those pins.
  - Dependabot delays routine action updates before opening PRs.
- Release artifacts stay traceable:
  - release tags must point at default-branch history.
  - existing releases are not clobbered.
  - release outputs include checksums, SBOMs, scans, and attestations.
- Credentials stay scoped:
  - Renovate uses a GitHub App token.
  - workflows avoid broad default permissions.
  - secret scanning runs in the standard scan path.
- Local and CI behavior stay aligned:
  - workflows call `make` targets.
  - scripts hold implementation details.
  - Docker-based tools keep validation reproducible.

## Workflow Triggers

- Use `pull_request` for PR validation:
  - build
  - test
  - scan
  - package checks
- Do not use `pull_request_target` for PR code execution:
  - no checkout of PR head code
  - no build/test of PR contents
  - no package or release from PR contents
  - no cache restore from untrusted PR jobs
- Do not use `issue_comment` for automation that can write, publish, dispatch,
  or run shell from user-controlled text.
- Keep privileged PR metadata automation separate:
  - prefer `workflow_run` handoff patterns when needed
  - treat artifacts from PR code as untrusted
  - add a reviewed policy exception before committing `workflow_run`

## Workflow Permissions

- Every checked-in workflow must declare a top-level `permissions:` block.
- Grant only the scopes needed by that workflow.
- Keep PR validation and scan workflows read-only.
- Restrict write, attestation, and OIDC permissions to release or maintenance
  workflows that require them.

## Untrusted Input

- Treat all event data as untrusted shell input:
  - PR titles
  - branch names
  - issue and PR comments
  - any `github.event.*` field
- Do not interpolate those values directly into `run:` steps.
- Prefer explicit allowlists, fixed strings, or separate metadata-only steps
  when a workflow needs to inspect event content.

## Credentials

- Prefer narrow credentials:
  - GitHub Apps
  - OIDC
  - fine-grained tokens
- Avoid broad credentials:
  - personal access tokens
  - organization-wide secrets
  - credentials shared across unrelated repos
- Rotate after suspected compromise:
  - repository secrets
  - organization secrets
  - package-registry tokens
  - marketplace credentials
- Review regularly:
  - remove unused secrets
  - restrict organization secret access policies
  - confirm app permissions still match workflow needs

## Releases And Artifacts

- Prefer immutable releases:
  - enable immutable GitHub Releases where available
  - publish assets once
  - do not edit or clobber published assets
- Protect release tags:
  - use tag rulesets for `refs/tags/v*`
  - reject tags outside default-branch history
- Keep release evidence:
  - checksums
  - SBOMs
  - vulnerability scan reports
  - GitHub artifact attestations
- Protect external registries:
  - enable tag immutability when supported
  - monitor unexpected tag or digest changes

## GitHub-Side Controls

Some controls live outside git unless you manage them through infrastructure
automation.

- Organization controls:
  - require SSO
  - use IP allow lists where appropriate
  - monitor audit logs
- Repository controls:
  - enable secret scanning
  - enable push protection
  - enable Dependabot alerts
  - enable Dependabot security updates
- Workflow controls:
  - require approval for sensitive workflow runs
  - restrict environments that expose secrets
  - keep default workflow permissions minimal
- Release controls:
  - enable immutable releases
  - protect release tags
  - watch release, tag, and asset changes

Document which controls are enforced for each derived repository so maintainers
know what is protected by git and what depends on GitHub settings.
