#!/bin/sh
# shellcheck shell=sh disable=SC1090
set -eu

# Default to testing the bundled `src/` example, but allow broader validation modes.
mode=src
case "${1:-}" in
src | template | smoke)
	mode=$1
	shift
	;;
esac

PROJECT_CFG_FILE=${1:-${PROJECT_CFG_FILE:-config/project.cfg}}

# Enumerate the files that belong in the shipped template archive.
list_template_files() {
	export LC_ALL=C
	cat <<'EOF' |
AGENTS.md
Dockerfile
LICENSE.md
Makefile
README.md
code_review.md
.dockerignore
.gitignore
.agents
.github
docs
config
scripts
src
EOF
		while IFS= read -r path; do
			[ -n "${path}" ] || continue
			# Expand tracked directories into files while skipping local state and generated outputs.
			if [ -d "${path}" ]; then
				find "${path}" \
					-type d \( -name dist -o -name .terraform -o -name node_modules -o -name coverage -o -name .cache -o -name .tmp \) -prune -o \
					-type f \
					! -name '.terraform.lock.hcl' \
					! -name '*.tfstate' \
					! -name '*.tfstate.*' \
					! -name '*.tfplan' \
					! -name 'crash.log' \
					-print
			elif [ -e "${path}" ]; then
				printf '%s\n' "${path}"
			fi
		done |
		LC_ALL=C sort
}

# Print a consistent failure prefix and stop immediately.
fail() {
	printf 'FAIL: %s\n' "$1" >&2
	exit 1
}

# Extract every external GitHub Action reference together with its workflow and comment.
list_workflow_entries() {
	for workflow in .github/workflows/*.yml; do
		awk -v workflow="${workflow}" '
			/^[[:space:]]*-[[:space:]]+uses:[[:space:]]+/ || /^[[:space:]]+uses:[[:space:]]+/ {
				ref = $0
				sub(/^[[:space:]]*-[[:space:]]+uses:[[:space:]]+/, "", ref)
				sub(/^[[:space:]]*uses:[[:space:]]+/, "", ref)
				comment = ""
				if (match(ref, /[[:space:]]+#.*$/)) {
					comment = substr(ref, RSTART + 1)
					sub(/^[[:space:]]+/, "", comment)
					sub(/^#[[:space:]]*/, "", comment)
					sub(/[[:space:]]+$/, "", comment)
					sub(/[[:space:]]+#.*$/, "", ref)
				}
				sub(/[[:space:]]+$/, "", ref)
				if (ref ~ /^(\.\/|\.\.\/)/) {
					next
				}
				printf "%s\t%s\t%s\n", workflow, ref, comment
			}
		' "${workflow}"
	done
}

