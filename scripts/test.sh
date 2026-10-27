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

# CI opts out of the nested src run with TEMPLATE_SKIP_SRC_TESTS=true because the
# separate test-code job already covers it. Only the exact value "true" skips;
# anything else (unset, false, TRUE, 1) keeps the full local/release behavior.
template_skip_src_tests() {
	[ "${TEMPLATE_SKIP_SRC_TESTS:-}" = true ]
}

test_template_skip_src_tests_flag() {
	(
		unset TEMPLATE_SKIP_SRC_TESTS
		! template_skip_src_tests || fail 'unset flag should not skip src tests'
	)
	for value in false TRUE 1 yes ''; do
		(
			TEMPLATE_SKIP_SRC_TESTS=${value}
			! template_skip_src_tests || fail "flag value '${value}' should not skip src tests"
		)
	done
	(
		TEMPLATE_SKIP_SRC_TESTS=true
		template_skip_src_tests || fail 'flag value true should skip src tests'
	)
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
scripts/test.sh
config/project.cfg
config/lockfile.cfg
.github/workflows/test.yml' true true
	assert_ci_change_detection 'agent skill prose' '.claude/skills/x/SKILL.md' false false
	assert_ci_change_detection 'infra subtree AGENTS.md' 'config/infra/AGENTS.md' false false
	assert_ci_change_detection 'k8s subtree CLAUDE.md' 'config/k8s/CLAUDE.md' false false
	assert_ci_change_detection 'repo-only script k8s' 'scripts/k8s.sh' false true
	assert_ci_change_detection 'repo-only script scan' 'scripts/scan.sh' false true
	assert_ci_change_detection 'repo-only script commit policy' 'scripts/commit-policy.sh' false true
	assert_ci_change_detection 'repo-only script agent policy' 'scripts/agent-policy.sh' false true
	assert_ci_change_detection 'non-test workflow' '.github/workflows/scan.yml' false true
	assert_ci_change_detection 'github config' '.github/renovate.json' false true
	assert_ci_change_detection 'gitignore' '.gitignore' false true
	assert_ci_change_detection 'agent non-Markdown file' '.agents/skills/x/agents/openai.yaml' false true
	assert_ci_change_detection 'unlisted new script' 'scripts/new-unlisted.sh' true true
	assert_ci_change_detection 'mixed repo-only script and source' 'scripts/k8s.sh
src/cmd/app/main.go' true true
	assert_ci_change_detection 'mixed prose and repo-only script' 'README.md
scripts/scan.sh' false true
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
	grep -Fq "if: github.event_name == 'pull_request'" .github/workflows/test.yml || fail 'change detection should run only for pull requests'
	grep -Fq "if: \${{ github.event_name == 'pull_request' && needs.detect-test-changes.result != 'success' }}" .github/workflows/test.yml || fail 'main pushes should not fail when change detection is skipped'
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

# Write one workflow fixture from stdin into an empty directory and require the
# real pinned zizmor image to fail it with the named audit. Uses Docker, so it
# runs in template mode on the host, not inside the network-less regression
# container.
assert_zizmor_rejects() {
	fixture_dir=$(mktemp -d)
	mkdir -p "${fixture_dir}/.github/workflows"
	cat >"${fixture_dir}/.github/workflows/unsafe.yml"
	if run_workflow_security_scan "${DEV_SCAN_ZIZMOR_IMAGE_LOCK}" "${fixture_dir}" >${TMPDIR}/template-zizmor.txt 2>&1; then
		fail "zizmor should reject $1"
	fi
	grep -q "$2" ${TMPDIR}/template-zizmor.txt || fail "zizmor should report $2 for $1"
	rm -rf "${fixture_dir}"
}

# These cases were previously enforced by awk checks in scripts/workflow-policy.sh;
# zizmor now owns them, so keep regression coverage against the real scanner.
test_zizmor_rejects_unsafe_workflows() {
	# Control: a minimal safe workflow passes, so the failures below come from
	# the unsafe construct rather than from the fixture setup.
	fixture_dir=$(mktemp -d)
	mkdir -p "${fixture_dir}/.github/workflows"
	cat >"${fixture_dir}/.github/workflows/safe.yml" <<'EOF'
name: safe
on:
  pull_request:
permissions: {}
jobs:
  safe:
    runs-on: ubuntu-24.04
    steps:
      - run: echo safe
EOF
	run_workflow_security_scan "${DEV_SCAN_ZIZMOR_IMAGE_LOCK}" "${fixture_dir}" >${TMPDIR}/template-zizmor-safe.txt 2>&1 || fail 'zizmor should accept the safe control workflow'
	rm -rf "${fixture_dir}"

	assert_zizmor_rejects 'tag-pinned actions' 'unpinned-uses' <<'EOF'
name: unsafe
on:
  pull_request:
permissions: {}
jobs:
  unsafe:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false
EOF
	assert_zizmor_rejects 'short-SHA action pins' 'unpinned-uses' <<'EOF'
name: unsafe
on:
  pull_request:
permissions: {}
jobs:
  unsafe:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@3d3c42e # v7.0.1
        with:
          persist-credentials: false
EOF
	assert_zizmor_rejects 'pull_request_target' 'dangerous-triggers' <<'EOF'
name: unsafe
on:
  pull_request_target:
permissions: {}
jobs:
  unsafe:
    runs-on: ubuntu-24.04
    steps:
      - run: echo unsafe
EOF
	assert_zizmor_rejects 'workflow_run' 'dangerous-triggers' <<'EOF'
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
	assert_zizmor_rejects 'untrusted metadata in run steps' 'template-injection' <<'EOF'
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
          echo "${{ github.head_ref }}"
EOF
	# zizmor only reports missing permissions per job, so a workflow with
	# job-level permissions but no top-level block passes it. The stricter
	# top-level rule stays in check_workflow_permissions_policy; this case
	# pins zizmor's overlapping coverage.
	assert_zizmor_rejects 'missing permissions' 'excessive-permissions' <<'EOF'
name: unsafe
on:
  pull_request:
jobs:
  unsafe:
    runs-on: ubuntu-24.04
    steps:
      - run: echo unsafe
EOF
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

# zizmor honors inline "# zizmor: ignore[...]" comments and has no flag to turn
# them off, so the workflow policy rejects them to keep its audits unbypassable.
# The check only reads workflow and action files, so a minimal fixture is enough.
test_workflow_zizmor_ignore_is_rejected() {
	workdir=$(mktemp -d)

	(
		cd "${workdir}"
		mkdir -p .github/workflows
		cat >.github/workflows/unsafe.yml <<'EOF'
name: unsafe
on:
  pull_request_target: # zizmor: ignore[dangerous-triggers]
permissions:
  contents: read
jobs:
  unsafe:
    runs-on: ubuntu-24.04
    steps:
      - run: echo unsafe
EOF
		if check_workflow_scanner_suppressions >${TMPDIR}/template-workflow-suppressions.txt 2>&1; then
			fail 'workflow policy should reject inline zizmor ignores'
		fi
		grep -q 'inline zizmor ignore is not allowed' ${TMPDIR}/template-workflow-suppressions.txt || fail 'workflow policy should report inline zizmor ignores'
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

test_local_state_is_not_packaged() {
	mkdir -p config/infra src
	: >config/infra/terraform.tfvars
	: >src/app
	# Exercise the packaging code with local credentials in a disposable tree.
	mkdir -p src/nested
	for secret in src/.env src/nested/.env.production config/.env.local; do
		printf '%s\n' 'PACKAGING_TEST_SECRET=placeholder-only' >"${secret}"
	done
	printf '%s\n' 'APP_TOKEN=replace-me' >src/nested/.env.example
	sh ./scripts/template.sh files >${TMPDIR}/template-files-local-state.txt
	! grep -qx 'config/infra/terraform.tfvars' ${TMPDIR}/template-files-local-state.txt || fail 'template files should exclude local Terraform variable files'
	! grep -qx 'src/app' ${TMPDIR}/template-files-local-state.txt || fail 'template files should exclude the generated example binary'
	sh ./scripts/template.sh release
	tar -tzf dist/kc-secure-repo-template.tar.gz >"${TMPDIR}/template-archive-local-state.txt"
	for listing in "${TMPDIR}/template-files-local-state.txt" "${TMPDIR}/template-archive-local-state.txt"; do
		for secret in src/.env src/nested/.env.production config/.env.local; do
			! grep -Fxq "${secret}" "${listing}" || fail "packaging should exclude ${secret}"
		done
		grep -Fxq 'src/nested/.env.example' "${listing}" || fail 'packaging should preserve environment examples'
	done
	rm -f config/infra/terraform.tfvars src/app
}

# Rewrite image selectors to their committed digest locks so update.sh can
# resolve every image offline (digest-pinned selectors skip registry lookups).
pin_selectors_to_locks() {
	sed \
		-e "s#^DEV_BASE_IMAGE=.*#DEV_BASE_IMAGE='${DEV_BASE_IMAGE_LOCK}'#" \
		-e "s#^DEV_GO_IMAGE=.*#DEV_GO_IMAGE='${DEV_GO_IMAGE_LOCK}'#" \
		-e "s#^DEV_TERRAFORM_IMAGE=.*#DEV_TERRAFORM_IMAGE='${DEV_TERRAFORM_IMAGE_LOCK}'#" \
		-e "s#^DEV_DISTROLESS_STATIC_IMAGE=.*#DEV_DISTROLESS_STATIC_IMAGE='${DEV_DISTROLESS_STATIC_IMAGE_LOCK}'#" \
		-e "s#^DEV_K8S_HELM_IMAGE=.*#DEV_K8S_HELM_IMAGE='${DEV_K8S_HELM_IMAGE_LOCK}'#" \
		-e "s#^DEV_K8S_KUBECTL_IMAGE=.*#DEV_K8S_KUBECTL_IMAGE='${DEV_K8S_KUBECTL_IMAGE_LOCK}'#" \
		-e "s#^DEV_SCAN_BETTERLEAKS_IMAGE=.*#DEV_SCAN_BETTERLEAKS_IMAGE='${DEV_SCAN_BETTERLEAKS_IMAGE_LOCK}'#" \
		-e "s#^DEV_SCAN_ACTIONLINT_IMAGE=.*#DEV_SCAN_ACTIONLINT_IMAGE='${DEV_SCAN_ACTIONLINT_IMAGE_LOCK}'#" \
		-e "s#^DEV_SCAN_ZIZMOR_IMAGE=.*#DEV_SCAN_ZIZMOR_IMAGE='${DEV_SCAN_ZIZMOR_IMAGE_LOCK}'#" \
		-e "s#^DEV_SCAN_TRIVY_IMAGE=.*#DEV_SCAN_TRIVY_IMAGE='${DEV_SCAN_TRIVY_IMAGE_LOCK}'#" \
		-e "s#^DEV_SCAN_SYFT_IMAGE=.*#DEV_SCAN_SYFT_IMAGE='${DEV_SCAN_SYFT_IMAGE_LOCK}'#" \
		-e "s#^DEV_SCAN_GRYPE_IMAGE=.*#DEV_SCAN_GRYPE_IMAGE='${DEV_SCAN_GRYPE_IMAGE_LOCK}'#" \
		-e "s#^DEV_RENOVATE_IMAGE=.*#DEV_RENOVATE_IMAGE='${DEV_RENOVATE_IMAGE_LOCK}'#"
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
			config/project.cfg | pin_selectors_to_locks >config/project.cfg.test
		PATH="${workdir}/bin:${PATH}" sh ./scripts/update.sh config/project.cfg.test >${TMPDIR}/template-update-optional-k8s.txt
		grep -q "^DEV_K8S_HELM_IMAGE_LOCK=''\$" config/lockfile.cfg || fail 'update should keep an empty K8S Helm lock when the optional setting is absent'
		grep -q "^DEV_K8S_KUBECTL_IMAGE_LOCK=''\$" config/lockfile.cfg || fail 'update should keep an empty K8S kubectl lock when the optional setting is absent'
	)
	rm -rf "${workdir}"
}

test_update_package_snapshot_refresh() {
	workdir=$(mktemp -d)
	root_dir=$(pwd)

	# Offline fixture: curl must not run, and date returns a fixed UTC day so
	# the refreshed Debian snapshot value is deterministic.
	mkdir -p "${workdir}/bin"
	cat >"${workdir}/bin/curl" <<'EOF'
#!/bin/sh
printf 'curl should not be called in package snapshot refresh test\n' >&2
exit 1
EOF
	cat >"${workdir}/bin/date" <<'EOF'
#!/bin/sh
[ "$*" = '-u +%Y%m%dT000000Z' ] || { printf 'unexpected date arguments: %s\n' "$*" >&2; exit 1; }
printf '%s\n' '20991231T000000Z'
EOF
	chmod +x "${workdir}/bin/curl" "${workdir}/bin/date"

	(
		cd "${workdir}"
		(cd "${root_dir}" && sh scripts/template.sh files) >files.txt
		tar -C "${root_dir}" -cf fixture.tar -T files.txt
		tar -xf fixture.tar
		rm fixture.tar files.txt
		pin_selectors_to_locks <config/project.cfg >config/project.cfg.test
		previous_snapshot=$(sed -n "s/^DEV_PACKAGE_SNAPSHOT_LOCK='\(.*\)'\$/\1/p" config/lockfile.cfg)

		# Plain make update keeps the reviewed snapshot unchanged.
		PATH="${workdir}/bin:${PATH}" sh ./scripts/update.sh config/project.cfg.test >/dev/null
		grep -qx "DEV_PACKAGE_SNAPSHOT_LOCK='${previous_snapshot}'" config/lockfile.cfg || fail 'update should keep the Debian package snapshot without the refresh flag'

		# The opt-in flag moves the snapshot to the current UTC day.
		PATH="${workdir}/bin:${PATH}" sh ./scripts/update.sh config/project.cfg.test --refresh-package-snapshot >/dev/null
		grep -qx "DEV_PACKAGE_SNAPSHOT_LOCK='20991231T000000Z'" config/lockfile.cfg || fail 'update --refresh-package-snapshot should lock the current UTC day'

		# Unknown options fail loudly instead of being ignored.
		! PATH="${workdir}/bin:${PATH}" sh ./scripts/update.sh config/project.cfg.test --refresh >/dev/null 2>&1 || fail 'update should reject unknown options'
	)
	rm -rf "${workdir}"
}

# The opt-in image vulnerability scan stays off by default, and when on it builds
# the target, scans a saved tarball with Trivy, and always removes the tarball.
test_scan_image_vulns() {
	workdir=$(mktemp -d)
	root_dir=$(pwd)

	(
		cd "${workdir}"
		(cd "${root_dir}" && sh scripts/template.sh files) >files.txt
		tar -C "${root_dir}" -cf fixture.tar -T files.txt
		tar -xf fixture.tar
		rm fixture.tar files.txt
		rm -rf config/k8s
		mkdir -p fake-bin scan-tmp
		# `docker save -o FILE` creates the file; a Trivy `image` run fails when asked to.
		cat >fake-bin/docker <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>docker.log
if [ "$1" = save ]; then
	: >"$3"
fi
case " $* " in
*' image --input '*) [ -z "${FAKE_TRIVY_IMAGE_FAIL:-}" ] || exit 1 ;;
esac
exit 0
EOF
		chmod +x fake-bin/docker
		sed -e "/^DEV_K8S_HELM_IMAGE=/d" config/project.cfg >config/project.cfg.test
		. ./config/lockfile.cfg

		# On (off-by-default is covered by test_scan_scanner_arguments): the runtime
		# target is built with the pinned locks and scanned by Trivy.
		printf '%s\n' 'PROJECT_SCAN_IMAGE_VULNS=true' >>config/project.cfg.test
		PATH="${workdir}/fake-bin:${PATH}" DOCKER_TMPDIR="${workdir}/scan-tmp" sh ./scripts/scan.sh config/project.cfg.test >${TMPDIR}/template-scan-image-on.txt
		grep -F -- '--target runtime' docker.log | grep -Fq -- "RUNTIME_BASE_IMAGE=${DEV_DISTROLESS_STATIC_IMAGE_LOCK}" || fail 'scan should build the runtime target with the pinned distroless lock'
		trivy_line=$(grep -F -- ' image --input ' docker.log) || fail 'scan should run Trivy against the saved image tarball'
		printf '%s\n' "${trivy_line}" | grep -Fq -- "${DEV_SCAN_TRIVY_IMAGE_LOCK}" || fail 'image scan should use the digest-pinned Trivy image'
		printf '%s\n' "${trivy_line}" | grep -Fq -- '--exit-code 1' || fail 'image scan should fail on findings'
		printf '%s\n' "${trivy_line}" | grep -Fq -- '--severity HIGH,CRITICAL' || fail 'image scan should gate on HIGH and CRITICAL findings'
		printf '%s\n' "${trivy_line}" | grep -Fq -- ':/scan/image.tar:ro' || fail 'image scan should mount only the tarball, read-only'
		printf '%s\n' "${trivy_line}" | grep -Fq -- '--ignorefile /scan/.trivyignore' || fail 'image scan should read the reviewed ignore file'
		grep -Fq 'image rm kc-secure-template-vuln-scan:local' docker.log || fail 'scan should remove the scan image afterwards'
		[ -z "$(find scan-tmp -name 'scan-image.*')" ] || fail 'scan should delete the image tarball after a passing scan'

		# Trivy failing fails the scan and still deletes the tarball.
		rm -f docker.log
		if PATH="${workdir}/fake-bin:${PATH}" DOCKER_TMPDIR="${workdir}/scan-tmp" FAKE_TRIVY_IMAGE_FAIL=1 sh ./scripts/scan.sh config/project.cfg.test >${TMPDIR}/template-scan-image-fail.txt 2>&1; then
			fail 'scan should fail when the image vulnerability scan fails'
		fi
		# The failure must come from Trivy itself, after the tarball was saved.
		grep -Fq 'save -o ' docker.log || fail 'failing scan should have saved the image tarball'
		tail -n 2 docker.log | grep -Fq ' image --input ' || fail 'failing scan should stop at the Trivy image scan'
		[ -z "$(find scan-tmp -name 'scan-image.*')" ] || fail 'scan should delete the image tarball after a failing scan'
		# Unknown toggle values are rejected instead of silently skipping the scan.
		printf '%s\n' 'PROJECT_SCAN_IMAGE_VULNS=TRUE' >>config/project.cfg.test
		if PATH="${workdir}/fake-bin:${PATH}" DOCKER_TMPDIR="${workdir}/scan-tmp" sh ./scripts/scan.sh config/project.cfg.test >${TMPDIR}/template-scan-image-bad.txt 2>&1; then
			fail 'scan should reject a PROJECT_SCAN_IMAGE_VULNS value other than true or false'
		fi
		grep -Fq 'PROJECT_SCAN_IMAGE_VULNS must be true or false' ${TMPDIR}/template-scan-image-bad.txt || fail 'scan should name the invalid toggle'
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

# Record every scanner container invocation so the argument contract (pinned
# image, read-only mounts, no network where the scanner needs none) is checked
# without pulling real images.
test_scan_scanner_arguments() {
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
printf '%s\n' "$*" >>docker.log
exit 0
EOF
		chmod +x fake-bin/docker
		sed -e "/^DEV_K8S_HELM_IMAGE=/d" config/project.cfg >config/project.cfg.test
		. ./config/lockfile.cfg

		# Without Git metadata the secret scan falls back to a plain directory scan.
		PATH="${workdir}/fake-bin:${PATH}" sh ./scripts/scan.sh config/project.cfg.test >${TMPDIR}/template-scan-args.txt
		secret_line=$(grep -F -- "${DEV_SCAN_BETTERLEAKS_IMAGE_LOCK}" docker.log) || fail 'scan should run the digest-pinned betterleaks image'
		printf '%s\n' "${secret_line}" | grep -Eq "${DEV_SCAN_BETTERLEAKS_IMAGE_LOCK} dir /repo( |$)" || fail 'scan should use betterleaks dir without Git metadata'
		printf '%s\n' "${secret_line}" | grep -Fq -- '--network=none' || fail 'secret scan should run without network access'
		printf '%s\n' "${secret_line}" | grep -Fq -- ':/repo:ro' || fail 'secret scan should mount the repository read-only'
		printf '%s\n' "${secret_line}" | grep -Fq -- '--validation' && fail 'secret scan must not validate findings against live APIs'
		# The opt-in image vulnerability scan is off by default and silent when off.
		! grep -Fq 'save ' docker.log || fail 'scan should not save an image when the vulnerability scan is off'
		! grep -Fq ' image --input ' docker.log || fail 'scan should not run the image vulnerability scan by default'
		! grep -Fq 'image vulnerability scan' ${TMPDIR}/template-scan-args.txt || fail 'scan output should be unchanged when the image vulnerability scan is off'

		# Trivy runs offline from its bundled checks, cannot write to the checkout,
		# and covers the Terraform under config/infra as well as Dockerfiles.
		trivy_line=$(grep -F -- "${DEV_SCAN_TRIVY_IMAGE_LOCK} fs " docker.log) || fail 'scan should run the digest-pinned Trivy filesystem scan'
		printf '%s\n' "${trivy_line}" | grep -Fq -- '--network=none' || fail 'Trivy should run without network access'
		printf '%s\n' "${trivy_line}" | grep -Fq -- '--skip-check-update' || fail 'Trivy should use its bundled checks instead of downloading them'
		printf '%s\n' "${trivy_line}" | grep -Fq -- ':/workspace:ro' || fail 'Trivy should mount the repository read-only'
		printf '%s\n' "${trivy_line}" | grep -Fq -- '--misconfig-scanners dockerfile,terraform' || fail 'Trivy should scan Dockerfiles and Terraform'
		printf '%s\n' "${trivy_line}" | grep -Fq -- '--skip-dirs /workspace/config/infra/.terraform' || fail 'Trivy should skip downloaded Terraform providers and modules'
		printf '%s\n' "${trivy_line}" | grep -Fq -- '--ignorefile /workspace/config/.trivyignore' || fail 'Trivy should read the reviewed ignore file'
		# Gitignored caches and scratch copies are not repository content.
		printf '%s\n' "${trivy_line}" | grep -Fq -- '--skip-dirs /workspace/.cache' || fail 'Trivy should skip the local Docker cache'
		printf '%s\n' "${trivy_line}" | grep -Fq -- '--skip-dirs /workspace/.tmp' || fail 'Trivy should skip local scratch files'
		printf '%s\n' "${trivy_line}" | grep -Fq -- '--tf-exclude-downloaded-modules' || fail 'Trivy should exclude downloaded Terraform modules'

		# A checked-in .github/zizmor.yml must not be able to disable the audits
		# that replaced the old awk workflow checks.
		zizmor_line=$(grep -F -- "${DEV_SCAN_ZIZMOR_IMAGE_LOCK}" docker.log) || fail 'scan should run the digest-pinned zizmor image'
		printf '%s\n' "${zizmor_line}" | grep -Fq -- '--no-config' || fail 'zizmor should ignore repository config files'

		# actionlint keeps its bundled shellcheck enabled for workflow run: blocks.
		actionlint_line=$(grep -F -- "${DEV_SCAN_ACTIONLINT_IMAGE_LOCK}" docker.log) || fail 'scan should run the digest-pinned actionlint image'
		printf '%s\n' "${actionlint_line}" | grep -Fq -- '-shellcheck=' && fail 'actionlint should keep shellcheck enabled'
		printf '%s\n' "${actionlint_line}" | grep -Fq -- '--network=none' || fail 'actionlint should run without network access'
		printf '%s\n' "${actionlint_line}" | grep -Fq -- ':/workspace:ro' || fail 'actionlint should mount the repository read-only'

		# With Git metadata the scan covers history through the git subcommand.
		git init -q .
		git -c user.name=fixture -c user.email=fixture@example.invalid commit -q --allow-empty -m "[test] fixture: init"
		: >docker.log
		PATH="${workdir}/fake-bin:${PATH}" sh ./scripts/scan.sh config/project.cfg.test >${TMPDIR}/template-scan-args-git.txt
		grep -F -- "${DEV_SCAN_BETTERLEAKS_IMAGE_LOCK}" docker.log | grep -Eq "${DEV_SCAN_BETTERLEAKS_IMAGE_LOCK} git /repo( |$)" || fail 'scan should use betterleaks git when Git metadata exists'

		# Derived repositories that still only set the legacy gitleaks lock keep a
		# working secret scan instead of failing on an unset variable.
		legacy_image='ghcr.io/example/legacy-secret-scanner@sha256:0000000000000000000000000000000000000000000000000000000000000000'
		sed -e '/^DEV_SCAN_BETTERLEAKS_IMAGE_LOCK=/d' config/lockfile.cfg >config/lockfile.cfg.new
		printf "DEV_SCAN_GITLEAKS_IMAGE_LOCK='%s'\n" "${legacy_image}" >>config/lockfile.cfg.new
		mv config/lockfile.cfg.new config/lockfile.cfg
		: >docker.log
		PATH="${workdir}/fake-bin:${PATH}" sh ./scripts/scan.sh config/project.cfg.test >${TMPDIR}/template-scan-args-legacy.txt
		grep -Fq -- "${legacy_image} git /repo" docker.log || fail 'scan should fall back to the legacy DEV_SCAN_GITLEAKS_IMAGE_LOCK'

		# An unpinned legacy lock is reported under the variable that is set.
		sed -e "s#^DEV_SCAN_GITLEAKS_IMAGE_LOCK=.*#DEV_SCAN_GITLEAKS_IMAGE_LOCK='ghcr.io/example/legacy-secret-scanner:v1'#" config/lockfile.cfg >config/lockfile.cfg.new
		mv config/lockfile.cfg.new config/lockfile.cfg
		if PATH="${workdir}/fake-bin:${PATH}" sh ./scripts/scan.sh config/project.cfg.test >${TMPDIR}/template-scan-args-legacy-unpinned.txt 2>&1; then
			fail 'scan should reject an unpinned legacy secret scanner lock'
		fi
		grep -Fq 'DEV_SCAN_GITLEAKS_IMAGE_LOCK must be pinned by digest' ${TMPDIR}/template-scan-args-legacy-unpinned.txt || fail 'unpinned legacy lock error should name DEV_SCAN_GITLEAKS_IMAGE_LOCK'
	)
	rm -rf "${workdir}"
}

# gcr.io selectors resolve through the gcr.io registry API and keep their tag
# (decision D2), so the lock reads `name:tag@sha256:...`.
test_update_gcr_digest() {
	workdir=$(mktemp -d)
	root_dir=$(pwd)
	digest="sha256:$(printf 'a%.0s' $(seq 1 64))"

	mkdir -p "${workdir}/bin"
	# Fake registry: log every request, answer token and manifest lookups.
	cat >"${workdir}/bin/curl" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>curl.log
case "\$*" in
*gcr.io/v2/token*) printf '{"token":"fake-token"}\n' ;;
*gcr.io/v2/distroless/static-debian13/manifests/nonroot*) printf 'HTTP/2 200\r\ndocker-content-digest: ${digest}\r\n' ;;
*) printf 'unexpected curl call: %s\n' "\$*" >&2; exit 1 ;;
esac
EOF
	chmod +x "${workdir}/bin/curl"

	(
		cd "${workdir}"
		(cd "${root_dir}" && sh scripts/template.sh files) >files.txt
		tar -C "${root_dir}" -cf fixture.tar -T files.txt
		tar -xf fixture.tar
		rm fixture.tar files.txt
		# Every other selector is already digest-pinned, so only gcr.io is looked up.
		pin_selectors_to_locks <config/project.cfg |
			sed -e "s#^DEV_DISTROLESS_STATIC_IMAGE=.*#DEV_DISTROLESS_STATIC_IMAGE='gcr.io/distroless/static-debian13:nonroot'#" >config/project.cfg.test
		: >curl.log
		PATH="${workdir}/bin:${PATH}" sh ./scripts/update.sh config/project.cfg.test >/dev/null
		grep -qx "DEV_DISTROLESS_STATIC_IMAGE_LOCK='gcr.io/distroless/static-debian13:nonroot@${digest}'" config/lockfile.cfg || fail 'update should lock a gcr.io selector to name:tag@digest'
		grep -q 'gcr.io/v2/distroless/static-debian13/manifests/nonroot' curl.log || fail 'update should query the gcr.io manifest for the selector'

		# A blank selector skips the lookup, like the optional k8s images.
		sed -e "s#^DEV_DISTROLESS_STATIC_IMAGE=.*#DEV_DISTROLESS_STATIC_IMAGE=''#" config/project.cfg.test >config/project.cfg.blank
		: >curl.log
		PATH="${workdir}/bin:${PATH}" sh ./scripts/update.sh config/project.cfg.blank >/dev/null
		grep -qx "DEV_DISTROLESS_STATIC_IMAGE_LOCK=''" config/lockfile.cfg || fail 'update should keep an empty distroless lock for a blank selector'
		[ ! -s curl.log ] || fail 'update should not call the registry for a blank distroless selector'
	)
	rm -rf "${workdir}"
}

