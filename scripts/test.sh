#!/bin/sh
# shellcheck shell=sh disable=SC1090
set -eu

# Default to testing the bundled `src/` example, but allow broader validation modes.
mode=src
case "${1:-}" in
src | template | smoke | _regression)
	mode=$1
	shift
	;;
esac

PROJECT_CFG_FILE=${1:-${PROJECT_CFG_FILE:-config/project.cfg}}

# Use the production manifest rather than maintaining a second copy.
list_template_files() {
	sh ./scripts/template.sh files
}

# Print a consistent failure prefix and stop immediately.
fail() {
	printf 'FAIL: %s\n' "$1" >&2
	exit 1
}

assert_ci_change_detection() {
	name=$1
	changed_files=$2
	expected_test_code=$3
	expected_test_repo=$4
	fixture=${TMPDIR}/ci-changes-fixture

	printf '%s' "${changed_files}" >"${fixture}"
	output=$(CI_CHANGED_FILES_FILE="${fixture}" sh scripts/ci-changes.sh)
	expected_output=$(printf 'test_code=%s\ntest_repo=%s' "${expected_test_code}" "${expected_test_repo}")
	[ "${output}" = "${expected_output}" ] || {
		printf '%s\n' "${output}" >&2
		fail "${name}: unexpected detector output"
	}
}

test_ci_change_detection_rules() {
	assert_ci_change_detection 'recognized prose' 'README.md
LICENSE.md
AGENTS.md
CLAUDE.md
code_review.md
docs/github-ci.md
docs/guides/setup.md
.agents/code_review.md
.agents/skills/example/README.md' false false
	assert_ci_change_detection 'source, build, and script surfaces' 'src/cmd/app/main.go
Dockerfile
.dockerignore
Makefile
scripts/build.sh
config/project.cfg
config/lockfile.cfg
.github/workflows/test.yml' true true
	assert_ci_change_detection 'template configuration' 'config/k8s/chart/values.yaml' false true
	assert_ci_change_detection 'mixed prose and template configuration' 'docs/github-ci.md
config/infra/versions.tf' false true
	assert_ci_change_detection 'mixed prose and source' 'README.md
src/cmd/app/main.go' true true
	assert_ci_change_detection 'unknown path' 'examples/demo.txt' true true
	assert_ci_change_detection 'root Markdown is not implicitly prose' 'DESIGN.md' true true
	assert_ci_change_detection 'executable-looking docs path' 'docs/build.sh' true true
	assert_ci_change_detection 'empty diff' '' true true
}

test_ci_change_detection_output_contract() {
	fixture=${TMPDIR}/ci-output-fixture
	github_output=${TMPDIR}/github-output
	printf '%s\n' 'docs/github-ci.md' >"${fixture}"
	: >"${github_output}"
	stdout=$(CI_CHANGED_FILES_FILE="${fixture}" GITHUB_OUTPUT="${github_output}" sh scripts/ci-changes.sh)
	[ -z "${stdout}" ] || fail 'GITHUB_OUTPUT mode should not write decisions to stdout'
	expected_output=$(printf 'test_code=false\ntest_repo=false')
	actual_output=$(cat "${github_output}")
	[ "${actual_output}" = "${expected_output}" ] || fail 'GITHUB_OUTPUT should receive both boolean decisions'

	if CI_CHANGED_FILES_FILE="${TMPDIR}/missing-ci-fixture" sh scripts/ci-changes.sh >${TMPDIR}/missing-ci-stdout 2>${TMPDIR}/missing-ci-stderr; then
		fail 'a missing changed-files fixture should fail detection'
	fi
	grep -q 'missing changed-files fixture' ${TMPDIR}/missing-ci-stderr || fail 'missing fixture failure should be explicit'

	output=$(GITHUB_EVENT_NAME=push sh scripts/ci-changes.sh)
	[ "${output}" = "$(printf 'test_code=true\ntest_repo=true')" ] || fail 'non-PR events should run both jobs'
	output=$(GITHUB_EVENT_NAME=pull_request GITHUB_SHA=missing-history sh scripts/ci-changes.sh)
	[ "${output}" = "$(printf 'test_code=true\ntest_repo=true')" ] || fail 'missing PR history should run both jobs'
	fake_bin=${TMPDIR}/ci-failed-diff-bin
	mkdir "${fake_bin}"
	cat >"${fake_bin}/git" <<'EOF'
#!/bin/sh
case "${1:-}" in
rev-parse) exit 0 ;;
-c) exit 1 ;;
*) exit 1 ;;
esac
EOF
	chmod +x "${fake_bin}/git"
	output=$(PATH="${fake_bin}:${PATH}" GITHUB_EVENT_NAME=pull_request GITHUB_SHA=synthetic-merge sh scripts/ci-changes.sh)
	[ "${output}" = "$(printf 'test_code=true\ntest_repo=true')" ] || fail 'failed diffs should run both jobs'

	grep -Fq "outputs.test_code != 'false'" .github/workflows/test.yml || fail 'test-code should run for missing or malformed detector output'
	grep -Fq "outputs.test_repo != 'false'" .github/workflows/test.yml || fail 'test-repo should run for missing or malformed detector output'
}

