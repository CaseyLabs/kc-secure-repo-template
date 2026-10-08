#!/bin/sh
# Focused behavior checks; invoked inside the disposable template test copy.
set -eu
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
test_dir=$(mktemp -d)
trap 'rm -rf "${test_dir}"' EXIT
trap 'exit 1' HUP INT TERM

ENABLE_SBOM=false ENABLE_GRYPE=false sh scripts/release-policy.sh || fail 'local disabled scans should pass'
if RELEASE_PUBLICATION=true RELEASE_TAG=v1.2.3 ENABLE_SBOM=false ENABLE_GRYPE=false \
	RELEASE_EXCEPTION_FILE="${test_dir}/missing" sh scripts/release-policy.sh >/dev/null 2>&1; then
	fail 'publication without exception passed'
fi
cat >"${test_dir}/exception" <<'EOF'
RELEASE_EXCEPTION_ID='TEST-1'
RELEASE_EXCEPTION_OWNER='maintainer'
RELEASE_EXCEPTION_RATIONALE='scanner outage'
RELEASE_EXCEPTION_RISK='unscanned archive'
RELEASE_EXCEPTION_APPROVAL='reviewed change'
RELEASE_EXCEPTION_COMPENSATING='independent scan'
RELEASE_EXCEPTION_EXPIRES='2099-01-01'
RELEASE_EXCEPTION_TAG='v1.2.3'
RELEASE_EXCEPTION_CONTROLS='sbom grype'
EOF
RELEASE_PUBLICATION=true RELEASE_TAG=v1.2.3 ENABLE_SBOM=false ENABLE_GRYPE=false \
	RELEASE_EXCEPTION_FILE="${test_dir}/exception" sh scripts/release-policy.sh >/dev/null || fail 'valid exception failed'
if RELEASE_PUBLICATION=true RELEASE_TAG=v2.0.0 ENABLE_SBOM=false ENABLE_GRYPE=false \
	RELEASE_EXCEPTION_FILE="${test_dir}/exception" sh scripts/release-policy.sh >/dev/null 2>&1; then
	fail 'wrong-tag exception passed'
fi
sed 's/2099-01-01/2000-01-01/' "${test_dir}/exception" >"${test_dir}/expired"
if RELEASE_PUBLICATION=true RELEASE_TAG=v1.2.3 ENABLE_SBOM=false ENABLE_GRYPE=false \
	RELEASE_EXCEPTION_FILE="${test_dir}/expired" sh scripts/release-policy.sh >/dev/null 2>&1; then
	fail 'expired exception passed'
fi
printf 'ENABLE_SBOM=false\nENABLE_GRYPE=false\n' >"${test_dir}/disabled.cfg"
if RELEASE_PUBLICATION=true RELEASE_TAG=v1.2.3 \
	RELEASE_EXCEPTION_FILE="${test_dir}/missing" \
	sh scripts/dist.sh "${test_dir}/disabled.cfg" >/dev/null 2>&1; then
	fail 'config-file scanner defaults bypassed publication policy'
fi

# A fake make records the bounded sequence without requiring a second Docker
# build in this focused test. Production template mode tests real Docker.
mkdir -p "${test_dir}/source/scripts" "${test_dir}/source/config" "${test_dir}/source/src" "${test_dir}/bin"
touch "${test_dir}/source/Makefile" "${test_dir}/source/Dockerfile" \
	"${test_dir}/source/config/project.cfg" "${test_dir}/source/scripts/build.sh" \
	"${test_dir}/source/scripts/test.sh"
tar -czf "${test_dir}/archive.tar.gz" -C "${test_dir}/source" .
cat >"${test_dir}/bin/make" <<'EOF'
#!/bin/sh
printf '%s %s\n' "${TEST_MODE:-default}" "$*" >>"${MAKE_LOG}"
if [ "${MAKE_FAIL:-false}" = true ]; then
	exit 42
fi
if [ "${MAKE_MUTATE:-false}" = true ]; then
	printf x >>"${ARCHIVE_TO_MUTATE}"
fi
EOF
chmod +x "${test_dir}/bin/make"
PATH="${test_dir}/bin:${PATH}" MAKE_LOG="${test_dir}/make.log" \
	sh scripts/validate-release-archive.sh "${test_dir}/archive.tar.gz" >/dev/null || fail 'valid archive failed'
[ "$(cat "${test_dir}/make.log")" = "$(printf 'default build\nsrc test')" ] || fail 'archive validation invoked wrong commands'
if PATH="${test_dir}/bin:${PATH}" MAKE_LOG="${test_dir}/make.log" MAKE_FAIL=true \
	sh scripts/validate-release-archive.sh "${test_dir}/archive.tar.gz" >/dev/null 2>&1; then
	fail 'build failure did not block archive validation'
fi
if PATH="${test_dir}/bin:${PATH}" MAKE_LOG="${test_dir}/make.log" MAKE_MUTATE=true \
	ARCHIVE_TO_MUTATE="${test_dir}/archive.tar.gz" \
	sh scripts/validate-release-archive.sh "${test_dir}/archive.tar.gz" >/dev/null 2>&1; then
	fail 'changed archive was accepted'
fi
printf 'release policy and archive validation checks passed\n'
