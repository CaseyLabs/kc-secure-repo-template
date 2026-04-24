# AGENTS.md

Instructions for coding agents working under `config/k8s/`.

## Scope

This subtree owns the optional Kubernetes Helm scaffold. Keep it optional and
generic for derived repositories.

Use the root `Makefile` as the public interface:

- `make k8s` validates, renders, and packages the chart
- `make k8s-test-local` runs server-side dry-run validation against a real
  cluster when the caller provides kubeconfig inputs

Keep execution glue in `scripts/` only when it needs to participate in those
root targets.

## Local Rules

- Keep Kubernetes-owned static assets in `config/k8s/`.
- Keep cluster-specific choices in Helm values or `config/project.cfg`, not
  hard-coded into templates.
- Preserve derived-repository defaults: blank `K8S_*` values should inherit from
  `PROJECT_NAME` or `PROJECT_IMAGE` at render time where the current scripts do
  that today.
- Keep `make k8s` local-only. It must not contact a Kubernetes cluster or run
  `helm install`.
- Keep `make k8s-test-local` non-persistent by using server-side dry-run.
- Treat kubeconfig files as sensitive. Validation helpers should stage only the
  selected kubeconfig file into a temporary directory and should not mount a
  broad host kubeconfig directory into repo-built images.
- Use pinned external tooling images from `config/project.cfg` or the lockfile
  when running Helm or kubectl flows.
- Do not add application-specific labels, names, hosts, namespaces, images, or
  ingress assumptions to the generic chart unless they remain configurable.

## Documentation

Update `config/k8s/README.md` when chart behavior, adaptation points,
validation commands, values, or security expectations change.

Avoid expanding the root `README.md` unless the root workflow or public command
surface changes.

## Verification

For documentation-only changes, verify commands, paths, and variable names
against the current files.

For chart, values, rendering, packaging, or Kubernetes script behavior changes,
run the smallest relevant set:

```sh
make k8s
make k8s-test-local
```

Run `make k8s-test-local` only when a real kubeconfig/context is available and
the change affects local cluster validation. If it cannot be run, state why.