test_ci_change_detection_git_history() {
	root_dir=$(pwd)
	history_dir=$(mktemp -d)

	if ! (
		cd "${history_dir}"
		mkdir home
		export HOME="${history_dir}/home"
		git init -q -b main source
		cd source
		git config user.name 'CI Detector Test'
		git config user.email 'ci-detector@example.invalid'
		mkdir -p src docs
		printf '%s\n' 'package main' >src/app.go
		printf '%s\n' 'package main' >src/remove.go
		printf '%s\n' '# Readme' >README.md
		git add .
		git commit -q -m initial

		git checkout -q -b feature
		printf '%s\n' '# Guide' >docs/guide.md
		git add docs/guide.md
		git commit -q -m docs

		git checkout -q main
		printf '%s\n' 'package main // base advanced' >src/app.go
		git commit -qam 'advance base independently'
		git merge -q --no-ff --no-edit feature
		git branch synthetic-merge
		merge_sha=$(git rev-parse HEAD)

		cd ..
		git clone -q --depth=2 --branch synthetic-merge "file://${history_dir}/source" shallow
		cd shallow
		output=$(GITHUB_EVENT_NAME=pull_request GITHUB_SHA="${merge_sha}" sh "${root_dir}/scripts/ci-changes.sh")
		[ "${output}" = "$(printf 'test_code=false\ntest_repo=false')" ] || {
			printf '%s\n' "${output}" >&2
			fail 'depth-two synthetic merge should compare its first parent with the tested tree'
		}

		cd "${history_dir}/source"
		git checkout -q -b rename-case "${merge_sha}^1"
		mkdir -p docs
		git mv src/app.go docs/app.md
		git commit -q -m 'move source into docs'
		git checkout -q synthetic-merge
		git merge -q --no-ff --no-edit rename-case
		rename_merge=$(git rev-parse HEAD)
		output=$(GITHUB_EVENT_NAME=pull_request GITHUB_SHA="${rename_merge}" sh "${root_dir}/scripts/ci-changes.sh")
		[ "${output}" = "$(printf 'test_code=true\ntest_repo=true')" ] || fail 'cross-category renames should classify both removed and added paths'

		git checkout -q -b deletion-case "${rename_merge}"
		git rm -q src/remove.go
		git commit -q -m 'delete source'
		git checkout -q synthetic-merge
		git merge -q --no-ff --no-edit deletion-case
		deletion_merge=$(git rev-parse HEAD)
		output=$(GITHUB_EVENT_NAME=pull_request GITHUB_SHA="${deletion_merge}" sh "${root_dir}/scripts/ci-changes.sh")
		[ "${output}" = "$(printf 'test_code=true\ntest_repo=true')" ] || fail 'source deletions should run both jobs'

		git checkout -q -b quoted-case "${deletion_merge}"
		quoted_path=$(printf 'docs/guide\tname.md')
		printf '%s\n' '# Quoted path' >"${quoted_path}"
		git add "${quoted_path}"
		git commit -q -m 'add quoted pathname'
		git checkout -q synthetic-merge
		git merge -q --no-ff --no-edit quoted-case
		quoted_merge=$(git rev-parse HEAD)
		output=$(GITHUB_EVENT_NAME=pull_request GITHUB_SHA="${quoted_merge}" sh "${root_dir}/scripts/ci-changes.sh")
		[ "${output}" = "$(printf 'test_code=true\ntest_repo=true')" ] || fail 'quoted pathnames should run both jobs'

		git checkout -q -b executable-docs-case "${quoted_merge}"
		printf '%s\n' '#!/bin/sh' >docs/build.sh
		chmod +x docs/build.sh
		git add docs/build.sh
		git commit -q -m 'add executable below docs'
		git checkout -q synthetic-merge
		git merge -q --no-ff --no-edit executable-docs-case
		executable_docs_merge=$(git rev-parse HEAD)
		output=$(GITHUB_EVENT_NAME=pull_request GITHUB_SHA="${executable_docs_merge}" sh "${root_dir}/scripts/ci-changes.sh")
		[ "${output}" = "$(printf 'test_code=true\ntest_repo=true')" ] || fail 'executable files below docs should run both jobs'

		git checkout -q -b prose-deletion-case "${executable_docs_merge}"
		git rm -q README.md
		git commit -q -m 'delete recognized prose'
		git checkout -q synthetic-merge
		git merge -q --no-ff --no-edit prose-deletion-case
		prose_deletion_merge=$(git rev-parse HEAD)
		output=$(GITHUB_EVENT_NAME=pull_request GITHUB_SHA="${prose_deletion_merge}" sh "${root_dir}/scripts/ci-changes.sh")
		[ "${output}" = "$(printf 'test_code=false\ntest_repo=false')" ] || fail 'recognized prose deletions should skip both jobs'
	); then
		rm -rf "${history_dir}"
		return 1
	fi
	rm -rf "${history_dir}"
}