# The runtime image is opt-in: a default build must not touch the runtime stage.
test_runtime_image_build() {
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
printf '%s\n' "$*" >>docker.log
exit 0
EOF
		chmod +x fake-bin/docker

		: >docker.log
		PATH="${workdir}/fake-bin:${PATH}" sh ./scripts/build.sh config/project.cfg >/dev/null
		grep -Fq -- '--target runtime' docker.log && fail 'a default build must not build the runtime stage'
		grep -Fq -- '--target dev' docker.log || fail 'a default build should still build the dev stage'

		printf '%s\n' '. ./config/project.cfg' "PROJECT_RUNTIME_IMAGE='example-runtime:local'" >config/project.cfg.runtime
		: >docker.log
		PATH="${workdir}/fake-bin:${PATH}" sh ./scripts/build.sh config/project.cfg.runtime >/dev/null
		runtime_line=$(grep -F -- '--target runtime' docker.log) || fail 'PROJECT_RUNTIME_IMAGE should build the runtime stage'
		for expected in "-t example-runtime:local" "RUNTIME_BASE_IMAGE=${DEV_DISTROLESS_STATIC_IMAGE_LOCK}" "RUNTIME_BUILD_IMAGE=${DEV_GO_IMAGE_LOCK}"; do
			printf '%s\n' "${runtime_line}" | grep -Fq -- "${expected}" || fail "runtime build should pass ${expected}"
		done

		# Opting in without digest locks must fail before any docker build, rather
		# than fall back to the Dockerfile's mutable default tags.
		cp config/lockfile.cfg config/lockfile.cfg.orig
		for lock_name in DEV_DISTROLESS_STATIC_IMAGE_LOCK DEV_GO_IMAGE_LOCK; do
			for mutation in "/^${lock_name}=/d" "s#^\(${lock_name}='[^@]*\)@sha256:[a-f0-9]*'#\1'#"; do
				sed -e "${mutation}" config/lockfile.cfg.orig >config/lockfile.cfg
				: >docker.log
				if PATH="${workdir}/fake-bin:${PATH}" sh ./scripts/build.sh config/project.cfg.runtime >build.txt 2>&1; then
					fail "runtime build should fail when ${lock_name} is missing or unpinned"
				fi
				grep -Fq "${lock_name} must be pinned by digest" build.txt || fail "runtime build should name ${lock_name}"
				[ ! -s docker.log ] || fail "runtime build should reject ${lock_name} before calling docker"
			done
		done
	)
	rm -rf "${workdir}"
}

