# Documentation

Use this folder as the starting point for understanding the template beyond the
root quick start.

## Table Of Contents

1. [Template Adoption Guide](template-adoption.md)
   - How to turn this template into a real derived repository.
2. [Workflow Guide](workflows.md)
   - What each `make` target does and why local and CI commands stay aligned.
3. [Security Model](security-model.md)
   - Security posture, rationale, and the split between git-enforced controls
     and GitHub-side settings.
4. [Release And Packaging Guide](release-and-packaging.md)
   - Template archive contents, release outputs, SBOMs, checksums, and
     attestations.
5. [Dependency Update Guide](dependency-updates.md)
   - Dependabot, Renovate, cooldowns, and lock refreshes.
6. [GitHub Configuration](github-ci.md)
   - GitHub Actions, workflow policy, credentials, and repository-control
     guidance.
7. [AI Agent Support](ai-agent-support.md)
   - Optional agent guidance included with the template.
8. [Optional Kubernetes Support](../config/k8s/README.md)
   - Helm scaffold usage and adaptation points.
9. [Infra Workspace](../config/infra/README.md)
   - Terraform-backed GitHub repository hardening workspace.
10. [Go Example](../src/README.md)
    - The bundled `src/` example used by `make example`.
