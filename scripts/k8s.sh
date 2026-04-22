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

# Use the locked Helm image when available so local output stays aligned with
# the repository's reproducible toolchain. Helm is the templating/packaging tool
# used here to turn chart files into plain Kubernetes YAML.
helm_image=${DEV_K8S_HELM_IMAGE_LOCK:-${DEV_K8S_HELM_IMAGE}}
# The chart is the Kubernetes package we lint, render, and package below.
chart_path=${K8S_CHART_PATH:-config/k8s/chart}
# A Helm "release" is one installed instance of a chart.
release_name=${K8S_RELEASE_NAME:-kc-secure-template}
# Kubernetes namespaces partition resources inside a cluster.
namespace=${K8S_NAMESPACE:-default}
# An optional values file lets callers override chart defaults without editing
# the chart itself, which is the standard Helm customization pattern.
values_file=${K8S_VALUES_FILE:-}
name_override=${K8S_NAME_OVERRIDE:-${PROJECT_NAME:-}}
chart_name=${PROJECT_NAME:-app}
image_repository=${K8S_IMAGE_REPOSITORY:-}
image_tag=${K8S_IMAGE_TAG:-}
package_dir=${K8S_PACKAGE_DIR:-.tmp/k8s/package}
render_dir=${K8S_RENDER_DIR:-.tmp/k8s/rendered}
render_file="${render_dir}/${release_name}.yaml"

case "${chart_path}" in
/* | ./* | ../*) ;;
*) chart_path="./${chart_path}" ;;
esac
[ -d "${chart_path}" ] || {
	printf 'missing chart directory: %s\n' "${chart_path}" >&2
	exit 1
}

if [ -z "${image_repository}" ] || [ -z "${image_tag}" ]; then
	project_image=${PROJECT_IMAGE:-}
	project_image_repository=''
	project_image_tag=''

	# Fall back to PROJECT_IMAGE so one source of image metadata can feed both
	# Docker-based local workflows and the rendered Kubernetes manifests.
	if [ -n "${project_image}" ]; then
		case "${project_image}" in
		*@*)
			project_image_repository=${project_image%%@*}
			project_image_tag=${project_image#*@}
			;;
		*)
			project_image_basename=${project_image##*/}
			case "${project_image_basename}" in
			*:*)
				project_image_repository=${project_image%:*}
				project_image_tag=${project_image##*:}
				;;
			*)
				project_image_repository=${project_image}
				;;
			esac
			;;
		esac
	fi

	[ -n "${image_repository}" ] || image_repository=${project_image_repository:-${chart_name}}
	[ -n "${image_tag}" ] || image_tag=${project_image_tag:-latest}
fi

