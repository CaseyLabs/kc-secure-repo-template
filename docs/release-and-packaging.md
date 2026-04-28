# Release And Packaging Guide

`make dist` builds the template release archive and integrity outputs under
`dist/`. The release workflow calls the same target after repeating tests and
security scans on the tagged commit.

## What Ships

`scripts/template.sh files` is the release file manifest. Directories in that
manifest are expanded into files while local state and generated outputs are
excluded, including Terraform state, local `.tfvars` files, nested build caches,
and the generated example binary.

The generated archive is `dist/kc-secure-repo-template.tar.gz`. It is built with
normalized ordering, ownership, and timestamps so repeated builds can produce the
same bytes when inputs match.

## Integrity Outputs

`make dist` writes release evidence next to the archive:

- `dist/SECURITY-ANALYSIS.md`: human-readable summary of generated release
  evidence.
- `dist/SHA256SUMS`: checksums for published integrity assets.
- `dist/template.spdx.json`: SBOM output when `ENABLE_SBOM=true`.
- `dist/grype-report.txt`: vulnerability scan output when `ENABLE_GRYPE=true`.
- `dist/template-manifest.txt`: generated manifest of template files.

`ENABLE_GRYPE=true` requires `ENABLE_SBOM=true` because the vulnerability scan
runs against the generated SBOM. `GRYPE_FAIL_ON` controls the severity threshold
for the Grype scan and defaults to `critical`.

## GitHub Release Behavior

The release workflow is the only supported publisher for versioned GitHub
Releases. To publish a release, create the reviewed `v*` tag and push the tag to
GitHub. Do not create the GitHub Release manually first; an existing release for
the same tag blocks the workflow from attaching generated integrity assets.

Before publishing, the workflow:

- verifies the tag commit is reachable from the repository default branch
- runs `make test`
- runs `make scan`
- runs `make dist`
- uploads the complete `dist/` directory as an Actions artifact
- creates GitHub artifact provenance attestations for generated release files
- creates a GitHub Release only when one does not already exist for the tag

Existing releases are not modified. This is intentional: release assets should be
treated as published evidence, not mutable build output.

## Reproducibility Checks

For release-related changes, validate both packaging scope and reproducibility:

```sh
sh scripts/template.sh manifest
ENABLE_SBOM=false ENABLE_GRYPE=false make dist
```

`TEST_MODE=template make test` also checks that the template manifest stays in
sync and that repeated release archives match when SBOM and vulnerability scans
are disabled.

## When To Update This Area

Update this guide when changing:

- `scripts/template.sh`
- `scripts/dist.sh`
- release workflow behavior
- release artifact names
- SBOM or vulnerability scan settings
- files that should or should not ship in the template archive