# Require full-SHA action pins plus a nearby reviewed tag comment.
check_workflow_action_pins() {
	list_workflow_entries | while IFS="$(printf '\t')" read -r workflow ref comment; do
		case "${ref}" in
		*/*@[0-9a-f][0-9a-f][0-9a-f][0-9a-f]*)
			sha=${ref##*@}
			printf '%s\n' "${sha}" | grep -Eq '^[0-9a-f]{40}$' || {
				printf '%s must pin actions by full SHA: %s\n' "${workflow}" "${ref}" >&2
				exit 1
			}
			;;
		*)
			printf '%s uses an invalid action ref: %s\n' "${workflow}" "${ref}" >&2
			exit 1
			;;
		esac

		case "${comment}" in
		v*) ;;
		*)
			printf '%s must keep a reviewed release tag comment for %s\n' "${workflow}" "${ref}" >&2
			exit 1
			;;
		esac
	done
}

# Nested `dist/` directories are usually an accidental packaging bug.
assert_no_nested_dist_dirs() {
	if find . -mindepth 2 -type d -name dist | grep -q .; then
		find . -mindepth 2 -type d -name dist -print >&2
		fail 'dist directories must only exist at the repository root'
	fi
}

test_optional_k8s_update_compat() {
	workdir=$(mktemp -d)
	root_dir=$(pwd)

	mkdir -p "${workdir}/bin"
	cat >"${workdir}/bin/curl" <<'EOF'
#!/bin/sh
printf 'curl should not be called in optional k8s update compatibility test\n' >&2
exit 1
EOF
	chmod +x "${workdir}/bin/curl"

	(
		cd "${workdir}"
		tar -C "${root_dir}" -cf - . | tar -xf -
		sed \
			-e "/^DEV_K8S_HELM_IMAGE=/d" \
			-e "/^DEV_K8S_KUBECTL_IMAGE=/d" \
			-e "/^K8S_CHART_PATH=/d" \
			-e "/^K8S_RELEASE_NAME=/d" \
			-e "/^K8S_NAMESPACE=/d" \
			-e "/^K8S_VALUES_FILE=/d" \
			-e "/^K8S_IMAGE_REPOSITORY=/d" \
			-e "/^K8S_IMAGE_TAG=/d" \
			-e "s#^DEV_BASE_IMAGE=.*#DEV_BASE_IMAGE='${DEV_BASE_IMAGE_LOCK}'#" \
			-e "s#^DEV_GO_IMAGE=.*#DEV_GO_IMAGE='${DEV_GO_IMAGE_LOCK}'#" \
			-e "s#^DEV_TERRAFORM_IMAGE=.*#DEV_TERRAFORM_IMAGE='${DEV_TERRAFORM_IMAGE_LOCK}'#" \
			-e "s#^DEV_SCAN_GITLEAKS_IMAGE=.*#DEV_SCAN_GITLEAKS_IMAGE='${DEV_SCAN_GITLEAKS_IMAGE_LOCK}'#" \
			-e "s#^DEV_SCAN_ACTIONLINT_IMAGE=.*#DEV_SCAN_ACTIONLINT_IMAGE='${DEV_SCAN_ACTIONLINT_IMAGE_LOCK}'#" \
			-e "s#^DEV_SCAN_TRIVY_IMAGE=.*#DEV_SCAN_TRIVY_IMAGE='${DEV_SCAN_TRIVY_IMAGE_LOCK}'#" \
			-e "s#^DEV_SCAN_SYFT_IMAGE=.*#DEV_SCAN_SYFT_IMAGE='${DEV_SCAN_SYFT_IMAGE_LOCK}'#" \
			-e "s#^DEV_SCAN_GRYPE_IMAGE=.*#DEV_SCAN_GRYPE_IMAGE='${DEV_SCAN_GRYPE_IMAGE_LOCK}'#" \
			-e "s#^DEV_RENOVATE_IMAGE=.*#DEV_RENOVATE_IMAGE='${DEV_RENOVATE_IMAGE_LOCK}'#" \
			config/project.cfg >config/project.cfg.test
		PATH="${workdir}/bin:${PATH}" sh ./scripts/update.sh config/project.cfg.test >/tmp/template-update-optional-k8s.txt
		grep -q "^DEV_K8S_HELM_IMAGE_LOCK=''\$" config/lockfile.cfg || fail 'update should keep an empty K8S Helm lock when the optional setting is absent'
		grep -q "^DEV_K8S_KUBECTL_IMAGE_LOCK=''\$" config/lockfile.cfg || fail 'update should keep an empty K8S kubectl lock when the optional setting is absent'
	)
	rm -rf "${workdir}"
}

test_optional_k8s_scan_skip() {
	workdir=$(mktemp -d)
	root_dir=$(pwd)

	(
		cd "${workdir}"
		tar -C "${root_dir}" -cf - . | tar -xf -
		rm -rf config/k8s
		mkdir -p fake-bin
		cat >fake-bin/docker <<'EOF'
#!/bin/sh
exit 0
EOF
		chmod +x fake-bin/docker
		sed \
			-e "/^DEV_K8S_HELM_IMAGE=/d" \
			-e "/^DEV_K8S_KUBECTL_IMAGE=/d" \
			-e "/^K8S_CHART_PATH=/d" \
			-e "/^K8S_RELEASE_NAME=/d" \
			-e "/^K8S_NAMESPACE=/d" \
			-e "/^K8S_VALUES_FILE=/d" \
			-e "/^K8S_IMAGE_REPOSITORY=/d" \
			-e "/^K8S_IMAGE_TAG=/d" \
			config/project.cfg >config/project.cfg.test
		PATH="${workdir}/fake-bin:${PATH}" sh ./scripts/scan.sh config/project.cfg.test >/tmp/template-scan-optional-k8s.txt
		grep -q 'Optional Kubernetes scaffold not configured; skipping Helm render and manifest scan' /tmp/template-scan-optional-k8s.txt || fail 'scan should report when it skips the optional Kubernetes scaffold'
		grep -q 'No rendered Kubernetes manifests available; skipping Trivy config scan' /tmp/template-scan-optional-k8s.txt || fail 'scan should skip the Kubernetes Trivy pass when nothing was rendered'
	)
	rm -rf "${workdir}"
}

test_k8s_shell_inputs_are_not_executed() {
	workdir=$(mktemp -d)
	root_dir=$(pwd)

	(
		cd "${workdir}"
		tar -C "${root_dir}" -cf - . | tar -xf -
		mkdir -p fake-bin
		cat >fake-bin/docker <<'EOF'
#!/bin/sh
set -eu

printf '%s\n' "$*" >>docker.log
for arg in "$@"; do
	[ "$arg" != "-c" ] || exit 97
done

if [ "${1:-}" = "run" ]; then
	shift
fi

image=''
while [ "$#" -gt 0 ]; do
	case "$1" in
	--rm | --cap-drop=* | --security-opt=*)
		shift
		continue
		;;
	-e | -v | -w | --user)
		shift
		[ "$#" -gt 0 ] && shift
		continue
		;;
	*)
		image=$1
		shift
		break
		;;
	esac
done

[ -n "${image}" ] || exit 1
case "${image}" in
*helm*)
	if [ "${1:-}" = "package" ]; then
		shift
		shift
		destination=''
		while [ "$#" -gt 0 ]; do
			if [ "$1" = "--destination" ]; then
				shift
				destination=${1:-}
				break
			fi
			shift
		done
		[ -n "${destination}" ] || exit 1
		mkdir -p "${destination}"
		: >"${destination}/fake-chart-0.1.0.tgz"
		exit 0
	fi
	image="$(pwd)/fake-bin/fake-helm"
	;;
esac
PATH="$(pwd)/fake-bin:${PATH}" "${image}" "$@"
EOF
		cat >fake-bin/fake-helm <<'EOF'
#!/bin/sh
set -eu

subcommand=${1:-}
shift
case "${subcommand}" in
lint)
	exit 0
	;;
template)
	release=${1:-}
	chart=${2:-}
	shift 2
	printf 'release: %s\n' "${release}"
	printf 'chart: %s\n' "${chart}"
	printf 'args:'
	for arg in "$@"; do
		printf ' [%s]' "${arg}"
	done
	printf '\n'
	;;
	package)
		exit 0
		;;
*)
	exit 1
	;;
esac
EOF
		chmod +x fake-bin/docker fake-bin/fake-helm
		cat >/tmp/template-k8s-shell-values.yaml <<'EOF'
container:
  port: 8080
EOF
		cat >config/project.cfg.test <<'EOF'
. ./config/project.cfg
DEV_K8S_HELM_IMAGE='fake-helm'
K8S_NAME_OVERRIDE='safe; touch /tmp/template-k8s-shell-proof #'
K8S_VALUES_FILE='/tmp/template-k8s-shell-values.yaml'
EOF
		rm -f /tmp/template-k8s-shell-proof
		PATH="${workdir}/fake-bin:${PATH}" sh ./scripts/k8s.sh config/project.cfg.test >/tmp/template-k8s-shell-safe.txt
		[ ! -f /tmp/template-k8s-shell-proof ] || fail 'k8s should not execute shell metacharacters from project config values'
		grep -F -- 'nameOverride=safe; touch /tmp/template-k8s-shell-proof #' .tmp/k8s/rendered/kc-secure-template.yaml || fail 'k8s should pass unsafe-looking overrides as literal Helm arguments'
	)
	rm -rf "${workdir}"
}

test_k8s_render_file_scan_path() {
	workdir=$(mktemp -d)
	root_dir=$(pwd)

	(
		cd "${workdir}"
		tar -C "${root_dir}" -cf - . | tar -xf -
		mkdir -p fake-bin
		cat >fake-bin/docker <<'EOF'
#!/bin/sh
set -eu

printf '%s\n' "$*" >>docker.log

case "${1:-}" in
run)
	shift
	;;
*)
	exit 0
	;;
esac

image=''
while [ "$#" -gt 0 ]; do
	case "$1" in
	--rm | --cap-drop=* | --security-opt=*)
		shift
		continue
		;;
	-e | -v | -w | --user)
		shift
		[ "$#" -gt 0 ] && shift
		continue
		;;
	*)
		image=$1
		shift
		break
		;;
	esac
done

[ -n "${image}" ] || exit 0
case "${image}" in
*helm*)
	image="$(pwd)/fake-bin/helm"
	;;
*)
	exit 0
	;;
esac
PATH="$(pwd)/fake-bin:${PATH}" "${image}" "$@"
EOF
		cat >fake-bin/helm <<'EOF'
#!/bin/sh
set -eu

case "$1" in
lint)
	exit 0
	;;
template)
	release=$2
	printf 'release: %s\n' "${release}"
	;;
package)
	shift
	chart=''
	destination=''
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--destination)
			shift
			destination=${1:-}
			;;
		*)
			if [ -z "${chart}" ]; then
				chart=$1
			fi
			;;
		esac
		shift
	done
	[ -n "${chart}" ] || exit 1
	[ -n "${destination}" ] || exit 1
	mkdir -p "${destination}"
	tar -C "$(dirname "${chart}")" -czf "${destination}/custom-release-0.1.0.tgz" "$(basename "${chart}")"
	;;
*)
exit 0
	;;
esac
EOF
		chmod +x fake-bin/docker fake-bin/helm
		cat >config/project.cfg.test <<'EOF'
. ./config/project.cfg
K8S_RENDER_DIR='out/k8s/rendered'
K8S_RELEASE_NAME='custom-release'
EOF
		PATH="${workdir}/fake-bin:${PATH}" \
			sh ./scripts/scan.sh config/project.cfg.test >/tmp/template-scan-render-dir.txt
		grep -F -- '/tmp/k8s-scan-manifest.' docker.log || fail 'scan should stage the rendered Kubernetes manifest into the mounted temp directory'
		grep -F -- '/tmp/k8s-scan-manifest.' docker.log | grep -F -- 'custom-release.yaml' >/dev/null || fail 'scan should pass the rendered Kubernetes manifest basename to Trivy'
		! grep -F -- '/workspace/out/k8s/rendered' docker.log >/dev/null 2>&1 || fail 'scan should not assume the render directory is mounted inside the scanner container'
		: >docker.log
		absolute_render_dir=$(mktemp -d "${workdir}/external-render.XXXXXX")
		cat >config/project.cfg.absolute <<EOF
. ./config/project.cfg
PROJECT_NAME='Derived_App'
PROJECT_IMAGE='registry.example.com/derived-app:local'
DEV_K8S_HELM_IMAGE='fake/helm:latest'
K8S_RELEASE_NAME=''
K8S_RENDER_DIR='${absolute_render_dir}'
EOF
		PATH="${workdir}/fake-bin:${PATH}" \
			sh ./scripts/scan.sh config/project.cfg.absolute >/tmp/template-scan-absolute-render-dir.txt
		[ -f "${absolute_render_dir}/derived-app.yaml" ] || fail 'scan should rely on the manifest path rendered by k8s.sh when K8S_RELEASE_NAME is omitted'
		grep -F -- '/tmp/k8s-scan-manifest.' docker.log | grep -F -- 'derived-app.yaml' >/dev/null || fail 'scan should stage the derived release-name manifest for Trivy'
		! grep -F -- "${absolute_render_dir}" docker.log >/dev/null 2>&1 || fail 'scan should not pass an absolute host render directory directly into the scanner container'
	)
	rm -rf "${workdir}"
}

test_k8s_chart_packaging_uses_project_defaults() {
	workdir=$(mktemp -d)
	root_dir=$(pwd)

	(
		cd "${workdir}"
		tar -C "${root_dir}" -cf - . | tar -xf -
		mkdir -p fake-bin
		cat >fake-bin/docker <<'EOF'
#!/bin/sh
set -eu

if [ "${1:-}" = "run" ]; then
	shift
fi

image=''
while [ "$#" -gt 0 ]; do
	case "$1" in
	--rm | --cap-drop=* | --security-opt=*)
		shift
		continue
		;;
	-e | -v | -w | --user)
		shift
		[ "$#" -gt 0 ] && shift
		continue
		;;
	*)
		image=$1
		shift
		break
		;;
	esac
done

[ -n "${image}" ] || exit 1
case "${image}" in
*helm*)
	image="$(pwd)/fake-bin/helm"
	;;
esac
PATH="$(pwd)/fake-bin:${PATH}" "${image}" "$@"
EOF
		cat >fake-bin/helm <<'EOF'
#!/bin/sh
set -eu

yaml_value() {
	file=$1
	key=$2
	awk -F': ' -v key="${key}" '$1 == key { print $2; exit }' "${file}"
}

image_value() {
	file=$1
	key=$2
	awk -v key="${key}" '
		/^image:/ { in_image = 1; next }
		in_image && /^[^[:space:]]/ { in_image = 0 }
		in_image && $1 == key ":" { print $2; exit }
	' "${file}"
}

case "$1" in
lint)
	chart=$2
	[ -f "${chart}/Chart.yaml" ] || exit 1
	;;
template)
	release=$2
	chart=$3
	printf 'release: %s\n' "${release}"
	printf 'chartName: %s\n' "$(yaml_value "${chart}/Chart.yaml" "name")"
	printf 'imageRepository: %s\n' "$(image_value "${chart}/values.yaml" "repository")"
	printf 'imageTag: %s\n' "$(image_value "${chart}/values.yaml" "tag")"
	;;
package)
	chart=$2
	shift 2
	destination=''
	while [ "$#" -gt 0 ]; do
		if [ "$1" = "--destination" ]; then
			shift
			destination=$1
			break
		fi
		shift
	done
	[ -n "${destination}" ] || exit 1
	mkdir -p "${destination}"
	chart_name=$(yaml_value "${chart}/Chart.yaml" "name")
	chart_version=$(yaml_value "${chart}/Chart.yaml" "version")
	tar -C "$(dirname "${chart}")" -czf "${destination}/${chart_name}-${chart_version}.tgz" "$(basename "${chart}")"
	;;
*)
	exit 1
	;;
esac
EOF
		chmod +x fake-bin/docker fake-bin/helm
		cat >config/project.cfg.test <<'EOF'
PROJECT_NAME='derived-app'
PROJECT_IMAGE='registry.example.com:5000/derived-app:local'
DEV_K8S_HELM_IMAGE='fake/helm:latest'
K8S_CHART_PATH='config/k8s/chart'
K8S_RELEASE_NAME="${PROJECT_NAME}"
K8S_NAME_OVERRIDE="${PROJECT_NAME}"
K8S_NAMESPACE='default'
K8S_VALUES_FILE=''
EOF
		PATH="${workdir}/fake-bin:${PATH}" sh ./scripts/k8s.sh config/project.cfg.test >/tmp/template-k8s-staged.txt
		grep -q '^chartName: derived-app$' .tmp/k8s/rendered/derived-app.yaml || fail 'k8s render should use the project-specific chart metadata'
		grep -q '^imageRepository: registry.example.com:5000/derived-app$' .tmp/k8s/rendered/derived-app.yaml || fail 'k8s render should derive the repository from PROJECT_IMAGE without the tag'
		grep -q '^imageTag: local$' .tmp/k8s/rendered/derived-app.yaml || fail 'k8s render should derive the tag from PROJECT_IMAGE when K8S_IMAGE_TAG is unset'
		tar -xOzf .tmp/k8s/package/derived-app-0.1.0.tgz chart/Chart.yaml | grep -q '^name: derived-app$' || fail 'packaged chart should use the project-specific chart name'
		tar -xOzf .tmp/k8s/package/derived-app-0.1.0.tgz chart/values.yaml | grep -q '^  repository: registry.example.com:5000/derived-app$' || fail 'packaged chart values should use the configured image repository'
		tar -xOzf .tmp/k8s/package/derived-app-0.1.0.tgz chart/values.yaml | grep -q '^  tag: local$' || fail 'packaged chart values should use the configured image tag'
	)
	rm -rf "${workdir}"
}

test_k8s_test_local_uses_kubeconfig_and_server_dry_run() {
	workdir=$(mktemp -d)
	root_dir=$(pwd)

	(
		cd "${workdir}"
		tar -C "${root_dir}" -cf - . | tar -xf -
		mkdir -p fake-bin fake-kubeconfig config/k8s .tmp/k8s/rendered scripts
		cat >fake-bin/docker <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>docker.log

case "$1" in
run)
	printf '%s\n' 'service/test-svc'
	exit 0
	;;
esac

exit 0
EOF
		chmod +x fake-bin/docker
		cat >scripts/k8s.sh <<'SCRIPT'
#!/bin/sh
set -eu
PROJECT_CFG_FILE=${1:-config/project.cfg}
. "${PROJECT_CFG_FILE}"

sanitize_k8s_name() {
	printf '%s' "$1" |
		tr '[:upper:]' '[:lower:]' |
		tr -cs 'a-z0-9' '-' |
		sed -e 's/^-*//' -e 's/-*$//'
}

