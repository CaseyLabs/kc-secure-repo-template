# GitHub Supply Chain Hardening

This template keeps most build, test, scan, and release behavior in versioned
files, but some supply chain controls live in GitHub repository, organization,
or package-registry settings. Review this checklist when creating a derived
repository and after any GitHub security incident that could affect automation
credentials or release artifacts.

## Workflow Triggers

- Keep pull request validation on `pull_request` with minimal permissions.
- Do not use `pull_request_target` for workflows that check out, build, test,
  scan, package, or otherwise execute pull request contents.
- If privileged PR metadata automation is truly needed, keep it separate from
  code execution and prefer `workflow_run` handoff patterns where untrusted
  code runs in an unprivileged workflow first.
- Treat workflow artifacts produced from pull request code as untrusted input in
  any later privileged workflow.

The template's `make scan` path rejects `pull_request_target` in checked-in
workflow files by default.

## Credentials

- Prefer GitHub Apps, OIDC, or fine-grained tokens over broad personal access
  tokens.
- Scope automation credentials to the smallest repository set and permission
  set that can complete the job.
- Avoid organization-level Actions secrets unless many repositories genuinely
  need the same credential. When organization secrets are used, restrict their
  repository access policy.
- Rotate repository, organization, package-registry, and marketplace credentials
  together after a suspected workflow or maintainer-account compromise.
- Remove credentials that no workflow still needs, and review registered
  Actions secrets on a recurring schedule.

## Releases And Artifacts

- Enable immutable GitHub Releases for repositories that publish release assets.
- Publish releases in one pass: create the release, attach all intended assets,
  and then publish. Do not edit or clobber assets after publication.
- Protect release tags from deletion and retagging. The Terraform example under
  `config/infra/` includes a release-tag ruleset for `refs/tags/v*`.
- Keep provenance and integrity evidence with releases. This template publishes
  checksums and GitHub artifact attestations from the tag release workflow.
- For container images or other external registries, enable tag immutability
  where the registry supports it and monitor for unexpected tag or digest
  changes where it does not.

## GitHub-Side Controls

The following controls are manual or organization-level unless you manage them
through your own infrastructure automation:

- Require SSO for organization members.
- Use IP allow lists where your organization model supports them.
- Require review before running sensitive workflows or accessing deployment
  environments that expose secrets.
- Enable secret scanning and push protection for repositories and organizations.
- Enable Dependabot alerts and security updates.
- Monitor GitHub audit logs for changes to secrets, workflows, releases, tags,
  repository visibility, repository names, and automation credentials.

Document which of these controls are enforced for each derived repository so
maintainers know what is protected by git and what depends on GitHub settings.