# Run the runtime policy against a mutated copy of the shipped Dockerfile/lockfile.
assert_runtime_policy_rejects() {
	name=$1
	mutation=$2
	expected_message=$3
	fixture_dir=$(mktemp -d)
	cp Dockerfile "${fixture_dir}/Dockerfile"
	cp config/lockfile.cfg "${fixture_dir}/lockfile.cfg"
	(
		cd "${fixture_dir}"
		eval "${mutation}"
		if check_runtime_image_policy Dockerfile lockfile.cfg >policy.txt 2>&1; then
			fail "runtime policy should reject ${name}"
		fi
		grep -q "${expected_message}" policy.txt || fail "runtime policy should report '${expected_message}' for ${name}"
	)
	rm -rf "${fixture_dir}"
}

test_runtime_image_policy() {
	check_runtime_image_policy Dockerfile config/lockfile.cfg || fail 'runtime policy should accept the shipped Dockerfile and lockfile'
	assert_runtime_policy_rejects 'an unpinned lock' \
		"sed -i \"s#^DEV_DISTROLESS_STATIC_IMAGE_LOCK=.*#DEV_DISTROLESS_STATIC_IMAGE_LOCK='gcr.io/distroless/static-debian13:nonroot'#\" lockfile.cfg" \
		'DEV_DISTROLESS_STATIC_IMAGE_LOCK must be pinned by digest'
	assert_runtime_policy_rejects 'a base that bypasses the lock' \
		"sed -i 's#^FROM .* AS runtime\$#FROM gcr.io/distroless/static-debian13:nonroot AS runtime#' Dockerfile" \
		'must build FROM'
	assert_runtime_policy_rejects 'a missing USER' \
		"sed -i '/^USER nonroot:nonroot\$/d' Dockerfile" \
		'must set a non-root USER'
	assert_runtime_policy_rejects 'USER root' \
		"sed -i 's/^USER nonroot:nonroot\$/USER root /' Dockerfile" \
		'must set a non-root USER'
	assert_runtime_policy_rejects 'USER 00' \
		"sed -i 's/^USER nonroot:nonroot\$/USER 00:0/' Dockerfile" \
		'must set a non-root USER'
	assert_runtime_policy_rejects 'an unverifiable USER variable' \
		"sed -i 's/^USER nonroot:nonroot\$/USER \${APP_UID}/' Dockerfile" \
		'must set a non-root USER'
	assert_runtime_policy_rejects 'root USER in a differently cased stage' \
		"sed -i -e 's/ AS runtime\$/ as Runtime/' -e 's/^USER nonroot:nonroot\$/user root/' Dockerfile" \
		'must set a non-root USER'
	assert_runtime_policy_rejects 'a shell-form ENTRYPOINT' \
		"sed -i 's#^ENTRYPOINT .*#ENTRYPOINT /app#' Dockerfile" \
		'must use an exec-form ENTRYPOINT'
	# A blank selector leaves an empty lock; make build refuses to opt in then.
	fixture_dir=$(mktemp -d)
	sed -e "s#^DEV_DISTROLESS_STATIC_IMAGE_LOCK=.*#DEV_DISTROLESS_STATIC_IMAGE_LOCK=''#" config/lockfile.cfg >"${fixture_dir}/lockfile.cfg"
	check_runtime_image_policy Dockerfile "${fixture_dir}/lockfile.cfg" || fail 'runtime policy should accept an empty lock from a blank selector'
	rm -rf "${fixture_dir}"
	# Derived repositories may remove the stage entirely.
	fixture_dir=$(mktemp -d)
	printf '%s\n' 'FROM debian:trixie-slim AS dev' >"${fixture_dir}/Dockerfile"
	check_runtime_image_policy "${fixture_dir}/Dockerfile" config/lockfile.cfg || fail 'runtime policy should skip Dockerfiles without a runtime stage'
	rm -rf "${fixture_dir}"
}