test_workflow_pull_request_target_is_rejected() {
	workdir=$(mktemp -d)
	root_dir=$(pwd)

	(
		cd "${workdir}"
		(cd "${root_dir}" && sh scripts/template.sh files) >files.txt
		tar -C "${root_dir}" -cf fixture.tar -T files.txt
		tar -xf fixture.tar
		rm fixture.tar files.txt
		cat >.github/workflows/unsafe.yml <<'EOF'
name: unsafe
on:
  pull_request_target:
jobs:
  unsafe:
    runs-on: ubuntu-24.04
    steps:
      - run: echo unsafe
EOF
		if check_workflow_trigger_policy >${TMPDIR}/template-workflow-trigger-policy.txt 2>&1; then
			fail 'workflow trigger policy should reject pull_request_target'
		fi
		grep -q 'pull_request_target is not allowed' ${TMPDIR}/template-workflow-trigger-policy.txt || fail 'workflow trigger policy should report pull_request_target'
	)
	rm -rf "${workdir}"
}

test_workflow_issue_comment_is_rejected() {
	workdir=$(mktemp -d)
	root_dir=$(pwd)

	(
		cd "${workdir}"
		(cd "${root_dir}" && sh scripts/template.sh files) >files.txt
		tar -C "${root_dir}" -cf fixture.tar -T files.txt
		tar -xf fixture.tar
		rm fixture.tar files.txt
		cat >.github/workflows/unsafe.yml <<'EOF'
name: unsafe
on:
  issue_comment:
    types:
      - created
permissions:
  contents: read
jobs:
  unsafe:
    runs-on: ubuntu-24.04
    steps:
      - run: echo unsafe
EOF
		if check_workflow_trigger_policy >${TMPDIR}/template-workflow-trigger-policy.txt 2>&1; then
			fail 'workflow trigger policy should reject issue_comment'
		fi
		grep -q 'issue_comment is not allowed' ${TMPDIR}/template-workflow-trigger-policy.txt || fail 'workflow trigger policy should report issue_comment'
	)
	rm -rf "${workdir}"
}

