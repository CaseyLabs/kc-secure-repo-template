#!/bin/sh
# Smoke-test the exact archive that will be attested and published.
set -eu
archive=${1:-dist/kc-secure-repo-template.tar.gz}
[ -f "${archive}" ] || { printf 'missing release archive: %s\n' "${archive}" >&2; exit 1; }
before=$(sha256sum "${archive}" | cut -d ' ' -f 1)
scratch=$(mktemp -d)
trap 'rm -rf "${scratch}"' EXIT
trap 'exit 1' HUP INT TERM
tar -xzf "${archive}" -C "${scratch}"
for required in Makefile Dockerfile config/project.cfg scripts/build.sh scripts/test.sh src; do
	[ -e "${scratch}/${required}" ] || { printf 'archive missing %s\n' "${required}" >&2; exit 1; }
done
(
	cd "${scratch}"
	make build
	TEST_MODE=src make test
)
after=$(sha256sum "${archive}" | cut -d ' ' -f 1)
[ "${before}" = "${after}" ] || { printf 'release archive changed during validation\n' >&2; exit 1; }
printf 'validated release archive sha256:%s\n' "${after}"