# The build, lint, test, and run commands are configurable, so check what each
# script hands to `sh -eu -c` inside the container without pulling real images.
test_workflow_command_overrides() {
	workdir=$(mktemp -d)
	root_dir=$(pwd)

	(
		cd "${workdir}"
		(cd "${root_dir}" && sh scripts/template.sh files) >files.txt
		tar -C "${root_dir}" -cf fixture.tar -T files.txt
		tar -xf fixture.tar
		rm fixture.tar files.txt
		mkdir -p fake-bin
		# The fake docker logs every call. With FAKE_DOCKER_EXEC=1 it also runs the
		# final `docker run` argument (the project command) locally, so a failing
		# override can prove the script fails instead of falling back.
		cat >fake-bin/docker <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>docker.log
case "$1" in
image | ps) exit 0 ;;
run)
	if [ "${FAKE_DOCKER_EXEC:-}" = 1 ]; then
		for last in "$@"; do :; done
		sh -eu -c "${last}"
		exit $?
	fi
	printf 'fake-container-id\n'
	;;
esac
exit 0
EOF
		chmod +x fake-bin/docker

		go_build='cd src && go build -trimpath -buildvcs=false ./cmd/app'
		go_lint='cd src && test -z "$(gofmt -l .)" && go vet ./...'
		go_test='cd src && go test -v ./... && go build -trimpath -buildvcs=false ./cmd/app'
		go_run='cd src && go run ./cmd/app'

		# Older layered configs do not define the new variables: the scripts must
		# fall back to the exact Go commands they ran before.
		grep -Ev '^PROJECT_(BUILD|LINT|TEST|RUN)_COMMAND=' config/project.cfg >config/project.cfg.legacy
		for cfg in config/project.cfg config/project.cfg.legacy; do
			: >docker.log
			PATH="${workdir}/fake-bin:${PATH}" sh ./scripts/build.sh "${cfg}" >/dev/null
			PATH="${workdir}/fake-bin:${PATH}" sh ./scripts/test.sh src "${cfg}" >/dev/null
			PATH="${workdir}/fake-bin:${PATH}" sh ./scripts/run.sh "${cfg}" >/dev/null
			for expected in "${go_build}" "${go_lint}" "${go_test}" "${go_run}"; do
				grep -Fq -- "sh -eu -c ${expected}" docker.log || fail "${cfg} should keep running: ${expected}"
			done
		done

		# A layered config that sources the base config and overrides each command.
		cat >config/project.cfg.override <<'EOF'