default_k8s_name=$(sanitize_k8s_name "${PROJECT_NAME:-}")
[ -n "${default_k8s_name}" ] || default_k8s_name=app
release_name=${K8S_RELEASE_NAME:-${default_k8s_name}}
[ -n "${release_name}" ] || release_name=kc-secure-template
render_dir=${K8S_RENDER_DIR:-.tmp/k8s/rendered}
render_file="${render_dir}/${release_name}.yaml"

mkdir -p "${render_dir}"
cat >"${render_file}" <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: test-svc
spec:
  ports:
    - port: 80
      targetPort: 8080
  selector:
    app: test
YAML
if [ -n "${K8S_METADATA_FILE:-}" ]; then
	cat >"${K8S_METADATA_FILE}" <<METADATA
K8S_RENDER_FILE='${render_file}'
METADATA
fi
SCRIPT
		chmod +x scripts/k8s.sh
		cat >config/project.cfg <<'EOF'
PROJECT_NAME='kc-secure-template'
DEV_K8S_KUBECTL_IMAGE='bitnami/kubectl:latest'
EOF
		cat >fake-kubeconfig/config <<'EOF'
apiVersion: v1
kind: Config
clusters: []
contexts: []
current-context: ''
users: []
EOF
		PATH="${workdir}/fake-bin:${PATH}" \
			K8S_TEST_LOCAL_KUBECONFIG="${workdir}/fake-kubeconfig/config" \
			K8S_TEST_LOCAL_CONTEXT='kind-local' \
			sh ./scripts/k8s-test-local.sh config/project.cfg >/tmp/template-k8s-test-local.txt
		! grep -F -- ' build ' docker.log >/dev/null 2>&1 || fail 'k8s-test-local should not build a repo-controlled kubectl image'
		grep -F -- 'bitnami/kubectl:latest' docker.log || fail 'k8s-test-local should run the configured kubectl image'
		grep -F -- '--dry-run=server' docker.log || fail 'k8s-test-local should use kubectl server-side dry-run'
		grep -F -- "--context kind-local" docker.log || fail 'k8s-test-local should pass the configured Kubernetes context'
		! grep -F -- "${workdir}/fake-kubeconfig:/tmp/k8s-test-kubeconfig:ro" docker.log >/dev/null 2>&1 || fail 'k8s-test-local should not mount the original kubeconfig directory'
		grep -F -- '/tmp/tmp.' docker.log || fail 'k8s-test-local should mount a staged kubeconfig directory'
		grep -F -- '/tmp/k8s-test-local-manifest.' docker.log | grep -F -- 'kc-secure-template.yaml' >/dev/null || fail 'k8s-test-local should stage the rendered manifest into the mounted temp directory'
		grep -q 'Resources checked by server-side dry-run: 1' /tmp/template-k8s-test-local.txt || fail 'k8s-test-local should report the dry-run resource count'
		: >docker.log
		external_render_dir=$(mktemp -d "${workdir}/external-render.XXXXXX")
		cat >config/project.cfg.absolute <<EOF