test_workflow_run_is_rejected_without_policy_exception() {
	workdir=$(mktemp -d)
	root_dir=$(pwd)

	(
		cd "${workdir}"
		(cd "${root_dir}" && sh scripts/template.sh files) >files.txt
		tar -C "${root_dir}" -cf fixture.tar -T files.txt
		tar -xf fixture.tar
		rm fixture.tar files.txt
		cat >.github/workflows/unsafe.yml <<'EOF'
name: unsafe
on:
  workflow_run:
    workflows:
      - test.yml
    types:
      - completed
permissions:
  contents: write
jobs:
  unsafe:
    runs-on: ubuntu-24.04
    steps:
      - run: echo unsafe
EOF
		if check_workflow_trigger_policy >${TMPDIR}/template-workflow-trigger-policy.txt 2>&1; then
			fail 'workflow trigger policy should reject workflow_run'
		fi
		grep -q 'workflow_run requires a dedicated reviewed policy exception' ${TMPDIR}/template-workflow-trigger-policy.txt || fail 'workflow trigger policy should report workflow_run'
	)
	rm -rf "${workdir}"
}

test_workflow_missing_permissions_is_rejected() {
	workdir=$(mktemp -d)
	root_dir=$(pwd)

	(
		cd "${workdir}"
		(cd "${root_dir}" && sh scripts/template.sh files) >files.txt
		tar -C "${root_dir}" -cf fixture.tar -T files.txt
		tar -xf fixture.tar
		rm fixture.tar files.txt
		cat >.github/workflows/unsafe.yml <<'EOF'
name: unsafe
on:
  pull_request:
jobs:
  unsafe:
    runs-on: ubuntu-24.04
    steps:
      - run: echo unsafe
EOF
		if check_workflow_permissions_policy >${TMPDIR}/template-workflow-permissions-policy.txt 2>&1; then
			fail 'workflow permissions policy should reject missing permissions'
		fi
		grep -q 'missing top-level permissions block' ${TMPDIR}/template-workflow-permissions-policy.txt || fail 'workflow permissions policy should report missing permissions'
	)
	rm -rf "${workdir}"
}

test_workflow_metadata_interpolation_is_rejected() {
	workdir=$(mktemp -d)
	root_dir=$(pwd)

	(
		cd "${workdir}"
		(cd "${root_dir}" && sh scripts/template.sh files) >files.txt
		tar -C "${root_dir}" -cf fixture.tar -T files.txt
		tar -xf fixture.tar
		rm fixture.tar files.txt
		cat >.github/workflows/unsafe.yml <<'EOF'
name: unsafe
on:
  pull_request:
permissions:
  contents: read
jobs:
  unsafe:
    runs-on: ubuntu-24.04
    steps:
      - run: |
          echo "${{ github.event.pull_request.title }}"
EOF
		if check_workflow_metadata_policy >${TMPDIR}/template-workflow-metadata-policy.txt 2>&1; then
			fail 'workflow metadata policy should reject unsafe run interpolation'
		fi
		grep -q 'untrusted github.event metadata must not be interpolated directly into run steps' ${TMPDIR}/template-workflow-metadata-policy.txt || fail 'workflow metadata policy should report unsafe metadata interpolation'
	)
	rm -rf "${workdir}"
}

test_local_state_is_not_packaged() {
	mkdir -p config/infra src
	: >config/infra/terraform.tfvars
	: >src/app
	sh ./scripts/template.sh files >${TMPDIR}/template-files-local-state.txt
	! grep -qx 'config/infra/terraform.tfvars' ${TMPDIR}/template-files-local-state.txt || fail 'template files should exclude local Terraform variable files'
	! grep -qx 'src/app' ${TMPDIR}/template-files-local-state.txt || fail 'template files should exclude the generated example binary'
	rm -f config/infra/terraform.tfvars src/app
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
		(cd "${root_dir}" && sh scripts/template.sh files) >files.txt
		tar -C "${root_dir}" -cf fixture.tar -T files.txt
		tar -xf fixture.tar
		rm fixture.tar files.txt
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
			-e "s#^DEV_SCAN_ZIZMOR_IMAGE=.*#DEV_SCAN_ZIZMOR_IMAGE='${DEV_SCAN_ZIZMOR_IMAGE_LOCK}'#" \
			-e "s#^DEV_SCAN_TRIVY_IMAGE=.*#DEV_SCAN_TRIVY_IMAGE='${DEV_SCAN_TRIVY_IMAGE_LOCK}'#" \
			-e "s#^DEV_SCAN_SYFT_IMAGE=.*#DEV_SCAN_SYFT_IMAGE='${DEV_SCAN_SYFT_IMAGE_LOCK}'#" \
			-e "s#^DEV_SCAN_GRYPE_IMAGE=.*#DEV_SCAN_GRYPE_IMAGE='${DEV_SCAN_GRYPE_IMAGE_LOCK}'#" \
			-e "s#^DEV_RENOVATE_IMAGE=.*#DEV_RENOVATE_IMAGE='${DEV_RENOVATE_IMAGE_LOCK}'#" \
			config/project.cfg >config/project.cfg.test
		PATH="${workdir}/bin:${PATH}" sh ./scripts/update.sh config/project.cfg.test >${TMPDIR}/template-update-optional-k8s.txt
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
		(cd "${root_dir}" && sh scripts/template.sh files) >files.txt
		tar -C "${root_dir}" -cf fixture.tar -T files.txt
		tar -xf fixture.tar
		rm fixture.tar files.txt
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
		PATH="${workdir}/fake-bin:${PATH}" sh ./scripts/scan.sh config/project.cfg.test >${TMPDIR}/template-scan-optional-k8s.txt
		grep -q 'Optional Kubernetes scaffold not configured; skipping Helm render and manifest scan' ${TMPDIR}/template-scan-optional-k8s.txt || fail 'scan should report when it skips the optional Kubernetes scaffold'
		grep -q 'No rendered Kubernetes manifests available; skipping Trivy config scan' ${TMPDIR}/template-scan-optional-k8s.txt || fail 'scan should skip the Kubernetes Trivy pass when nothing was rendered'
	)
	rm -rf "${workdir}"
}

