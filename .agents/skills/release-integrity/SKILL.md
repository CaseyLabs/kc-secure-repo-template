---
name: release-integrity
description: Use when reviewing or improving this template's release-integrity story, including artifact verification, SBOMs, attestations, vulnerability scanning, signing guidance, and release-workflow safety. Do not use for general CI validation, GitHub-settings-only work, or unrelated template customization.
---

# Release integrity

Use this skill when working on release and artifact integrity for this template.

## Use this skill when
- changing release workflows
- adding or revising SBOM generation
- adding or revising vulnerability scanning
- adding or revising attestation, provenance, or signing guidance
- changing artifact creation, packaging, or publication behavior

## Do not use this skill when
- the task is ordinary template validation
- the task is ordinary GitHub-settings documentation
- the task is a general adaptation of the template to a new project
- the task is a small bug fix unrelated to release or artifact trust

## Goals
- Keep release workflows understandable, reviewable, and difficult to bypass.
- Improve trust in generated artifacts and release evidence.
- Preserve reproducibility and supply-chain safety where practical.

## Method
- Treat release workflows as sensitive paths.
- Review `scripts/dist.sh`, `.github/workflows/build.yml`, and release-related `config/project.cfg` settings as the core release-integrity surface.
- Prefer explicit tool versions and pinned actions where practical.
- Verify downloaded tools with checksums or signatures when feasible.
- Keep SBOM, Grype, checksum, provenance, attestation, and compliance-summary outputs aligned when release behavior changes.
- Keep generated artifacts and caches out of the Docker build context where appropriate.
- Document any weakening of defaults explicitly.
- Keep guidance clear about what evidence a derived repository should produce and why.
- Pair this skill with `template-validation` when release changes require `make dist`, workflow checks, or packaging-manifest validation.

## Review priorities
- supply-chain risk
- workflow bypass risk
- artifact integrity gaps
- missing verification steps
- unclear release evidence
- unnecessary complexity

## Output expectations
- State what changed in the release path.
- Call out integrity controls added, removed, or weakened.
- Note any follow-up work for externally published artifacts or stronger signing.
