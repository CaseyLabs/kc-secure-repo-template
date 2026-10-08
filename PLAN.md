# CI/CD Build and Release Improvement Plan

Status: implemented and locally verified on
`feat/release-integrity-improvements`. GitHub-side release publication and
settings remain unverified until an authorized release.

## Objective

Close the template's CI and release gaps identified against
`/home/user/downloads/CI_CD_Build_and_Release_Best_Practices.md`
(version 1.0, reference date October 8, 2026).

- Preserve low-privilege PR validation, container-first workflows, pinned
  dependencies, reproducible packaging, and the existing public Makefile interface.
- Improve trust and retention for the template archive and its release evidence.
- Keep application delivery optional and generic; do not introduce an AWS,
  registry, or deployment-controller dependency into the default template.
- Distinguish checked-in controls from GitHub settings that require separate
  verification. The review did not verify live repository settings.

## 1. Make review requirements explicit

Priority: high. Reference guide sections 3, 4, and 7.

Current state:

- `config/infra/variables.tf` defaults to zero required approvals and disables
  code-owner and last-push approval requirements.
- Required checks are configured, and releases verify default-branch ancestry.
  These controls do not establish independent review.

Work:

- Preserve the documented solo-maintainer defaults.
- Provide an opt-in team configuration requiring independent approval, dismissal
  of stale approvals, and appropriate approval of the latest push.
- Document ownership requirements for `.github/workflows/`, `scripts/`,
  `config/infra/`, and release policy. Provide CODEOWNERS guidance that derived
  repositories can populate with their actual maintainers.
- Record the solo-maintainer posture as an explicit exception to the reference
  standard, with owner, rationale, risk, review date, and compensating controls.
- Document verification of active rulesets, required checks, tag protection,
  immutable releases, and relevant GitHub plan limitations.

Acceptance:

- A team can adopt the stronger configuration without redesigning Terraform.
- Documentation clearly separates required checks from independent approval.
- No claim of enforced protection depends only on an unapplied Terraform example.

Likely files: `config/infra/variables.tf`,
`config/infra/terraform.tfvars.example`, `docs/terraform.md`,
`docs/github-ci.md`, and `docs/security-model.md`.

Verification:

- Check example values and required check names against the implementation.
- Verify version-sensitive settings against official GitHub/provider documentation.
- Run `make infra` if Terraform configuration changes; do not apply remote changes.

## 2. Retain complete release artifacts durably

Priority: high. Reference guide sections 4, 5, and 9.

Current state:

- The generated archive and `ARCHIVE-SHA256SUMS` remain only in the Actions
  artifact bundle, whose retention is finite.
- GitHub Releases contain the security summary, checksums, and enabled SBOM.

Work:

- Attach the generated template archive and its checksum to the versioned GitHub
  Release alongside the existing integrity assets.
- Retain the Actions artifact bundle as additional workflow evidence.
- Define release retention and artifact quarantine/revocation procedures.
- Preserve refusal to overwrite existing releases and document enabling immutable
  releases through GitHub settings.
- Ensure the security summary accurately lists published assets and records the
  archive checksum, source commit, build/run identity, and relevant evidence links.

Acceptance:

- A release's built archive remains available after its Actions bundle expires.
- Consumers can verify all downloaded release assets using documented checksums.
- The archive published is the same file scanned, tested, and attested.

Likely files: `.github/workflows/release.yml`, `scripts/dist.sh`, and
`docs/release-and-packaging.md`.

Verification:

- Add targeted tests for changed release-generation logic.
- Run `make dist`, `make scan`, and `TEST_MODE=template make test` as relevant.
- Validate actual asset upload and immutable-release behavior later in an
  explicitly authorized release; local checks alone cannot prove publication.

## 3. Verify artifact provenance before consumption

Priority: medium. Reference guide sections 4, 7, and 8.

Current state:

- The release workflow creates GitHub provenance attestations for `dist/**`.
- Consumer instructions verify checksums but do not authenticate provenance.

Work:

- Document attestation verification for the archive and integrity evidence.
- Require verification against the expected repository and approved release
  workflow identity; do not accept any valid signature as sufficient.
- Check the attested source commit against the intended release commit.
- Explain that checksums provide integrity while attestation verification
  establishes authenticated origin under the selected policy.
- Document GitHub plan/access prerequisites and future promotion-gate behavior.

Acceptance:

- Consumer instructions reject artifacts from an unexpected repository, builder,
  or source commit, even when their local checksums are consistent.
- Future delivery guidance requires verification before deployment authorization.

Likely files: `docs/release-and-packaging.md`, `docs/security-model.md`, and
an optional verification helper under `scripts/` if automation is justified.

Verification:

- Verify CLI syntax and identity-policy options against official documentation.
- If adding a helper, test rejection cases before implementing it and keep normal
  tooling container-based.
- Record whether verification against an existing attested release was possible.

## 4. Smoke-test the exact packaged archive

Priority: medium. Reference guide sections 2 and 8.

Current state:

- Release tests run before the final `make dist`.
- Template tests exercise copied repository files and archive reproducibility,
  rather than building/testing an extraction of the final release archive.

Work:

- After packaging, extract the final archive into a disposable directory.
- Validate its documented build/test workflow through the existing Makefile
  interface, without modifying the source checkout.
- Use a bounded sequence from the extracted directory: `make build` and
  `TEST_MODE=src make test`. Run template/smoke packaging regressions separately;
  those suites invoke `make dist` and must not be called by archive validation.
- Fail publication when extraction, required contents, build, or tests fail.
- Verify the archive is unchanged after validation and before attestation/upload.
- Keep implementation in `scripts/`; keep the workflow wrapper thin.

Acceptance:

- Successful publication depends on validation of the exact archive being released.
- Validation never rebuilds or replaces that archive after its identity is recorded.
- Archive validation cannot recursively invoke `make dist` through its test path.
- Temporary files and generated outputs do not enter the published package.

Likely files: `scripts/dist.sh`, `scripts/test.sh`,
`.github/workflows/release.yml`, and `docs/release-and-packaging.md`.

Verification:

- Add targeted behavioral tests for validation failures and archive preservation.
- Verify that archive validation invokes only the bounded build/test sequence
  and does not re-enter packaging.
- Run `TEST_MODE=template make test`, `make dist`, and `make scan`.
- Retain the existing reproducibility and packaging-exclusion checks.

## 5. Manage security exceptions and release reassessment

Priority: medium. Reference guide sections 4, 8, 9, and 10.

Current state:

- Repository variables can disable SBOM generation or vulnerability scanning and
  change the vulnerability threshold. Skipped controls are reported.
- No scheduled workflow reassesses published releases against new vulnerability
  intelligence.

Work:

- Define an exception record with owner, rationale, affected releases/control,
  risk, expiry, approval, and compensating measures.
- Require a valid exception for weakening release integrity gates; expired or
  missing exceptions must block publication of the affected release.
- Enforce exceptions at the publication boundary through shared script logic.
  Preserve local packaging with disabled scanners for disposable test artifacts,
  including the existing `ENABLE_SBOM=false ENABLE_GRYPE=false make dist`
  reproducibility checks, without requiring policy exceptions for those runs.
- Require the release workflow to validate effective controls and exceptions
  before publication; local packaging options must not bypass that gate.
- Include exception references and effective scan settings in release evidence.
- Define which supported releases receive periodic vulnerability reassessment.
- Reassess retained SBOMs or artifacts without rebuilding released bytes.
- Define how findings trigger triage, quarantine, consumer notification, and a
  replacement release. Keep reporting read-only unless further actions are authorized.

Acceptance:

- Disabling a default release gate cannot silently produce an apparently normal
  release or rely on an expired exception.
- Local reproducibility tests can disable scanners without an exception, while
  publication with those settings requires a valid exception.
- New vulnerability findings remain traceable to affected retained releases.
- Published artifacts are never rebuilt or overwritten during reassessment.