. ./config/project.cfg
PROJECT_BUILD_COMMAND='echo custom-build'
PROJECT_LINT_COMMAND='echo custom-lint'
PROJECT_TEST_COMMAND='echo custom-test'
PROJECT_RUN_COMMAND='echo custom-run'
EOF
		: >docker.log
		PATH="${workdir}/fake-bin:${PATH}" sh ./scripts/build.sh config/project.cfg.override >/dev/null
		PATH="${workdir}/fake-bin:${PATH}" sh ./scripts/test.sh src config/project.cfg.override >/dev/null
		PATH="${workdir}/fake-bin:${PATH}" sh ./scripts/run.sh config/project.cfg.override >/dev/null
		for name in BUILD LINT TEST RUN; do
			lower=$(printf '%s' "${name}" | tr '[:upper:]' '[:lower:]')
			grep -Fq -- "sh -eu -c echo custom-${lower}" docker.log || fail "PROJECT_${name}_COMMAND override should run"
		done
		for unexpected in "${go_build}" "${go_lint}" "${go_test}" "${go_run}"; do
			grep -Fq -- "${unexpected}" docker.log && fail "overridden commands must not also run: ${unexpected}"
		done

		# Only config sets the commands: an exported variable must not leak into a
		# config that leaves it unset.
		: >docker.log
		PROJECT_BUILD_COMMAND='echo from-env' PATH="${workdir}/fake-bin:${PATH}" sh ./scripts/build.sh config/project.cfg.legacy >/dev/null
		grep -Fq -- "sh -eu -c ${go_build}" docker.log || fail 'an exported PROJECT_BUILD_COMMAND must not replace the config fallback'

		# An explicitly empty command is a deliberate no-op, not a Go fallback.
		printf '%s\n' '. ./config/project.cfg' "PROJECT_LINT_COMMAND=''" >config/project.cfg.empty
		: >docker.log
		PATH="${workdir}/fake-bin:${PATH}" sh ./scripts/test.sh src config/project.cfg.empty >/dev/null
		grep -Fq -- "${go_lint}" docker.log && fail 'an empty PROJECT_LINT_COMMAND must not fall back to the Go lint'

		# An override that fails must fail its script, with no fallback to Go.
		for name in BUILD LINT TEST RUN; do
			case "${name}" in
			BUILD) script='build.sh' ;;
			RUN) script='run.sh' ;;
			*) script='test.sh src' ;;
			esac
			# Neutral commands for the other variables keep host Go out of the picture.
			printf '%s\n' \
				'. ./config/project.cfg' \
				"PROJECT_BUILD_COMMAND='true'" \
				"PROJECT_LINT_COMMAND='true'" \
				"PROJECT_TEST_COMMAND='true'" \
				"PROJECT_RUN_COMMAND='true'" \
				"PROJECT_${name}_COMMAND='exit 7'" >config/project.cfg.failing
			# shellcheck disable=SC2086
			if FAKE_DOCKER_EXEC=1 PATH="${workdir}/fake-bin:${PATH}" sh ./scripts/${script} config/project.cfg.failing >/dev/null 2>&1; then
				fail "a failing PROJECT_${name}_COMMAND should fail ${script}"
			fi
		done
	)
	rm -rf "${workdir}"
}

