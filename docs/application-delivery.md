# Optional Application Delivery

A derived application can add image publishing and deployment without changing
the template's default release workflow or requiring a particular cloud,
registry, or controller. Keep the implementation behind reviewed scripts and
`make` targets. Assign registry credentials, protected environments, approval
policy, telemetry, and deployment tooling in the derived repository.

## Build once and promote

1. Build and test the image from a reviewed source commit with pinned inputs.
   Push it under an immutable registry tag, then capture the digest reported by
   the registry. Record source commit, workflow run, SBOM, scan result, and
   provenance against that digest. Registry tag immutability must be enabled
   where supported; a tag alone is not a deployment identity.
2. Verify the digest, expected repository, builder workflow, and source commit
   before deployment authorization. Keep image publishing credentials separate
   from environment-scoped deployment credentials.
3. Deploy the same approved digest to staging and production. Supply ports,
   secrets, hosts, and runtime configuration per environment without rebuilding
   the image. Staging smoke and end-to-end tests must pass before production
   approval. Serialize deployments to each environment and retain who approved,
   what digest and configuration were deployed, and the resulting health checks.
4. Monitor readiness, errors, latency, and rollout health. On failure, stop
   promotion and roll back to the previous approved digest and saved runtime
   configuration. Check migration compatibility before rollback; an irreversible
   database migration may require a forward fix.

For this Helm scaffold, set `K8S_IMAGE_REPOSITORY` to the registry path and
`K8S_IMAGE_TAG` to `sha256:<digest>`; `make k8s` renders the corresponding
`repository@sha256:...` reference. Production policy should reject tag-only
images. Local defaults remain convenient for development. If a registry copy
changes the digest, verify the destination digest and provenance again. For
multi-platform images, distinguish the index digest from each platform manifest
digest and approve the identity actually deployed by the cluster.

When an artifact is compromised, trace its digest to affected environments,
quarantine further promotion, preserve evidence, notify consumers, and publish
a newly built replacement under a new version. Never overwrite a released
image or rebuild it for vulnerability reassessment.