Likely files: `scripts/dist.sh`, `.github/workflows/release.yml`,
a focused reassessment script/workflow, and release/security documentation.

Verification:

- Test missing/expired exception rejection and scan failure propagation.
- Test that local scanner-disabled packaging remains supported and that the same
  settings cannot bypass publication exception enforcement.
- Run the relevant template tests, `make scan`, and `make dist`.
- Exercise reassessment against retained evidence with no publishing credentials.

## 6. Document optional application delivery

Priority: follow-up for derived applications. Reference guide sections 5–9.

Current state:

- This repository does not publish production OCI images or deploy applications.
- The Helm scaffold supports `repository@sha256:...`, but permits tags and local
  defaults. It includes basic readiness/liveness probes.

Work:

- Add focused adaptation guidance for a trusted image build that captures the
  registry-reported digest and records source, run, SBOM, scan, and provenance.
- Require immutable registry tags and keep release publishing privileges separate
  from environment-scoped deployment privileges.
- Deploy the same approved digest to staging and production, with runtime
  configuration and no environment-specific rebuilds.
- Require staging smoke/E2E gates, production authorization, deployment concurrency
  controls, audit records, health monitoring, and explicit failure behavior.
- Document digest-based rollback, retention of previous configuration, migration
  compatibility, and compromised-artifact tracing/quarantine.
- Document digest-only production use of the existing Helm scaffold; preserve
  convenient local defaults. Add an opt-in enforcement mode only if justified.
- Explain cross-registry digest changes and multi-platform index versus manifest
  identity when those features are used.

Acceptance:

- Guidance covers the complete build-once/promote lifecycle without coupling the
  default template to a cloud provider or deployment controller.
- Application-specific credentials, environments, approval policies, telemetry,
  and deployment implementation remain the derived repository's responsibility.

Likely files: `docs/customize-template.md`, `docs/k8s.md`, and a focused delivery
guide linked from `docs/README.md`.

Verification:

- Check examples against existing configuration and chart behavior.
- Run `make k8s` and relevant behavioral tests if chart/rendering code changes.
- Run `make k8s-test-local` only with a real kubeconfig/context and relevant changes.

## Execution and completion

- Complete items 1 and 2 first, then items 3–5. Item 4 depends on the final archive
  produced by item 2; item 5 can reuse the durable evidence retained there.
- Keep item 6 optional; it does not block improvements to template releases.
- Use TDD for code changes; do not add tests that merely assert documentation
  wording, filenames, or directory layout.
- Reuse passing checks when later changes do not invalidate them. Record exact
  commands, results, and any unverified GitHub-side behavior at each milestone.
- Keep packaging manifests and focused documentation aligned with implementation.
- Preserve unrelated working-tree changes, including the existing `README.md` edit.

Checkpoint:

- Current step: complete; ready for review.
- Changed files: release workflow, reassessment workflow, release policy,
  archive validation, dist generation, focused tests, infra example, and focused
  documentation. See `git status --short` for the exact branch diff.
- Verification passed: `sh scripts/test-release.sh`, `make dist`,
  `sh scripts/validate-release-archive.sh`,
  `TEST_MODE=template make test`, `make scan`, `make infra`, checksum checks,
  and shell syntax checks. The Terraform run wrote a plan and did not apply it.
- Final checks after the last script edits: `TEST_MODE=template make test`,
  `make dist`, `make scan`, `sh scripts/validate-release-archive.sh`,
  `sha256sum -c dist/SHA256SUMS`, and `git diff --check` passed.
- Reassessment: read-only scan of retained SBOMs for v1.10.3, v1.10.2, and
  v1.10.1 passed with no findings. The first run exposed an unwritable scanner
  temp directory; the final run used a nonroot writable mount and succeeded.
- Unresolved external evidence: active GitHub rulesets, immutable-release setting,
  artifact retention configuration, and real release attestation verification.
- Plan verification: confirm referenced repository paths and Makefile targets;
  runtime checks are deferred until implementation changes exist.