. ./config/project.cfg
PROJECT_NAME='Derived_App'
DEV_K8S_KUBECTL_IMAGE='bitnami/kubectl:latest'
K8S_RELEASE_NAME=''
K8S_RENDER_DIR='${external_render_dir}'
EOF
		PATH="${workdir}/fake-bin:${PATH}" \
			K8S_TEST_LOCAL_KUBECONFIG="${workdir}/fake-kubeconfig/config" \
			sh ./scripts/k8s-test-local.sh config/project.cfg.absolute >/tmp/template-k8s-test-local-absolute.txt
		[ -f "${external_render_dir}/derived-app.yaml" ] || fail 'k8s-test-local should use the manifest path rendered by k8s.sh when K8S_RELEASE_NAME is omitted'
		grep -F -- '/tmp/k8s-test-local-manifest.' docker.log | grep -F -- 'derived-app.yaml' >/dev/null || fail 'k8s-test-local should stage the derived release-name manifest for kubectl'
		! grep -F -- "${external_render_dir}" docker.log >/dev/null 2>&1 || fail 'k8s-test-local should not pass an absolute host render directory directly into the kubectl container'
	)
	rm -rf "${workdir}"
}

case "${mode}" in
src)
	# Validate the default bundled Go example the same way a derived repo would.
	PROJECT_CFG_FILE_PATH=${PROJECT_CFG_FILE}
	case "${PROJECT_CFG_FILE_PATH}" in
	/* | ./* | ../*) ;;
	*) PROJECT_CFG_FILE_PATH="./${PROJECT_CFG_FILE_PATH}" ;;
	esac
	[ -f "${PROJECT_CFG_FILE_PATH}" ] || fail "missing ${PROJECT_CFG_FILE_PATH}; set PROJECT_CFG_FILE to an existing config file"
	. "${PROJECT_CFG_FILE_PATH}"

	# The example image name is derived from the project name to avoid collisions.
	case "${PROJECT_NAME}" in
	*-dev) src_name=${PROJECT_NAME%-dev}-example ;;
	*) src_name=${PROJECT_NAME}-example ;;
	esac
	src_image="${src_name}:local"

	# Build the image on demand if the user runs tests from a clean checkout.
	if ! docker image inspect "${src_image}" >/dev/null 2>&1; then
		sh ./scripts/build.sh "${PROJECT_CFG_FILE}"
	fi

	# Match host ownership for bind-mounted caches and workspace files.
	docker_uid=${DOCKER_UID:-$(id -u)}
	docker_gid=${DOCKER_GID:-$(id -g)}
	docker_home=${DOCKER_HOME:-/tmp/kc-template-home}
	docker_cache_home=${DOCKER_CACHE_HOME:-${docker_home}/.cache}
	docker_home_source=${DOCKER_HOME_SOURCE:-$(pwd)/.cache/docker-home}
	docker_tmpdir=${DOCKER_TMPDIR:-$(pwd)/.cache/docker-tmp}
	mkdir -p "${docker_home_source}" "${docker_tmpdir}"

	printf '\n==> Lint src workspace\n'
	# Formatting and vet checks run before tests so failures are easier to interpret.
	docker run --rm --user "${docker_uid}:${docker_gid}" \
		--cap-drop=ALL \
		--security-opt=no-new-privileges:true \
		-e HOME="${docker_home}" \
		-e XDG_CACHE_HOME="${docker_cache_home}" \
		-v "${docker_home_source}:${docker_home}" \
		-v "${docker_tmpdir}:/tmp" \
		-v "$(pwd):/workspace" \
		-w /workspace \
		"${src_image}" \
		sh -eu -c 'cd src && test -z "$(gofmt -l .)" && go vet ./...'

	printf '\n==> Test and build src workspace\n'
	# Run the example unit tests and build in the same containerized environment.
	docker run --rm --user "${docker_uid}:${docker_gid}" \
		--cap-drop=ALL \
		--security-opt=no-new-privileges:true \
		-e HOME="${docker_home}" \
		-e XDG_CACHE_HOME="${docker_cache_home}" \
		-v "${docker_home_source}:${docker_home}" \
		-v "${docker_tmpdir}:/tmp" \
		-v "$(pwd):/workspace" \
		-w /workspace \
		"${src_image}" \
		sh -eu -c 'cd src && go test -v ./... && go build -trimpath -buildvcs=false ./cmd/app'

	printf '\n==> Test summary\n'
	# Summaries make CI and local output easier to scan.
	printf '%s\n' "Image: ${src_image}"
	printf '%s\n' "Project config: ${PROJECT_CFG_FILE}"
	printf '%s\n' 'Workspace: src'
	printf '%s\n' 'Results: lint passed, tests passed, build passed'
	;;
template)
	# Validate that the template wiring, documentation, and release outputs stay in sync.
	find scripts -type f -name '*.sh' -print | LC_ALL=C sort | while IFS= read -r path; do
		sh -n "${path}"
	done
	[ ! -d scripts/lib ] || fail 'scripts/lib should not exist'
	. ./config/lockfile.cfg
	make help >/tmp/template-help.txt
	grep -q 'Available targets' /tmp/template-help.txt || fail 'make help output is missing the target list'
	make -n build | grep -q 'sh scripts/build.sh "' || fail 'make build should call scripts/build.sh'
	make -n test | grep -q 'sh scripts/test.sh "' || fail 'make test should call scripts/test.sh'
	make -n scan | grep -q 'sh scripts/scan.sh "' || fail 'make scan should call scripts/scan.sh'
	make -n k8s | grep -q 'sh scripts/k8s.sh "' || fail 'make k8s should call scripts/k8s.sh'
	make -n k8s-test-local | grep -q 'sh scripts/k8s-test-local.sh "' || fail 'make k8s-test-local should call scripts/k8s-test-local.sh'
	make -n dist | grep -q 'sh scripts/dist.sh "' || fail 'make dist should call scripts/dist.sh'
	! grep -qx 'config/project.cfg' .dockerignore || fail '.dockerignore should not exclude tracked config/project.cfg'
	! grep -qx 'config/project.cfg' .gitignore || fail '.gitignore should not exclude tracked config/project.cfg'
	check_workflow_action_pins
	assert_no_nested_dist_dirs
	test_optional_k8s_update_compat
	test_optional_k8s_scan_skip
	test_k8s_shell_inputs_are_not_executed
	test_k8s_render_file_scan_path
	test_k8s_chart_packaging_uses_project_defaults
	test_k8s_test_local_uses_kubeconfig_and_server_dry_run
	rm -rf dist
	# `make example` should exercise the demo without leaving release artifacts behind.
	PROJECT_CFG_FILE=config/project.cfg make example >/tmp/template-example.txt
	[ ! -d dist ] || fail 'make example should not create root dist'
	grep -q 'Run secret scan' /tmp/template-example.txt || fail 'make example should run the security scan'
	assert_no_nested_dist_dirs
	rm -rf .tmp
	# Infra validation should also avoid writing release outputs.
	PROJECT_CFG_FILE=config/project.cfg make infra >/tmp/template-infra.txt
	[ ! -d dist ] || fail 'make infra should not create root dist'
	assert_no_nested_dist_dirs
	PROJECT_CFG_FILE=config/project.cfg make k8s >/tmp/template-k8s.txt
	grep -q 'Rendered manifest:' /tmp/template-k8s.txt || fail 'make k8s should render the bundled Helm chart'
	[ -f .tmp/k8s/rendered/kc-secure-template.yaml ] || fail 'make k8s should write a rendered Kubernetes manifest'
	grep -q 'app.kubernetes.io/name: kc-secure-template' .tmp/k8s/rendered/kc-secure-template.yaml || fail 'make k8s should derive the chart app name from PROJECT_NAME by default'
	find .tmp/k8s/package -maxdepth 1 -type f -name '*.tgz' | grep -q . || fail 'make k8s should package the bundled Helm chart'
	cat >/tmp/template-k8s-values.yaml <<'EOF'
container:
  port: 8080
service:
  port: 80
EOF
	PROJECT_CFG_FILE=config/project.cfg K8S_VALUES_FILE=/tmp/template-k8s-values.yaml make k8s >/tmp/template-k8s-custom-port.txt
	grep -q 'containerPort: 8080' .tmp/k8s/rendered/kc-secure-template.yaml || fail 'make k8s should keep the container port independent from the Service port'
	grep -q 'port: 80' .tmp/k8s/rendered/kc-secure-template.yaml || fail 'make k8s should allow the Service port to differ from the container port'
	external_render_dir=$(mktemp -d)
	external_package_dir=$(mktemp -d)
	cat >/tmp/template-k8s-external-values.yaml <<'EOF'
container:
  port: 9090
EOF
	PROJECT_CFG_FILE=config/project.cfg \
		K8S_VALUES_FILE=/tmp/template-k8s-external-values.yaml \
		K8S_RENDER_DIR="${external_render_dir}" \
		K8S_PACKAGE_DIR="${external_package_dir}" \
		make k8s >/tmp/template-k8s-external-paths.txt
	[ -f "${external_render_dir}/kc-secure-template.yaml" ] || fail 'make k8s should write rendered manifests to an external K8S_RENDER_DIR'
	grep -q 'containerPort: 9090' "${external_render_dir}/kc-secure-template.yaml" || fail 'make k8s should apply an external K8S_VALUES_FILE override'
	find "${external_package_dir}" -maxdepth 1 -type f -name '*.tgz' | grep -q . || fail 'make k8s should package charts into an external K8S_PACKAGE_DIR'
	rm -rf "${external_render_dir}" "${external_package_dir}"
	sed \
		-e "s/^PROJECT_NAME='kc-secure-template'/PROJECT_NAME='My_App'/" \
		-e "s#^PROJECT_IMAGE=.*#PROJECT_IMAGE='ghcr.io/example/my-app:local'#" \
		config/project.cfg >/tmp/template-k8s-sanitized.cfg
	sh ./scripts/k8s.sh /tmp/template-k8s-sanitized.cfg >/tmp/template-k8s-sanitized.txt
	[ -f .tmp/k8s/rendered/my-app.yaml ] || fail 'make k8s should sanitize the default release name for non-DNS-safe project names'
	grep -q 'app.kubernetes.io/instance: my-app' .tmp/k8s/rendered/my-app.yaml || fail 'make k8s should render a DNS-safe default release label for non-DNS-safe project names'
	grep -q 'app.kubernetes.io/name: my-app' .tmp/k8s/rendered/my-app.yaml || fail 'make k8s should sanitize the default chart app name for non-DNS-safe project names'
	cat >/tmp/template-k8s-digest.cfg <<'EOF'
. ./config/project.cfg
K8S_IMAGE_REPOSITORY='ghcr.io/example/app'
K8S_IMAGE_TAG='sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
EOF
	sh ./scripts/k8s.sh /tmp/template-k8s-digest.cfg >/tmp/template-k8s-digest.txt
	grep -q 'image: "ghcr.io/example/app@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"' .tmp/k8s/rendered/kc-secure-template.yaml || fail 'make k8s should render digest-pinned images with @sha256 references'
	sh ./scripts/template.sh manifest
	tail -n +2 dist/template-manifest.txt >/tmp/template-manifest.txt
	list_template_files >/tmp/template-expected-manifest.txt
	cmp -s /tmp/template-manifest.txt /tmp/template-expected-manifest.txt || fail 'template manifest is out of sync'
	rm -rf dist
	ENABLE_SBOM=false ENABLE_GRYPE=false make dist PROJECT_CFG_FILE=config/project.cfg >/dev/null
	cp dist/kc-secure-repo-template.tar.gz /tmp/template-first.tar.gz
	rm -rf dist
	ENABLE_SBOM=false ENABLE_GRYPE=false make dist PROJECT_CFG_FILE=config/project.cfg >/dev/null
	cp dist/kc-secure-repo-template.tar.gz /tmp/template-second.tar.gz
	[ "$(sha256sum /tmp/template-first.tar.gz | awk '{print $1}')" = "$(sha256sum /tmp/template-second.tar.gz | awk '{print $1}')" ] || fail 'release archive should be reproducible'
	;;
smoke)
	# Smoke mode copies the template into temporary directories and adapts it like a new user would.
	workdir=$(mktemp -d)
	root_dir=$(pwd)
	trap 'rm -rf "${workdir}"' EXIT INT TERM
	list_template_files >"${workdir}/files.txt"
	mkdir -p "${workdir}/go" "${workdir}/infra"
	(
		cd "${workdir}/go"
		tar -C "${root_dir}" -cf - -T "${workdir}/files.txt" | tar -xf -
		rm -rf src
		mkdir -p src/cmd/app
		# Create a minimal Go project that uses the template's container-first workflow.
		cat >src/go.mod <<'EOF'
module example.com/template-go-smoke

go 1.26.1
EOF
		cat >src/cmd/app/main.go <<'EOF'
package main

import "fmt"

func main() {
	fmt.Println("hello from go smoke test")
}
EOF
		cat >config/project.cfg <<'EOF'
DEV_BASE_IMAGE='golang:1.26.1-trixie@sha256:1d414b0376b53ec94b9a2493229adb81df8b90af014b18619732f1ceaaf7234a'
DEV_PACKAGE_SNAPSHOT_LOCK='20260401T164506Z'
DEV_SCAN_GITLEAKS_IMAGE_LOCK='ghcr.io/gitleaks/gitleaks@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f'
DEV_SCAN_ACTIONLINT_IMAGE_LOCK='rhysd/actionlint:1.7.12@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667'
ENABLE_SBOM='false'
ENABLE_GRYPE='false'
DEV_K8S_HELM_IMAGE='alpine/helm:3.19.0'
K8S_CHART_PATH='config/k8s/chart'
K8S_RELEASE_NAME='smoke-go'
K8S_NAMESPACE='smoke'
K8S_VALUES_FILE=''
K8S_IMAGE_REPOSITORY='example.com/template-go-smoke'
K8S_IMAGE_TAG='smoke'
EOF
		cat >Dockerfile <<'EOF'
# syntax=docker/dockerfile:1
ARG DEV_BASE_IMAGE
ARG DEV_PACKAGE_SNAPSHOT

FROM ${DEV_BASE_IMAGE:-golang:1.26.1-trixie} AS dev

WORKDIR /workspace
COPY . .

CMD ["sh", "-eu", "-c", "cd src && test -z \"$(gofmt -l .)\" && go vet ./... && go test ./... && go build -trimpath -buildvcs=false ./cmd/app"]
EOF
		cat >scripts/scan.sh <<'EOF'
#!/bin/sh
set -eu

PROJECT_CFG_FILE=${1:-${PROJECT_CFG_FILE:-config/project.cfg}}
project_cfg_file=${PROJECT_CFG_FILE}
case "${project_cfg_file}" in
/* | ./* | ../*) ;;
*) project_cfg_file="./${project_cfg_file}" ;;
esac
. "${project_cfg_file}"

docker build \
	--build-arg DEV_BASE_IMAGE="${DEV_BASE_IMAGE_LOCK:-${DEV_BASE_IMAGE}}" \
	--build-arg DEV_PACKAGE_SNAPSHOT="${DEV_PACKAGE_SNAPSHOT_LOCK}" \
	-t smoke-go:local .

docker run --rm -v "$(pwd):/workspace" -w /workspace smoke-go:local \
	sh -eu -c 'cd src && test -z "$(gofmt -l .)" && go vet ./... && go test ./... && go build -trimpath -buildvcs=false ./cmd/app'
EOF
		cat >scripts/dist.sh <<'EOF'
#!/bin/sh
set -eu

PROJECT_CFG_FILE=${1:-${PROJECT_CFG_FILE:-config/project.cfg}}
project_cfg_file=${PROJECT_CFG_FILE}
case "${project_cfg_file}" in
/* | ./* | ../*) ;;
*) project_cfg_file="./${project_cfg_file}" ;;
esac
. "${project_cfg_file}"

docker build \
	--build-arg DEV_BASE_IMAGE="${DEV_BASE_IMAGE_LOCK:-${DEV_BASE_IMAGE}}" \
	--build-arg DEV_PACKAGE_SNAPSHOT="${DEV_PACKAGE_SNAPSHOT_LOCK}" \
	-t smoke-go:local .

mkdir -p dist
docker run --rm -v "$(pwd):/workspace" -w /workspace smoke-go:local \
	sh -eu -c 'cd src && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -buildvcs=false -ldflags="-s -w" -o ../dist/app-linux-amd64 ./cmd/app'
EOF
		chmod +x scripts/scan.sh scripts/dist.sh
		# The copied template should still be easy to adapt to a simple Go repository.
		make scan PROJECT_CFG_FILE=config/project.cfg >/dev/null
		make k8s PROJECT_CFG_FILE=config/project.cfg >/dev/null
		make dist PROJECT_CFG_FILE=config/project.cfg >/dev/null
		[ -d dist ] || fail 'make dist should create root dist'
		[ ! -d src/dist ] || fail 'make dist should not create src/dist'
		[ -f .tmp/k8s/rendered/smoke-go.yaml ] || fail 'make k8s should render the optional Helm chart in a copied repo'
		assert_no_nested_dist_dirs
	)
	(
		cd "${workdir}/infra"
		tar -C "${root_dir}" -cf - -T "${workdir}/files.txt" | tar -xf -
		# Also verify the bundled infra workspace works in a fresh copied repository.
		cat >config/project.cfg <<'EOF'
DEV_BASE_IMAGE='debian:trixie-slim@sha256:4ffb3a1511099754cddc70eb1b12e50ffdb67619aa0ab6c13fcd800a78ef7c7a'
DEV_PACKAGE_SNAPSHOT_LOCK='20260401T164506Z'
DEV_TERRAFORM_IMAGE='hashicorp/terraform:1.14.8'
DEV_TERRAFORM_IMAGE_LOCK='hashicorp/terraform:1.14.8@sha256:42ecfb253183ec823646dd7859c5652039669409b44daa72abf57112e622849a'
DEV_SCAN_GITLEAKS_IMAGE_LOCK='ghcr.io/gitleaks/gitleaks@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f'
ENABLE_SBOM='false'
ENABLE_GRYPE='false'
EOF
		make infra PROJECT_CFG_FILE=config/project.cfg >/dev/null
		[ ! -d dist ] || fail 'make infra should not create root dist'
		assert_no_nested_dist_dirs
	)
	;;
*)
	fail "unknown mode: ${mode}"
	;;
esac