values_args=''
if [ -n "${values_file}" ]; then
	case "${values_file}" in
	/* | ./* | ../*) ;;
	*) values_file="./${values_file}" ;;
	esac
	[ -f "${values_file}" ] || {
		printf 'missing values file: %s\n' "${values_file}" >&2
		exit 1
	}
	values_args="--values ${values_file}"
fi

name_override_args=''
if [ -n "${name_override}" ]; then
	name_override_args="--set-string nameOverride=${name_override}"
fi

# Helm runs in Docker rather than on the host so the workflow stays
# container-first and reproducible for new contributors.
docker_uid=${DOCKER_UID:-$(id -u)}
docker_gid=${DOCKER_GID:-$(id -g)}
docker_home=${DOCKER_HOME:-/tmp/kc-template-home}
docker_cache_home=${DOCKER_CACHE_HOME:-${docker_home}/.cache}
docker_home_source=${DOCKER_HOME_SOURCE:-$(pwd)/.cache/docker-home}
docker_tmpdir=${DOCKER_TMPDIR:-$(pwd)/.cache/docker-tmp}
mkdir -p "${docker_home_source}" "${docker_tmpdir}" "${package_dir}" "${render_dir}"

chart_stage_parent=.tmp/k8s
mkdir -p "${chart_stage_parent}"
chart_stage_dir=$(mktemp -d "${chart_stage_parent}/staged.XXXXXX")
cleanup() {
	rm -rf "${chart_stage_dir}"
}
trap cleanup EXIT INT TERM HUP

staged_chart_path="${chart_stage_dir}/chart"
cp -R "${chart_path}" "${staged_chart_path}"

chart_yaml_tmp="${chart_stage_dir}/Chart.yaml.tmp"
# Rewrite the staged chart name so the packaged chart follows the project
# configuration without forcing template authors to hard-code one project name.
awk -v chart_name="${chart_name}" '
	/^name:/ { print "name: " chart_name; next }
	{ print }
' "${staged_chart_path}/Chart.yaml" >"${chart_yaml_tmp}"
mv "${chart_yaml_tmp}" "${staged_chart_path}/Chart.yaml"

values_yaml_tmp="${chart_stage_dir}/values.yaml.tmp"
# Rewrite the staged values file so the rendered manifests use the caller's
# chosen image repository and tag, which is what a cluster would eventually
# pull for the Deployment's container.
awk -v image_repository="${image_repository}" -v image_tag="${image_tag}" '
	/^image:/ { in_image = 1; print; next }
	in_image && /^[^[:space:]]/ { in_image = 0 }
	in_image && /^[[:space:]]+repository:/ { print "  repository: " image_repository; next }
	in_image && /^[[:space:]]+tag:/ { print "  tag: " image_tag; next }
	{ print }
' "${staged_chart_path}/values.yaml" >"${values_yaml_tmp}"
mv "${values_yaml_tmp}" "${staged_chart_path}/values.yaml"

printf '\n==> Validate Kubernetes Helm chart\n'
# `helm lint` is a static check: it validates chart structure and catches many
# template/value issues before anything is sent to a cluster.
# shellcheck disable=SC2086
docker run --rm --user "${docker_uid}:${docker_gid}" \
	--cap-drop=ALL \
	--security-opt=no-new-privileges:true \
	--entrypoint sh \
	-e HOME="${docker_home}" \
	-e XDG_CACHE_HOME="${docker_cache_home}" \
	-v "${docker_home_source}:${docker_home}" \
	-v "${docker_tmpdir}:/tmp" \
	-v "$(pwd):/workspace" \
	-w /workspace \
	"${helm_image}" \
	-eu -c "helm lint '${staged_chart_path}' ${values_args} ${name_override_args}"

printf '\n==> Render Kubernetes manifests\n'
# `helm template` expands the chart into plain YAML. This is the safest way to
# inspect what Kubernetes objects would be created without installing them.
# shellcheck disable=SC2086
docker run --rm --user "${docker_uid}:${docker_gid}" \
	--cap-drop=ALL \
	--security-opt=no-new-privileges:true \
	--entrypoint sh \
	-e HOME="${docker_home}" \
	-e XDG_CACHE_HOME="${docker_cache_home}" \
	-v "${docker_home_source}:${docker_home}" \
	-v "${docker_tmpdir}:/tmp" \
	-v "$(pwd):/workspace" \
	-w /workspace \
	"${helm_image}" \
	-eu -c "helm template '${release_name}' '${staged_chart_path}' --namespace '${namespace}' ${values_args} ${name_override_args} --set-string image.repository='${image_repository}' --set-string image.tag='${image_tag}' > '${render_file}'"

printf '\n==> Package Kubernetes Helm chart\n'
# `helm package` produces a distributable `.tgz` chart archive, which is the
# form you would publish to a chart repository or attach to a release.
# shellcheck disable=SC2086
docker run --rm --user "${docker_uid}:${docker_gid}" \
	--cap-drop=ALL \
	--security-opt=no-new-privileges:true \
	--entrypoint sh \
	-e HOME="${docker_home}" \
	-e XDG_CACHE_HOME="${docker_cache_home}" \
	-v "${docker_home_source}:${docker_home}" \
	-v "${docker_tmpdir}:/tmp" \
	-v "$(pwd):/workspace" \
	-w /workspace \
	"${helm_image}" \
	-eu -c "helm package '${staged_chart_path}' --destination '${package_dir}'"

printf '\n==> Kubernetes summary\n'
printf '%s\n' "Project config: ${PROJECT_CFG_FILE}"
printf '%s\n' "Chart: ${chart_path}"
printf '%s\n' "Release: ${release_name}"
printf '%s\n' "Namespace: ${namespace}"
printf '%s\n' "Rendered manifest: ${render_file}"
printf '%s\n' "Chart package directory: ${package_dir}"