test_k8s_shell_inputs_are_not_executed() {
	workdir=$(mktemp -d)
	root_dir=$(pwd)

	(
		cd "${workdir}"
		(cd "${root_dir}" && sh scripts/template.sh files) >files.txt
		tar -C "${root_dir}" -cf fixture.tar -T files.txt
		tar -xf fixture.tar
		rm fixture.tar files.txt
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
		cat >${TMPDIR}/template-k8s-shell-values.yaml <<'EOF'
container:
  port: 8080
EOF
		cat >config/project.cfg.test <<'EOF'
. ./config/project.cfg
DEV_K8S_HELM_IMAGE='fake-helm'
K8S_NAME_OVERRIDE="safe; touch ${TMPDIR}/template-k8s-shell-proof #"
K8S_VALUES_FILE="${TMPDIR}/template-k8s-shell-values.yaml"
EOF
		rm -f ${TMPDIR}/template-k8s-shell-proof
		PATH="${workdir}/fake-bin:${PATH}" sh ./scripts/k8s.sh config/project.cfg.test >${TMPDIR}/template-k8s-shell-safe.txt
		[ ! -f ${TMPDIR}/template-k8s-shell-proof ] || fail 'k8s should not execute shell metacharacters from project config values'
		grep -F -- "nameOverride=safe; touch ${TMPDIR}/template-k8s-shell-proof #" .tmp/k8s/rendered/kc-secure-template.yaml || fail 'k8s should pass unsafe-looking overrides as literal Helm arguments'
	)
	rm -rf "${workdir}"
}

test_k8s_render_file_scan_path() {
	workdir=$(mktemp -d)
	root_dir=$(pwd)

	(
		cd "${workdir}"
		(cd "${root_dir}" && sh scripts/template.sh files) >files.txt
		tar -C "${root_dir}" -cf fixture.tar -T files.txt
		tar -xf fixture.tar
		rm fixture.tar files.txt
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
			sh ./scripts/scan.sh config/project.cfg.test >${TMPDIR}/template-scan-render-dir.txt
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
			sh ./scripts/scan.sh config/project.cfg.absolute >${TMPDIR}/template-scan-absolute-render-dir.txt
		[ -f "${absolute_render_dir}/derived-app.yaml" ] || fail 'scan should rely on the manifest path rendered by k8s.sh when K8S_RELEASE_NAME is omitted'
		grep -F -- '/tmp/k8s-scan-manifest.' docker.log | grep -F -- 'derived-app.yaml' >/dev/null || fail 'scan should stage the derived release-name manifest for Trivy'
		! grep -F -- "${absolute_render_dir}" docker.log >/dev/null 2>&1 || fail 'scan should not pass an absolute host render directory directly into the scanner container'
	)
	rm -rf "${workdir}"
}

