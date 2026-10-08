# Release And Packaging Guide

`make dist` builds the template release archive and integrity outputs under
`dist/`. The release workflow calls the same target after repeating tests and
security scans on the tagged commit.

## What Ships

`scripts/template.sh files` is the release file manifest. Directories in that
manifest are expanded into files while local state and generated outputs are
excluded, including Terraform state, local `.tfvars` files, nested build caches,
and the generated example binary. Environment files named `.env` or `.env.*`
are excluded at every depth, except `.env.example`, which must contain only
public placeholders. These exclusions also apply when packaging an extracted
template without Git metadata; other untracked files can still be included.

The generated archive is `dist/kc-secure-repo-template.tar.gz`. It is built with
normalized ordering, ownership, and timestamps so repeated builds can produce the
same bytes when inputs match.

## Integrity Outputs

`make dist` writes release evidence next to the archive:

- `dist/SECURITY-ANALYSIS.md`: human-readable summary of generated release
  evidence.
- `dist/SHA256SUMS`: checksums for every other published asset, including the archive.
- `dist/ARCHIVE-SHA256SUMS`: direct checksum for the template archive.
- `dist/template.spdx.json`: SBOM output when `ENABLE_SBOM=true`.
- `dist/grype-report.txt`: vulnerability scan output when `ENABLE_GRYPE=true`.
- `dist/template-manifest.txt`: generated manifest of template files.

The security summary records the archive digest, source commit, Actions run,
effective scan settings, and any publication exception.

## Retention and Incident Handling

Treat every published GitHub Release and its provenance attestations as the
canonical release record. Retain versioned release assets and attestations
indefinitely while the repository exists; there is no routine expiry or
cleanup. The Actions artifact bundle and reassessment report are supplementary
evidence and follow the repository's configured Actions artifact retention
period. Do not rely on those bundles as the only copy of release assets.
Repository owners should preserve an offline copy of release assets, checksums,
attestations, and reassessment reports before repository transfer or closure.

When a reassessment or incident identifies a compromised or unsafe release:

- record the affected version, archive digest, finding, and investigation
  evidence in the incident record
- stop downstream promotion and ask consumers to quarantine the affected
  digest; notify known consumers with the affected version and replacement or
  mitigation guidance
- publish a replacement under a new version after it passes the normal release
  gates; never replace or rebuild the bytes of the affected version
- preserve the original release and evidence for investigation by default.
  If access must be revoked or a release removed, obtain separate incident
  authorization, preserve an offline evidence copy first, and document the
  resulting loss of public availability

Review the repository's artifact-retention setting periodically. Changing
that setting affects supplementary Actions evidence, not the indefinite
retention policy for published GitHub Releases.

`ENABLE_GRYPE=true` requires `ENABLE_SBOM=true` because the vulnerability scan
runs against the generated SBOM. `GRYPE_FAIL_ON` controls the severity threshold
for the Grype scan and defaults to `critical`.

## GitHub Release Behavior

The release workflow is the only supported publisher for versioned GitHub
Releases. To publish a release, create the reviewed `v*` tag and push the tag to
GitHub. Do not create the GitHub Release manually first; an existing release for
the same tag blocks the workflow from attaching generated integrity assets.

Maintainers who need a web UI flow should use **Actions** -> **release.yml** ->
**Run workflow** from the default branch, then enter the `v*` release tag. That
path creates the tag after local release gates pass, then publishes the GitHub
Release with generated integrity assets. Do not use **Releases** -> **Draft a
new release** for this repository, because that creates the GitHub Release before
the workflow can attach the generated evidence.

Before publishing, the workflow:

- verifies the release target commit is reachable from the repository default
  branch
- runs `make test` and `TEST_MODE=template make test`
- runs `make scan`
- runs `make dist`
- extracts the final archive in a disposable directory and runs `make build`
  and `TEST_MODE=src make test` from there; publication stops if the archive
  changes, lacks required files, or fails those checks
- creates the `v*` tag for manual Actions UI releases when the tag does not
  already exist
- uploads the complete `dist/` directory as an Actions artifact
- creates GitHub artifact provenance attestations for generated release files
- creates a GitHub Release only when one does not already exist for the tag

The GitHub Release attaches the built archive, both checksum files, security
summary, template manifest, and the enabled SBOM and Grype report. Download all
assets into `dist/`, then verify them:

```sh
mkdir -p dist
gh release download vX.Y.Z --repo OWNER/REPO --dir dist
sha256sum -c dist/SHA256SUMS
sha256sum -c dist/ARCHIVE-SHA256SUMS
gh attestation verify dist/kc-secure-repo-template.tar.gz \
  --repo OWNER/REPO \
  --signer-workflow OWNER/REPO/.github/workflows/release.yml \
  --source-digest EXPECTED_COMMIT_SHA
gh attestation verify dist/SHA256SUMS \
  --repo OWNER/REPO \
  --signer-workflow OWNER/REPO/.github/workflows/release.yml \
  --source-digest EXPECTED_COMMIT_SHA
```

Use an independently approved repository, workflow, and release commit SHA.
The checksum detects changed bytes; attestation verification authenticates the
source under that policy. A valid signature from another workflow is
insufficient. Apply the attestation check to other evidence used for promotion.
For manual releases the workflow source ref may be the default branch, so check
the source digest against the intended release commit. The
[GitHub CLI reference](https://cli.github.com/manual/gh_attestation_verify)
documents these options. Artifact attestations require a public repository on
Free, Pro, or Team, or Enterprise Cloud for private/internal repositories.
Future deployment gates must perform provenance checks before authorization.

Existing releases are not modified. This is intentional: release assets should be
treated as published evidence, not mutable build output.

Enable [immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases)
in GitHub settings and verify that published releases show **Immutable**. The
workflow stages all assets on a draft before publishing. Local checks cannot
prove that the repository setting is active or that upload succeeds.

## Exceptions and reassessment

Local disposable packaging may disable both scanners for `make dist`.
Publication with either gate disabled requires a reviewed
`config/release-exception.cfg` based on `config/release-exception.cfg.example`.
It records the exact release tag, affected controls, owner, rationale, risk,
approval, compensating measures, and a future expiry. Missing or expired
exceptions block publication. Remove a release-specific exception after use.

`reassess-releases.yml` checks the three newest published stable releases weekly.
It downloads their retained SBOMs and uses the pinned Grype image with current
vulnerability data. It does not rebuild or change published bytes. A release-list
error, missing SBOM, scanner error, or critical finding fails the read-only workflow.
Reports for scanned tags are retained in an Actions artifact under the
repository's configured artifact-retention period. Triage findings using the
incident procedure above. The reassessment workflow is read-only; it does not
change release assets or automatically quarantine, notify, or publish.

## Reproducibility Checks

For release-related changes, validate both packaging scope and reproducibility:

```sh
sh scripts/template.sh manifest
ENABLE_SBOM=false ENABLE_GRYPE=false make dist
```

`TEST_MODE=template make test` checks packaging exclusions and repeated archive
reproducibility in a disposable copy, with SBOM and vulnerability scans disabled.
It exercises the production packaging code without overwriting local state.

## When To Update This Area

Update this guide when changing:

- `scripts/template.sh`
- `scripts/dist.sh`
- release workflow behavior
- release artifact names
- SBOM or vulnerability scan settings
- files that should or should not ship in the template archive
