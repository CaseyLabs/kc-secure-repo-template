# Optional Kubernetes Support

This template ships an optional Helm chart under `config/k8s/chart`.

Use it when a derived repository wants a simple Kubernetes deployment scaffold
without changing the template's default Docker-first local workflow.

If you are new to Kubernetes:

- a `Deployment` tells Kubernetes how many copies of your app to run
- a `Service` gives those app copies a stable in-cluster network address
- an `Ingress` is an optional HTTP entry point from outside the cluster
- a Helm chart is a reusable package of Kubernetes YAML templates and defaults

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
PROJECT_CFG_FILE=config/project.cfg make k8s-test-local
```

That command:

- lints the chart
- renders manifests locally using the image and project metadata from `config/project.cfg`
- packages the chart with matching default `Chart.yaml` and `values.yaml` settings
- `make k8s-test-local` also builds `config/k8s/Dockerfile.k8s` and runs `kubectl apply --dry-run=server` against a real kubeconfig/context

`make k8s` does not contact a Kubernetes cluster or perform `helm install`.
`make k8s-test-local` does contact the cluster API for validation, but uses
server-side dry-run so it does not persist resources.

## Main Adaptation Points

- `config/project.cfg`
  - `K8S_CHART_PATH`
  - `K8S_RELEASE_NAME`
  - `K8S_NAME_OVERRIDE`
  - `K8S_NAMESPACE`
  - `K8S_PACKAGE_DIR`
  - `K8S_RENDER_DIR`
  - `K8S_VALUES_FILE`
  - `K8S_IMAGE_REPOSITORY`
  - `K8S_IMAGE_TAG` set this to an explicit image version or digest-backed release tag
  - `DEV_K8S_KUBECTL_VERSION`
  - `DEV_K8S_KUBECTL_SHA256_LINUX_AMD64`
- `config/k8s/chart/values.yaml`
- `config/k8s/chart/templates/*.yaml`
- local-only runtime inputs
  - `K8S_TEST_LOCAL_KUBECONFIG`
  - `K8S_TEST_LOCAL_CONTEXT`
  - `K8S_TEST_LOCAL_IMAGE`

By default, `K8S_NAME_OVERRIDE` follows `PROJECT_NAME`, so the chart's
`app.kubernetes.io/name` label derives from the repository config without
hard-coding project-specific names into `values.yaml`.

`K8S_VALUES_FILE`, `K8S_RENDER_DIR`, and `K8S_PACKAGE_DIR` may be either
repository-relative paths or absolute host paths.

Keep Kubernetes-specific static assets in `config/k8s/`. Put execution glue in
`scripts/` only when it needs to participate in the root `make` interface.