test_k8s_test_local_uses_kubeconfig_and_server_dry_run() {
	workdir=$(mktemp -d)
	root_dir=$(pwd)

	(
		cd "${workdir}"
		(cd "${root_dir}" && sh scripts/template.sh files) >files.txt
		tar -C "${root_dir}" -cf fixture.tar -T files.txt
		tar -xf fixture.tar
		rm fixture.tar files.txt
		mkdir -p fake-bin fake-kubeconfig config/k8s .tmp/k8s/rendered scripts
		cat >fake-bin/docker <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>docker.log

case "$1" in
run)
	[ "${FAKE_KUBECTL_FAIL:-false}" != true ] || exit 42
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
			sh ./scripts/k8s-test-local.sh config/project.cfg >${TMPDIR}/template-k8s-test-local.txt
		! grep -F -- ' build ' docker.log >/dev/null 2>&1 || fail 'k8s-test-local should not build a repo-controlled kubectl image'
		grep -F -- 'bitnami/kubectl:latest' docker.log || fail 'k8s-test-local should run the configured kubectl image'
		grep -F -- '--dry-run=server' docker.log || fail 'k8s-test-local should use kubectl server-side dry-run'
		grep -F -- "--context kind-local" docker.log || fail 'k8s-test-local should pass the configured Kubernetes context'
		! grep -F -- "${workdir}/fake-kubeconfig:/tmp/k8s-test-kubeconfig:ro" docker.log >/dev/null 2>&1 || fail 'k8s-test-local should not mount the original kubeconfig directory'
		grep -F -- '/kubeconfig.' docker.log || fail 'k8s-test-local should mount a staged kubeconfig directory'
		grep -F -- '/tmp/k8s-test-local-manifest.' docker.log | grep -F -- 'kc-secure-template.yaml' >/dev/null || fail 'k8s-test-local should stage the rendered manifest into the mounted temp directory'
		grep -q 'Resources checked by server-side dry-run: 1' ${TMPDIR}/template-k8s-test-local.txt || fail 'k8s-test-local should report the dry-run resource count'
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
			sh ./scripts/k8s-test-local.sh config/project.cfg.absolute >${TMPDIR}/template-k8s-test-local-absolute.txt
		[ -f "${external_render_dir}/derived-app.yaml" ] || fail 'k8s-test-local should use the manifest path rendered by k8s.sh when K8S_RELEASE_NAME is omitted'
		grep -F -- '/tmp/k8s-test-local-manifest.' docker.log | grep -F -- 'derived-app.yaml' >/dev/null || fail 'k8s-test-local should stage the derived release-name manifest for kubectl'
		! grep -F -- "${external_render_dir}" docker.log >/dev/null 2>&1 || fail 'k8s-test-local should not pass an absolute host render directory directly into the kubectl container'
		if PATH="${workdir}/fake-bin:${PATH}" FAKE_KUBECTL_FAIL=true \
			K8S_TEST_LOCAL_KUBECONFIG="${workdir}/fake-kubeconfig/config" \
			sh ./scripts/k8s-test-local.sh config/project.cfg >"${TMPDIR}/failed-dry-run.txt" 2>&1; then
			fail 'kubectl failure must fail the local validation command'
		fi
	)
	rm -rf "${workdir}"
}

