# Optional Kubernetes Support

This template ships an optional Helm chart under `config/k8s/chart`.

Use it when a derived repository wants a simple Kubernetes deployment scaffold
without changing the template's default Docker-first local workflow.

## What It Includes

- `Deployment`
- `Service`
- `Ingress`, disabled by default

The chart keeps security-sensitive settings explicit and exposes deployment
choices through Helm values instead of hard-coding cluster-specific behavior.

## Root Workflow

Run the bundled validation and packaging flow with:

```sh
PROJECT_CFG_FILE=config/project.cfg make k8s
```

That command:

- lints the chart
- renders manifests locally using the image and project metadata from `config/project.cfg`
- packages the chart with matching default `Chart.yaml` and `values.yaml` settings

It does not contact a Kubernetes cluster or perform `helm install`.

## Main Adaptation Points

- `config/project.cfg`
  - `K8S_CHART_PATH`
  - `K8S_RELEASE_NAME`
  - `K8S_NAME_OVERRIDE`
  - `K8S_NAMESPACE`
  - `K8S_RENDER_DIR`
  - `K8S_VALUES_FILE`
  - `K8S_IMAGE_REPOSITORY`
  - `K8S_IMAGE_TAG` set this to an explicit image version or digest-backed release tag
- `config/k8s/chart/values.yaml`
- `config/k8s/chart/templates/*.yaml`

By default, `K8S_NAME_OVERRIDE` follows `PROJECT_NAME`, so the chart's
`app.kubernetes.io/name` label derives from the repository config without
hard-coding project-specific names into `values.yaml`.

Keep Kubernetes-specific static assets in `config/k8s/`. Put execution glue in
`scripts/` only when it needs to participate in the root `make` interface.
