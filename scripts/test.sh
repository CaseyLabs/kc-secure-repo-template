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

PROJECT_ENV=${1:-${PROJECT_ENV:-project.env}}

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
project.env.example
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

case "${mode}" in
src)
	# Validate the default bundled Go example the same way a derived repo would.
	PROJECT_ENV_PATH=${PROJECT_ENV}
	case "${PROJECT_ENV_PATH}" in
	/* | ./* | ../*) ;;
	*) PROJECT_ENV_PATH="./${PROJECT_ENV_PATH}" ;;
	esac
	[ -f "${PROJECT_ENV_PATH}" ] || fail "missing ${PROJECT_ENV_PATH}; copy project.env.example to ${PROJECT_ENV} first"
	. "${PROJECT_ENV_PATH}"

	# The example image name is derived from the project name to avoid collisions.
	case "${PROJECT_NAME}" in
	*-dev) src_name=${PROJECT_NAME%-dev}-example ;;
	*) src_name=${PROJECT_NAME}-example ;;
	esac
	src_image="${src_name}:local"

	# Build the image on demand if the user runs tests from a clean checkout.
	if ! docker image inspect "${src_image}" >/dev/null 2>&1; then
		sh ./scripts/build.sh "${PROJECT_ENV}"
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

	printf '\n==> Test src workspace\n'
	# Run the example unit tests in the same containerized environment.
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
		sh -eu -c 'cd src && go test -v ./...'

	printf '\n==> Test summary\n'
	# Summaries make CI and local output easier to scan.
	printf '%s\n' "Image: ${src_image}"
	printf '%s\n' "Project env: ${PROJECT_ENV}"
	printf '%s\n' 'Workspace: src'
	printf '%s\n' 'Results: lint passed, tests passed'
	;;
template)
	# Validate that the template wiring, documentation, and release outputs stay in sync.
	find scripts -type f -name '*.sh' -print | LC_ALL=C sort | while IFS= read -r path; do
		sh -n "${path}"
	done
	[ ! -d scripts/lib ] || fail 'scripts/lib should not exist'
	make help >/tmp/template-help.txt
	grep -q 'Available targets' /tmp/template-help.txt || fail 'make help output is missing the target list'
	make -n build | grep -q 'sh scripts/build.sh "' || fail 'make build should call scripts/build.sh'
	make -n test | grep -q 'sh scripts/test.sh "' || fail 'make test should call scripts/test.sh'
	make -n scan | grep -q 'sh scripts/scan.sh "' || fail 'make scan should call scripts/scan.sh'
	make -n dist | grep -q 'sh scripts/dist.sh "' || fail 'make dist should call scripts/dist.sh'
	grep -qx 'project.env' .dockerignore || fail '.dockerignore should exclude project.env from Docker build contexts'
	check_workflow_action_pins
	assert_no_nested_dist_dirs
	rm -rf dist
	# `make example` should exercise the demo without leaving release artifacts behind.
	PROJECT_ENV=project.env.example make example >/tmp/template-example.txt
	[ ! -d dist ] || fail 'make example should not create root dist'
	grep -q 'Run secret scan' /tmp/template-example.txt || fail 'make example should run the security scan'
	assert_no_nested_dist_dirs
	rm -rf .tmp
	# Infra validation should also avoid writing release outputs.
	PROJECT_ENV=project.env.example make infra >/tmp/template-infra.txt
	[ ! -d dist ] || fail 'make infra should not create root dist'
	assert_no_nested_dist_dirs
	sh ./scripts/template.sh manifest
	tail -n +2 dist/template-manifest.txt >/tmp/template-manifest.txt
	list_template_files >/tmp/template-expected-manifest.txt
	cmp -s /tmp/template-manifest.txt /tmp/template-expected-manifest.txt || fail 'template manifest is out of sync'
	rm -rf dist
	ENABLE_SBOM=false ENABLE_GRYPE=false make dist PROJECT_ENV=project.env.example >/dev/null
	cp dist/kc-secure-repo-template.tar.gz /tmp/template-first.tar.gz
	rm -rf dist
	ENABLE_SBOM=false ENABLE_GRYPE=false make dist PROJECT_ENV=project.env.example >/dev/null
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
		cat >project.env <<'EOF'
DEV_BASE_IMAGE='golang:1.26.1-bookworm@sha256:09f72a3e4d00f209358f03b93e4d62e6ed45b786569c2d97e83cb7cbaaed15f2'
DEV_PACKAGE_SNAPSHOT_LOCK='20260401T164506Z'
DEV_SCAN_GITLEAKS_IMAGE_LOCK='ghcr.io/gitleaks/gitleaks@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f'
DEV_SCAN_ACTIONLINT_IMAGE_LOCK='rhysd/actionlint:1.7.12@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667'
ENABLE_SBOM='false'
ENABLE_GRYPE='false'
EOF
		cat >Dockerfile <<'EOF'
# syntax=docker/dockerfile:1
ARG DEV_BASE_IMAGE
ARG DEV_PACKAGE_SNAPSHOT

FROM ${DEV_BASE_IMAGE:-golang:1.26.1-bookworm} AS dev

WORKDIR /workspace
COPY . .

CMD ["sh", "-eu", "-c", "cd src && test -z \"$(gofmt -l .)\" && go vet ./... && go test ./... && go build -trimpath -buildvcs=false ./cmd/app"]
EOF
		cat >scripts/scan.sh <<'EOF'
#!/bin/sh
set -eu

PROJECT_ENV=${1:-${PROJECT_ENV:-project.env}}
project_env=${PROJECT_ENV}
case "${project_env}" in
/* | ./* | ../*) ;;
*) project_env="./${project_env}" ;;
esac
. "${project_env}"

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

PROJECT_ENV=${1:-${PROJECT_ENV:-project.env}}
project_env=${PROJECT_ENV}
case "${project_env}" in
/* | ./* | ../*) ;;
*) project_env="./${project_env}" ;;
esac
. "${project_env}"

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
		make scan PROJECT_ENV=project.env >/dev/null
		make dist PROJECT_ENV=project.env >/dev/null
		[ -d dist ] || fail 'make dist should create root dist'
		[ ! -d src/dist ] || fail 'make dist should not create src/dist'
		assert_no_nested_dist_dirs
	)
	(
		cd "${workdir}/infra"
		tar -C "${root_dir}" -cf - -T "${workdir}/files.txt" | tar -xf -
		# Also verify the bundled infra workspace works in a fresh copied repository.
		cat >project.env <<'EOF'
DEV_BASE_IMAGE='debian:bookworm-slim@sha256:4724b8cc51e33e398f0e2e15e18d5ec2851ff0c2280647e1310bc1642182655d'
DEV_PACKAGE_SNAPSHOT_LOCK='20260401T164506Z'
DEV_TERRAFORM_IMAGE='hashicorp/terraform:1.14.8'
DEV_TERRAFORM_IMAGE_LOCK='hashicorp/terraform:1.14.8@sha256:42ecfb253183ec823646dd7859c5652039669409b44daa72abf57112e622849a'
DEV_SCAN_GITLEAKS_IMAGE_LOCK='ghcr.io/gitleaks/gitleaks@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f'
ENABLE_SBOM='false'
ENABLE_GRYPE='false'
EOF
		make infra PROJECT_ENV=project.env >/dev/null
		[ ! -d dist ] || fail 'make infra should not create root dist'
		assert_no_nested_dist_dirs
	)
	;;
*)
	fail "unknown mode: ${mode}"
	;;
esac