test_infra_preserves_lock_and_forwards_token() {
	workdir=$(mktemp -d)
	root_dir=$(pwd)
	(
		cd "${workdir}"
		(cd "${root_dir}" && sh scripts/template.sh files) >files.txt
		tar -C "${root_dir}" -cf fixture.tar -T files.txt
		tar -xf fixture.tar
		mkdir -p fake-bin
		cat >fake-bin/docker <<'EOF'
#!/bin/sh
# Record argument names only; no real credential is used by this fixture.
printf '%s\n' "$*" >>docker.log
EOF
		chmod +x fake-bin/docker
		PATH="${workdir}/fake-bin:${PATH}" GITHUB_TOKEN=fixture-token \
			sh scripts/infra.sh >infra.log
		grep -q -- '-e GITHUB_TOKEN' docker.log || fail 'infra must forward the token by environment variable name'
		! grep -q 'fixture-token' docker.log || fail 'infra must not place token values in command arguments'
		! grep -q 'rm -rf .*terraform.lock.hcl' docker.log || fail 'infra must preserve provider checksums'
		! grep -q 'apply -input' docker.log || fail 'infra must not apply by default'
		: >docker.log
		PATH="${workdir}/fake-bin:${PATH}" INFRA_UPDATE_LOCK=true \
			sh scripts/infra.sh >infra.log
		grep -q 'providers lock -platform=linux_amd64 -platform=linux_arm64' docker.log || fail 'explicit lock maintenance must cover both container architectures'
		if PATH="${workdir}/fake-bin:${PATH}" INFRA_UPDATE_LOCK=true APPLY=true \
			sh scripts/infra.sh >infra.log 2>&1; then
			fail 'provider upgrades and apply must require separate runs'
		fi
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
template | smoke | _regression)
	# All destructive fixtures and generated outputs live in a disposable copy.
	# In particular, never truncate a developer's terraform.tfvars or delete their .tmp.
	suite_dir=$(mktemp -d)
	trap 'rm -rf "${suite_dir}"' EXIT
	trap 'exit 1' HUP INT TERM
	list_template_files >"${suite_dir}/files.txt"
	mkdir "${suite_dir}/repo" "${suite_dir}/tmp"
	tar -cf "${suite_dir}/repo.tar" -T "${suite_dir}/files.txt"
	tar -xf "${suite_dir}/repo.tar" -C "${suite_dir}/repo"
	cd "${suite_dir}/repo"
	export TMPDIR="${suite_dir}/tmp"
	if [ "${mode}" = _regression ]; then
		. ./scripts/workflow-policy.sh
		. ./config/lockfile.cfg
		test_workflow_pull_request_target_is_rejected
		test_workflow_issue_comment_is_rejected
		test_workflow_run_is_rejected_without_policy_exception
		test_workflow_missing_permissions_is_rejected
		test_workflow_metadata_interpolation_is_rejected
		test_ci_change_detection_rules
		test_ci_change_detection_output_contract
		test_ci_change_detection_git_history
		test_local_state_is_not_packaged
		test_infra_preserves_lock_and_forwards_token
		test_optional_k8s_update_compat
		test_optional_k8s_scan_skip
		test_k8s_shell_inputs_are_not_executed
		test_k8s_render_file_scan_path
		test_k8s_test_local_uses_kubeconfig_and_server_dry_run
		exit 0
	fi
	# Exercise the shipped build/test code unchanged with the current image locks.
	make build
	make test TEST_MODE=src
	. ./config/project.cfg
	case "${PROJECT_NAME}" in
	*-dev) regression_image="${PROJECT_NAME%-dev}-example:local" ;;
	*) regression_image="${PROJECT_NAME}-example:local" ;;
	esac
	# Shell regression fixtures run nonroot without Docker socket or network access.
	docker run --rm --user "$(id -u):$(id -g)" --network=none \
		--cap-drop=ALL --security-opt=no-new-privileges:true \
		-v "$(pwd):/workspace:ro" -w /workspace \
		"${regression_image}" sh scripts/test.sh _regression
	GITHUB_TOKEN= make infra APPLY=false INFRA_UPDATE_LOCK=false
	PROJECT_CFG_FILE=config/project.cfg make k8s >${TMPDIR}/template-k8s.txt
	[ -f .tmp/k8s/rendered/kc-secure-template.yaml ] || fail 'make k8s should write a rendered Kubernetes manifest'
	grep -q 'app.kubernetes.io/name: kc-secure-template' .tmp/k8s/rendered/kc-secure-template.yaml || fail 'make k8s should derive the chart app name from PROJECT_NAME by default'
	find .tmp/k8s/package -maxdepth 1 -type f -name '*.tgz' | grep -q . || fail 'make k8s should package the bundled Helm chart'
	cat >${TMPDIR}/template-k8s-values.yaml <<'EOF'
container:
  port: 8080
service:
  port: 80
EOF
	PROJECT_CFG_FILE=config/project.cfg K8S_VALUES_FILE=${TMPDIR}/template-k8s-values.yaml make k8s >${TMPDIR}/template-k8s-custom-port.txt
	grep -q 'containerPort: 8080' .tmp/k8s/rendered/kc-secure-template.yaml || fail 'make k8s should keep the container port independent from the Service port'
	grep -q 'port: 80' .tmp/k8s/rendered/kc-secure-template.yaml || fail 'make k8s should allow the Service port to differ from the container port'
	external_render_dir=$(mktemp -d)
	external_package_dir=$(mktemp -d)
	cat >${TMPDIR}/template-k8s-external-values.yaml <<'EOF'