test_dist_scanner_arguments() {
	workdir=$(mktemp -d)
	root_dir=$(pwd)

	(
		cd "${workdir}"
		(cd "${root_dir}" && sh scripts/template.sh files) >files.txt
		tar -C "${root_dir}" -cf fixture.tar -T files.txt
		tar -xf fixture.tar
		rm fixture.tar files.txt
		mkdir -p fake-bin
		# The fake docker logs each call and stands in for the release command by
		# writing the archive and manifest that the real container would create.
		cat >fake-bin/docker <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>docker.log
case "$*" in
*'scripts/template.sh release'*)
	mkdir -p dist
	: >dist/kc-secure-repo-template.tar.gz
	: >dist/template-manifest.txt
	;;
esac
exit 0
EOF
		chmod +x fake-bin/docker
		. ./config/lockfile.cfg

		PATH="${workdir}/fake-bin:${PATH}" sh ./scripts/dist.sh config/project.cfg >${TMPDIR}/template-dist-args.txt
		# The release command writes dist/, so only it keeps a writable checkout.
		grep -F -- 'scripts/template.sh release' docker.log | grep -Fq -- ':/workspace ' || fail 'release command should mount the repository read-write'
		# syft and grype only read the archive and SBOM, so they cannot modify the
		# checkout or the evidence they are reporting on.
		syft_line=$(grep -F -- "${DEV_SCAN_SYFT_IMAGE_LOCK}" docker.log) || fail 'dist should run the digest-pinned syft image'
		printf '%s\n' "${syft_line}" | grep -Fq -- ':/workspace:ro' || fail 'syft should mount the repository read-only'
		grype_line=$(grep -F -- "${DEV_SCAN_GRYPE_IMAGE_LOCK}" docker.log) || fail 'dist should run the digest-pinned grype image'
		printf '%s\n' "${grype_line}" | grep -Fq -- ':/workspace:ro' || fail 'grype should mount the repository read-only'
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

# Run the attribution check on one message and report whether it was rejected.
assert_commit_message_policy() {
	name=$1
	expected=$2
	message=$3
	message_file=${TMPDIR}/commit-policy-message.txt

	printf '%s\n' "${message}" >"${message_file}"
	if check_commit_message_file "${message_file}" >"${TMPDIR}/commit-policy-output.txt" 2>&1; then
		actual=accept
	else
		actual=reject
	fi
	[ "${actual}" = "${expected}" ] || fail "commit policy ${name}: expected ${expected}, got ${actual}"
}

test_commit_policy_message_rules() {
	assert_commit_message_policy 'plain message' accept '[fix] docker: update snapshot

Mention claude in prose without attribution.'
	assert_commit_message_policy 'human co-author' accept '[feat] src: add flag

Co-authored-by: Pat Example <pat@example.invalid>'
	assert_commit_message_policy 'claude co-author' reject '[feat] src: add flag

Co-authored-by: Claude <noreply@anthropic.com>'
	assert_commit_message_policy 'codex co-author' reject '[feat] src: add flag

co-authored-by: Codex <codex@openai.com>'
	assert_commit_message_policy 'generated-with line' reject '[feat] src: add flag

🤖 Generated with [Claude Code](https://claude.com/claude-code)'
	assert_commit_message_policy 'assisted-by trailer' reject '[feat] src: add flag

Assisted-by: Claude <noreply@anthropic.com>'
	assert_commit_message_policy 'co-developed-by trailer' reject '[feat] src: add flag

Co-developed-by: Codex <codex@openai.com>'
	assert_commit_message_policy 'generated-by trailer' reject '[feat] src: add flag

Generated-by: Claude Code'
	assert_commit_message_policy 'human assisted-by trailer' accept '[feat] src: add flag

Assisted-by: Pat Example <pat@example.invalid>'
	assert_commit_message_policy 'generated prose' accept '[docs] src: explain output

Files generated by AI tools must be reviewed.'
	assert_commit_message_policy 'session trailer' reject '[feat] src: add flag

Claude-Session: abc123'
	assert_commit_message_policy 'session url' reject '[feat] src: add flag

See https://claude.ai/code/session_0123'
	assert_commit_message_policy 'comment line' accept '[feat] src: add flag
# Co-authored-by: Claude <noreply@anthropic.com>'
	assert_commit_message_policy 'below scissors' accept '[feat] src: add flag
# ------------------------ >8 ------------------------
+Co-authored-by: Claude <noreply@anthropic.com>'
	grep -q 'AI attribution' "${TMPDIR}/commit-policy-output.txt" && fail 'accepted message should not print a rejection'
	assert_commit_message_policy 'rejection output' reject 'x

Co-authored-by: Claude <noreply@anthropic.com>'
	grep -q 'Co-authored-by: Claude' "${TMPDIR}/commit-policy-output.txt" || fail 'commit policy should print the offending line'
}

test_commit_policy_range() {
	history_dir=$(mktemp -d)

	if ! (
		cd "${history_dir}"
		mkdir home
		export HOME="${history_dir}/home"
		git init -q -b main source
		cd source
		git config user.name 'Commit Policy Test'
		git config user.email 'commit-policy@example.invalid'
		git commit -q --allow-empty -m 'initial'
		base=$(git rev-parse HEAD)
		git commit -q --allow-empty -m '[feat] src: one' -m 'Co-authored-by: Claude <noreply@anthropic.com>'
		bad=$(git rev-parse HEAD)
		git commit -q --allow-empty -m '[feat] src: two'
		head=$(git rev-parse HEAD)

		# A bad commit in the middle of the pushed range must fail the check.
		if COMMIT_POLICY_BASE=${base} COMMIT_POLICY_HEAD=${head} check_commit_attribution_policy >../range.txt 2>&1; then
			fail 'commit range policy should reject a bad commit inside the range'
		fi
		grep -q "${bad}" ../range.txt || fail 'commit range policy should name the offending commit'

		# An unresolvable head must fail instead of checking zero commits.
		if COMMIT_POLICY_BASE=${base} COMMIT_POLICY_HEAD=deadbeefnotacommit check_commit_attribution_policy >/dev/null 2>&1; then
			fail 'commit range policy should fail when the head cannot be resolved'
		fi

		# A range that starts after the bad commit passes.
		COMMIT_POLICY_BASE=${bad} COMMIT_POLICY_HEAD=${head} check_commit_attribution_policy >/dev/null 2>&1 ||
			fail 'commit range policy should accept a clean range'

		# An unknown base (new branch push, rewritten history) checks all of history.
		if COMMIT_POLICY_BASE=0000000000000000000000000000000000000000 COMMIT_POLICY_HEAD=${head} check_commit_attribution_policy >/dev/null 2>&1; then
			fail 'commit range policy should check full history when the base is unknown'
		fi

		# Without CI variables or a remote, only HEAD is checked.
		(unset COMMIT_POLICY_BASE COMMIT_POLICY_HEAD; check_commit_attribution_policy >/dev/null 2>&1) ||
			fail 'local commit policy without a remote should check HEAD only'

		# Without CI variables, a remote default branch bounds the local range.
		git update-ref refs/remotes/origin/main "${base}"
		if (unset COMMIT_POLICY_BASE COMMIT_POLICY_HEAD; check_commit_attribution_policy >/dev/null 2>&1); then
			fail 'local commit policy should check commits since origin/main'
		fi

		# Recorded messages are checked verbatim: a stored scissors line must not
		# hide a trailer after it (the hook-only cleanup does not apply here).
		git commit -q --allow-empty --cleanup=verbatim -m '[feat] src: three
# ------------------------ >8 ------------------------
Co-authored-by: Claude <noreply@anthropic.com>'
		scissors=$(git rev-parse HEAD)
		if COMMIT_POLICY_BASE=${head} COMMIT_POLICY_HEAD=${scissors} check_commit_attribution_policy >/dev/null 2>&1; then
			fail 'commit range policy should check recorded messages verbatim'
		fi
	); then
		rm -rf "${history_dir}"
		return 1
	fi
	rm -rf "${history_dir}"

	# Archives have no Git metadata; the check skips instead of failing.
	archive_dir=$(mktemp -d)
	(cd "${archive_dir}" && GIT_CEILING_DIRECTORIES=${archive_dir%/*} check_commit_attribution_policy >/dev/null 2>&1) ||
		fail 'commit policy should skip outside a Git checkout'
	rm -rf "${archive_dir}"
}

# Copy the real agent files into a disposable fixture so each case mutates one thing.
agent_policy_fixture() {
	fixture_dir=$(mktemp -d)
	cp -R .agents .claude AGENTS.md "${fixture_dir}/"
	printf '%s\n' "${fixture_dir}"
}

run_agent_policy_checks() {
	check_agent_skill_policy && check_agent_guidance_size && check_agent_settings_policy
}

# Apply one mutation in a fresh fixture and require a specific rejection message.
assert_agent_policy_rejects() {
	name=$1
	mutation=$2
	expected_message=$3
	fixture_dir=$(agent_policy_fixture)

	(
		cd "${fixture_dir}"
		eval "${mutation}"
		if run_agent_policy_checks >"${TMPDIR}/agent-policy.txt" 2>&1; then
			fail "agent policy should reject ${name}"
		fi
		grep -q "${expected_message}" "${TMPDIR}/agent-policy.txt" ||
			fail "agent policy should report '${expected_message}' for ${name}"
	)
	rm -rf "${fixture_dir}"
}

test_agent_policy_accepts_repository() {
	fixture_dir=$(agent_policy_fixture)
	(
		cd "${fixture_dir}"
		run_agent_policy_checks >"${TMPDIR}/agent-policy.txt" 2>&1 || {
			cat "${TMPDIR}/agent-policy.txt" >&2
			fail 'agent policy should accept the shipped agent files'
		}
	)
	rm -rf "${fixture_dir}"
}

test_agent_policy_rejects_violations() {
	assert_agent_policy_rejects 'a missing entrypoint' \
		'rm -r .claude/skills/pr-draft-summary' \
		'pr-draft-summary: missing Claude entrypoint'
	assert_agent_policy_rejects 'an orphan entrypoint' \
		'mkdir .claude/skills/orphan && cp .claude/skills/pr-draft-summary/SKILL.md .claude/skills/orphan/' \
		'orphan: Claude entrypoint has no canonical skill'
	assert_agent_policy_rejects 'description drift' \
		'sed -i "s/^description: .*/description: Drifted./" .claude/skills/pr-draft-summary/SKILL.md' \
		'pr-draft-summary: entrypoint description differs'
	assert_agent_policy_rejects 'a name mismatch' \
		'sed -i "s/^name: .*/name: other/" .agents/skills/pr-draft-summary/SKILL.md' \
		'pr-draft-summary: frontmatter name'
	assert_agent_policy_rejects 'a host-only key in a canonical skill' \
		'sed -i "2a model: sonnet" .agents/skills/pr-draft-summary/SKILL.md' \
		'pr-draft-summary: non-portable frontmatter key model'
	assert_agent_policy_rejects 'a broken canonical link' \
		'sed -i "s#\.agents/skills/pr-draft-summary/SKILL\.md#.agents/skills/missing/SKILL.md#" .claude/skills/pr-draft-summary/SKILL.md' \
		'pr-draft-summary: entrypoint must link'
	assert_agent_policy_rejects 'an implicitly invocable Claude security review' \
		'sed -i "/^disable-model-invocation:/d" .claude/skills/repo-security-review/SKILL.md' \
		'repo-security-review: must stay manual-only'
	assert_agent_policy_rejects 'an implicitly invocable Codex security review' \
		'sed -i "s/allow_implicit_invocation: false/allow_implicit_invocation: true/" .agents/skills/repo-security-review/agents/openai.yaml' \
		'repo-security-review: must stay manual-only'
	assert_agent_policy_rejects 'oversized root guidance' \
		'AGENT_GUIDANCE_MAX_LINES=10; export AGENT_GUIDANCE_MAX_LINES' \
		'AGENTS.md has'
	assert_agent_policy_rejects 'a missing deny rule' \
		'jq ".permissions.deny -= [\"Bash(git commit -n*)\"]" .claude/settings.json >settings.tmp && mv settings.tmp .claude/settings.json' \
		'missing deny rule Bash(git commit -n\*)'
	assert_agent_policy_rejects 'a deny rule moved to allow' \
		'jq ".permissions.deny -= [\"Bash(git commit --no-verify*)\"] | .permissions.allow = [\"Bash(git commit --no-verify*)\"]" .claude/settings.json >settings.tmp && mv settings.tmp .claude/settings.json' \
		'missing deny rule Bash(git commit --no-verify\*)'
	assert_agent_policy_rejects 'an overly broad deny rule' \
		'jq ".permissions.deny += [\"Bash(git commit * -n*)\"]" .claude/settings.json >settings.tmp && mv settings.tmp .claude/settings.json' \
		'overly broad deny rule Bash(git commit \* -n\*)'
	assert_agent_policy_rejects 'unreadable Claude settings' \
		'printf "{\\n" >.claude/settings.json' \
		'cannot read permissions.deny'
	assert_agent_policy_rejects 'missing Claude settings' \
		'rm .claude/settings.json' \
		'.claude/settings.json is missing'
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
	# Read the workflow commands only from the config, never from the caller's
	# environment, so an exported variable cannot replace the reviewed command.
	unset PROJECT_BUILD_COMMAND PROJECT_LINT_COMMAND PROJECT_TEST_COMMAND PROJECT_RUN_COMMAND
	. "${PROJECT_CFG_FILE_PATH}"

	# Workflow commands run through `sh -eu -c` in the existing non-root dev
	# container. Fall back to the Go example commands so older layered configs that
	# predate these settings keep working unchanged. Only an unset variable falls
	# back; an explicitly empty command is a deliberate no-op.
	project_lint_command=${PROJECT_LINT_COMMAND-'cd src && test -z "$(gofmt -l .)" && go vet ./...'}
	project_test_command=${PROJECT_TEST_COMMAND-'cd src && go test -v ./... && go build -trimpath -buildvcs=false ./cmd/app'}

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
		sh -eu -c "${project_lint_command}"

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
		sh -eu -c "${project_test_command}"

	printf '\n==> Test summary\n'
	# Summaries make CI and local output easier to scan.
	printf '%s\n' "Image: ${src_image}"
	printf '%s\n' "Project config: ${PROJECT_CFG_FILE}"
	printf '%s\n' "Lint command: ${project_lint_command}"
	printf '%s\n' "Test command: ${project_test_command}"
	printf '%s\n' 'Results: lint passed, tests passed'
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
		. ./scripts/commit-policy.sh
		. ./scripts/agent-policy.sh
		. ./config/lockfile.cfg
		test_workflow_issue_comment_is_rejected
		test_workflow_missing_permissions_is_rejected
		test_workflow_zizmor_ignore_is_rejected
		test_ci_change_detection_rules
		test_ci_change_detection_output_contract
		test_ci_change_detection_git_history
		test_template_skip_src_tests_flag
		test_commit_policy_message_rules
		test_commit_policy_range
		test_agent_policy_accepts_repository
		test_agent_policy_rejects_violations
		test_local_state_is_not_packaged
		test_infra_preserves_lock_and_forwards_token
		sh scripts/test-release.sh
		test_optional_k8s_update_compat
		test_update_package_snapshot_refresh
		test_update_gcr_digest
		test_runtime_image_build
		test_runtime_image_policy
		test_optional_k8s_scan_skip
		test_scan_scanner_arguments
		test_scan_image_vulns
		test_dist_scanner_arguments
		test_workflow_command_overrides
		test_k8s_shell_inputs_are_not_executed
		test_k8s_render_file_scan_path
		test_k8s_test_local_uses_kubeconfig_and_server_dry_run
		exit 0
	fi
	# Exercise the shipped build/test code with the current image locks. The
	# layered config only adds the opt-in runtime image, so one `make build` also
	# builds it for real (the fake-docker tests cannot catch a broken `go build` or
	# base image). Then check it is non-root, holds only the binary, and starts
	# the example.
	runtime_check_image='kc-template-runtime-check:local'
	printf '%s\n' '. ./config/project.cfg' "PROJECT_RUNTIME_IMAGE='${runtime_check_image}'" >"${TMPDIR}/template-runtime.cfg"
	make build PROJECT_CFG_FILE="${TMPDIR}/template-runtime.cfg"
	[ "$(docker image inspect --format '{{.Config.User}}' "${runtime_check_image}")" = 'nonroot:nonroot' ] || fail 'runtime image should run as nonroot:nonroot'
	[ "$(docker run --rm --network=none --cap-drop=ALL --security-opt=no-new-privileges:true "${runtime_check_image}")" = 'Hello, World!' ] || fail 'runtime image should start the example'
	runtime_container=$(docker create "${runtime_check_image}")
	docker export "${runtime_container}" | tar -t >"${TMPDIR}/template-runtime-files.txt"
	docker rm "${runtime_container}" >/dev/null
	grep -qx 'app' "${TMPDIR}/template-runtime-files.txt" || fail 'runtime image should contain the /app binary'
	! grep -Eq '(^build/|\.go$|^go\.mod$)' "${TMPDIR}/template-runtime-files.txt" || fail 'runtime image must not contain source or tests'
	docker image rm "${runtime_check_image}" >/dev/null
	if template_skip_src_tests; then
		printf '%s\n' 'Skipping nested src tests (TEMPLATE_SKIP_SRC_TESTS=true); they are covered by the test-code job.'
	else
		make test TEST_MODE=src
	fi
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
	. ./scripts/workflow-policy.sh
	test_zizmor_rejects_unsafe_workflows
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
