#!/bin/sh
# shellcheck shell=sh disable=SC1090
set -eu

PROJECT_CFG_FILE=${1:-${PROJECT_CFG_FILE:-config/project.cfg}}
project_cfg_file=${PROJECT_CFG_FILE}
case "${project_cfg_file}" in
/* | ./* | ../*) ;;
*) project_cfg_file="./${project_cfg_file}" ;;
esac
[ -f "${project_cfg_file}" ] || {
	printf 'missing %s; set PROJECT_CFG_FILE to an existing config file\n' "${project_cfg_file}" >&2
	exit 1
}

. "${project_cfg_file}"

render_dir=${K8S_RENDER_DIR:-.tmp/k8s/rendered}
release_name=${K8S_RELEASE_NAME:-kc-secure-template}
render_file="${render_dir}/${release_name}.yaml"
k8s_test_image=${K8S_TEST_LOCAL_IMAGE:-kc-secure-template-k8s-tools:local}
kubeconfig_host_path=${K8S_TEST_LOCAL_KUBECONFIG:-${HOME}/.kube/config}
kube_context=${K8S_TEST_LOCAL_CONTEXT:-}

case "${render_file}" in
/*) render_file_in_workspace=${render_file} ;;
./*) render_file_in_workspace="/workspace/${render_file#./}" ;;
*) render_file_in_workspace="/workspace/${render_file}" ;;
esac

case "${kubeconfig_host_path}" in
/*) ;;
*) kubeconfig_host_path="${PWD}/${kubeconfig_host_path}" ;;
esac
[ -f "${kubeconfig_host_path}" ] || {
	printf 'missing kubeconfig: %s\n' "${kubeconfig_host_path}" >&2
	printf '%s\n' 'Set K8S_TEST_LOCAL_KUBECONFIG to a readable kubeconfig file before running make k8s-test-local' >&2
	exit 1
}

kubeconfig_host_dir=$(dirname "${kubeconfig_host_path}")
kubeconfig_basename=$(basename "${kubeconfig_host_path}")
kubeconfig_container_dir=/tmp/k8s-test-kubeconfig
kubeconfig_container_path="${kubeconfig_container_dir}/${kubeconfig_basename}"

[ -n "${DEV_K8S_KUBECTL_VERSION:-}" ] || {
	printf '%s\n' 'Kubernetes local dry-run requires DEV_K8S_KUBECTL_VERSION' >&2
	exit 1
}
[ -n "${DEV_K8S_KUBECTL_SHA256_LINUX_AMD64:-}" ] || {
	printf '%s\n' 'Kubernetes local dry-run requires DEV_K8S_KUBECTL_SHA256_LINUX_AMD64' >&2
	exit 1
}

docker_uid=${DOCKER_UID:-$(id -u)}
docker_gid=${DOCKER_GID:-$(id -g)}
docker_home=${DOCKER_HOME:-/tmp/kc-template-home}
docker_cache_home=${DOCKER_CACHE_HOME:-${docker_home}/.cache}
docker_home_source=${DOCKER_HOME_SOURCE:-$(pwd)/.cache/docker-home}
docker_tmpdir=${DOCKER_TMPDIR:-$(pwd)/.cache/docker-tmp}
mkdir -p "${docker_home_source}" "${docker_tmpdir}"

kubectl_context_args=''
if [ -n "${kube_context}" ]; then
	kubectl_context_args="--context ${kube_context}"
fi

printf '\n==> Render Kubernetes manifests for local dry-run\n'
sh ./scripts/k8s.sh "${PROJECT_CFG_FILE}" >/tmp/k8s-test-local-render.txt

[ -f "${render_file}" ] || {
	printf 'missing rendered manifest: %s\n' "${render_file}" >&2
	exit 1
}

printf '\n==> Build local Kubernetes validation image\n'
docker build \
	--build-arg DEV_BASE_IMAGE="${DEV_BASE_IMAGE_LOCK:-${DEV_BASE_IMAGE}}" \
	--build-arg DEV_PACKAGE_SNAPSHOT="${DEV_PACKAGE_SNAPSHOT_LOCK}" \
	--build-arg DEV_K8S_KUBECTL_VERSION="${DEV_K8S_KUBECTL_VERSION}" \
	--build-arg DEV_K8S_KUBECTL_SHA256_LINUX_AMD64="${DEV_K8S_KUBECTL_SHA256_LINUX_AMD64}" \
	-f config/k8s/Dockerfile.k8s \
	-t "${k8s_test_image}" .

printf '\n==> Run kubectl server-side dry-run against the current cluster context\n'
# `--dry-run=server` asks the API server to validate and default the resources
# without persisting them. This requires a real kubeconfig/context and keeps the
# local command aligned with how Kubernetes would handle the manifests.
# shellcheck disable=SC2086
docker run --rm --user "${docker_uid}:${docker_gid}" \
	--cap-drop=ALL \
	--security-opt=no-new-privileges:true \
	-e HOME="${docker_home}" \
	-e XDG_CACHE_HOME="${docker_cache_home}" \
	-e KUBECONFIG="${kubeconfig_container_path}" \
	-v "${docker_home_source}:${docker_home}" \
	-v "${docker_tmpdir}:/tmp" \
	-v "${kubeconfig_host_dir}:${kubeconfig_container_dir}:ro" \
	-v "$(pwd):/workspace" \
	-w /workspace \
	"${k8s_test_image}" \
	apply \
	--dry-run=server \
	--validate=strict \
	${kubectl_context_args} \
	-o name \
	-f "${render_file_in_workspace}" | tee /tmp/k8s-test-local-dry-run.txt

resource_count=$(grep -c . /tmp/k8s-test-local-dry-run.txt || true)

printf '\n==> Kubernetes local dry-run summary\n'
printf '%s\n' "Rendered manifest: ${render_file}"
printf '%s\n' "kubectl version: ${DEV_K8S_KUBECTL_VERSION}"
printf '%s\n' "Local validation image: ${k8s_test_image}"
printf '%s\n' "Kubeconfig: ${kubeconfig_host_path}"
if [ -n "${kube_context}" ]; then
	printf '%s\n' "Kubernetes context: ${kube_context}"
fi
printf '%s\n' "Resources checked by server-side dry-run: ${resource_count}"