container:
  port: 9090
EOF
	PROJECT_CFG_FILE=config/project.cfg \
		K8S_VALUES_FILE=${TMPDIR}/template-k8s-external-values.yaml \
		K8S_RENDER_DIR="${external_render_dir}" \
		K8S_PACKAGE_DIR="${external_package_dir}" \
		make k8s >${TMPDIR}/template-k8s-external-paths.txt
	[ -f "${external_render_dir}/kc-secure-template.yaml" ] || fail 'make k8s should write rendered manifests to an external K8S_RENDER_DIR'
	grep -q 'containerPort: 9090' "${external_render_dir}/kc-secure-template.yaml" || fail 'make k8s should apply an external K8S_VALUES_FILE override'
	find "${external_package_dir}" -maxdepth 1 -type f -name '*.tgz' | grep -q . || fail 'make k8s should package charts into an external K8S_PACKAGE_DIR'
	rm -rf "${external_render_dir}" "${external_package_dir}"
	sed \
		-e "s/^PROJECT_NAME='kc-secure-template'/PROJECT_NAME='My_App'/" \
		-e "s#^PROJECT_IMAGE=.*#PROJECT_IMAGE='ghcr.io/example/my-app:local'#" \
		config/project.cfg >${TMPDIR}/template-k8s-sanitized.cfg
	sh ./scripts/k8s.sh ${TMPDIR}/template-k8s-sanitized.cfg >${TMPDIR}/template-k8s-sanitized.txt
	[ -f .tmp/k8s/rendered/my-app.yaml ] || fail 'make k8s should sanitize the default release name for non-DNS-safe project names'
	grep -q 'app.kubernetes.io/instance: my-app' .tmp/k8s/rendered/my-app.yaml || fail 'make k8s should render a DNS-safe default release label for non-DNS-safe project names'
	grep -q 'app.kubernetes.io/name: my-app' .tmp/k8s/rendered/my-app.yaml || fail 'make k8s should sanitize the default chart app name for non-DNS-safe project names'
	cat >${TMPDIR}/template-k8s-digest.cfg <<'EOF'
. ./config/project.cfg
K8S_IMAGE_REPOSITORY='ghcr.io/example/app'
K8S_IMAGE_TAG='sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
EOF
	sh ./scripts/k8s.sh ${TMPDIR}/template-k8s-digest.cfg >${TMPDIR}/template-k8s-digest.txt
	grep -q 'image: "ghcr.io/example/app@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"' .tmp/k8s/rendered/kc-secure-template.yaml || fail 'make k8s should render digest-pinned images with @sha256 references'
	cat >config/project.cfg.derived <<'EOF'
. ./config/project.cfg
PROJECT_NAME='Derived_App'
PROJECT_IMAGE='registry.example.com:5000/derived-app:local'
EOF
	sh ./scripts/k8s.sh config/project.cfg.derived
	grep -q 'image: "registry.example.com:5000/derived-app:local"' .tmp/k8s/rendered/derived-app.yaml || fail 'Helm should use layered project image defaults'
	tar -xOzf .tmp/k8s/package/derived-app-0.1.0.tgz derived-app/values.yaml | grep -q 'repository: registry.example.com:5000/derived-app' || fail 'packaged chart should inherit the project image'
	ENABLE_SBOM=false ENABLE_GRYPE=false make dist
	cp dist/kc-secure-repo-template.tar.gz "${TMPDIR}/first.tar.gz"
	ENABLE_SBOM=false ENABLE_GRYPE=false make dist
	cmp "${TMPDIR}/first.tar.gz" dist/kc-secure-repo-template.tar.gz || fail 'release archive should be reproducible'
	sha256sum -c dist/SHA256SUMS
	sha256sum -c dist/ARCHIVE-SHA256SUMS
	printf '\n==> Template regressions and copied-repository smoke checks passed\n'
	;;

*)
	fail "unknown mode: ${mode}"
	;;
esac
