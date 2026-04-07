#!/bin/sh
# shellcheck shell=sh disable=SC1090
set -eu

# Resolve and validate the chosen project configuration file.
PROJECT_ENV=${1:-${PROJECT_ENV:-project.env}}
project_env=${PROJECT_ENV}
case "${project_env}" in
/* | ./* | ../*) ;;
*) project_env="./${project_env}" ;;
esac
# Infra validation needs a real config because it depends on pinned image values.
[ -f "${project_env}" ] || {
	printf 'missing %s; copy project.env.example to %s first\n' "${project_env}" "${PROJECT_ENV}" >&2
	exit 1
}

# Load image locks and Terraform selectors.
. "${project_env}"

apply=${APPLY:-false}
infra_image='kc-secure-template-infra:local'
infra_dockerfile='.tmp/infra/Dockerfile'
iac_bin='terraform'
terraform_image_arg="${DEV_TERRAFORM_IMAGE_LOCK:-${DEV_TERRAFORM_IMAGE}}"

# Use host-matching ids and local cache directories for containerized infra commands.
docker_uid=${DOCKER_UID:-$(id -u)}
docker_gid=${DOCKER_GID:-$(id -g)}
docker_home=${DOCKER_HOME:-/tmp/kc-template-home}
docker_cache_home=${DOCKER_CACHE_HOME:-${docker_home}/.cache}
docker_home_source=${DOCKER_HOME_SOURCE:-$(pwd)/.cache/docker-home}
docker_tmpdir=${DOCKER_TMPDIR:-$(pwd)/.cache/docker-tmp}
infra_plan_dir=${INFRA_PLAN_DIR:-.tmp/infra}
infra_plan_path="${infra_plan_dir}/github-repository.tfplan"
mkdir -p "${docker_home_source}" "${docker_tmpdir}" "${infra_plan_dir}"

# Materialize a temporary Dockerfile with the currently pinned tool images substituted in.
sed \
	-e "s#^FROM .* AS terraform-cli\$#FROM ${terraform_image_arg} AS terraform-cli#" \
	-e "s#^FROM .* AS dev-base\$#FROM ${DEV_BASE_IMAGE_LOCK:-${DEV_BASE_IMAGE}} AS dev-base#" \
	config/infra/Dockerfile >"${infra_dockerfile}"

printf '\n==> Prepare infra image\n'
# Build the container that contains the IaC CLI and repository workspace.
docker build \
	--build-arg DEBIAN_APT_SNAPSHOT="${DEV_PACKAGE_SNAPSHOT_LOCK}" \
	--target dev \
	-f "${infra_dockerfile}" \
	-t "${infra_image}" .

# Small wrapper to keep repeated docker-run flags in one place.
run_infra() {
	docker run --rm --user "${docker_uid}:${docker_gid}" \
		--cap-drop=ALL \
		--security-opt=no-new-privileges:true \
		-e HOME="${docker_home}" \
		-e XDG_CACHE_HOME="${docker_cache_home}" \
		-v "${docker_home_source}:${docker_home}" \
		-v "${docker_tmpdir}:/tmp" \
		-v "$(pwd):/workspace" \
		-w /workspace \
		"${infra_image}" \
		sh -eu -c "$1"
}

printf '\n==> Run infra lint\n'
# Format checks catch drift before validation or planning.
run_infra "cd config/infra && ${iac_bin} fmt -check -recursive"

printf '\n==> Run infra tests\n'
# Reinitialize in a clean state, then validate the configuration syntax and schema.
run_infra "cd config/infra && rm -rf .terraform .terraform.lock.hcl && ${iac_bin} init -backend=false && ${iac_bin} validate"

printf '\n==> Run infra plan\n'
# Create a plan file using the example variables so maintainers can review the changes.
run_infra "cd config/infra && rm -rf .terraform .terraform.lock.hcl && ${iac_bin} init -backend=false && ${iac_bin} plan -input=false -lock=false -refresh=false -var-file=terraform.tfvars.example -out=../../${infra_plan_path}"

# Only apply when the caller explicitly opts in.
if [ "${apply}" = 'true' ]; then
	printf '\n==> Apply infra plan\n'
	run_infra "cd config/infra && ${iac_bin} apply -input=false ../../${infra_plan_path}"
else
	printf '\n==> Apply skipped\n'
	printf 'Plan written to %s. Export GITHUB_TOKEN, update config/infra/terraform.tfvars.example, and run: APPLY=true make infra\n' "${infra_plan_path}"
fi
