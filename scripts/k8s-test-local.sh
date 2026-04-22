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

render_file=''
render_file_in_workspace=''
k8s_test_image=${K8S_TEST_LOCAL_IMAGE:-${DEV_K8S_KUBECTL_IMAGE_LOCK:-${DEV_K8S_KUBECTL_IMAGE:-}}}
kubeconfig_host_path=${K8S_TEST_LOCAL_KUBECONFIG:-${HOME}/.kube/config}
kube_context=${K8S_TEST_LOCAL_CONTEXT:-}

case "${kubeconfig_host_path}" in
/*) ;;
*) kubeconfig_host_path="${PWD}/${kubeconfig_host_path}" ;;
esac
[ -f "${kubeconfig_host_path}" ] || {
	printf 'missing kubeconfig: %s\n' "${kubeconfig_host_path}" >&2
	printf '%s\n' 'Set K8S_TEST_LOCAL_KUBECONFIG to a readable kubeconfig file before running make k8s-test-local' >&2
	exit 1
}

kubeconfig_basename=$(basename "${kubeconfig_host_path}")
kubeconfig_container_dir=/tmp/k8s-test-kubeconfig
kubeconfig_container_path="${kubeconfig_container_dir}/${kubeconfig_basename}"

[ -n "${k8s_test_image}" ] || {
	printf '%s\n' 'Kubernetes local dry-run requires DEV_K8S_KUBECTL_IMAGE or DEV_K8S_KUBECTL_IMAGE_LOCK' >&2
	exit 1
}

docker_uid=${DOCKER_UID:-$(id -u)}
docker_gid=${DOCKER_GID:-$(id -g)}
docker_home=${DOCKER_HOME:-/tmp/kc-template-home}
docker_cache_home=${DOCKER_CACHE_HOME:-${docker_home}/.cache}
docker_home_source=${DOCKER_HOME_SOURCE:-$(pwd)/.cache/docker-home}
docker_tmpdir=${DOCKER_TMPDIR:-$(pwd)/.cache/docker-tmp}
mkdir -p "${docker_home_source}" "${docker_tmpdir}"

kubeconfig_stage_dir=$(mktemp -d "${docker_tmpdir}/kubeconfig.XXXXXX")
k8s_stage_dir=''
k8s_metadata_file=''
cleanup() {
	rm -rf "${kubeconfig_stage_dir}"
	if [ -n "${k8s_stage_dir}" ]; then
		rm -rf "${k8s_stage_dir}"
	fi
	if [ -n "${k8s_metadata_file}" ]; then
		rm -f "${k8s_metadata_file}"
	fi
}
trap cleanup EXIT INT TERM HUP
cp "${kubeconfig_host_path}" "${kubeconfig_stage_dir}/${kubeconfig_basename}"
chmod 600 "${kubeconfig_stage_dir}/${kubeconfig_basename}"

kubectl_context_args=''
if [ -n "${kube_context}" ]; then
	kubectl_context_args="--context ${kube_context}"
fi

printf '\n==> Render Kubernetes manifests for local dry-run\n'
k8s_metadata_file=$(mktemp "${docker_tmpdir}/k8s-test-local-meta.XXXXXX")
K8S_METADATA_FILE="${k8s_metadata_file}" sh ./scripts/k8s.sh "${PROJECT_CFG_FILE}" >/tmp/k8s-test-local-render.txt

# shellcheck disable=SC1090
. "${k8s_metadata_file}"
[ -n "${K8S_RENDER_FILE:-}" ] || {
	printf '%s\n' 'k8s render did not report a manifest path' >&2
	exit 1
}
[ -f "${K8S_RENDER_FILE}" ] || {
	printf 'missing rendered manifest: %s\n' "${K8S_RENDER_FILE}" >&2
	exit 1
}
render_file=${K8S_RENDER_FILE}
k8s_stage_dir=$(mktemp -d "${docker_tmpdir}/k8s-test-local-manifest.XXXXXX")
k8s_stage_file="${k8s_stage_dir}/$(basename "${render_file}")"
cp "${render_file}" "${k8s_stage_file}"
render_file_in_workspace="/tmp/$(basename "${k8s_stage_dir}")/$(basename "${render_file}")"

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
	-v "${kubeconfig_stage_dir}:${kubeconfig_container_dir}:ro" \
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
printf '%s\n' "kubectl image: ${k8s_test_image}"
printf '%s\n' "Kubeconfig: ${kubeconfig_host_path}"
if [ -n "${kube_context}" ]; then
	printf '%s\n' "Kubernetes context: ${kube_context}"
fi
printf '%s\n' "Resources checked by server-side dry-run: ${resource_count}"
