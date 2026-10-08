#!/bin/sh
# Publication gate shared by the release workflow and dist generation.
set -eu

enable_sbom=${ENABLE_SBOM:-true}
enable_grype=${ENABLE_GRYPE:-true}
grype_fail_on=${GRYPE_FAIL_ON:-critical}

case "${enable_sbom}:${enable_grype}:${grype_fail_on}" in
true:true:critical|true:true:high|true:true:medium|true:true:low|true:true:negligible|true:false:critical|false:false:critical) ;;
*) printf 'invalid release scan settings\n' >&2; exit 1 ;;
esac

# Local disposable archives may omit scanners. Only publication needs an
# approved, time-bounded exception for either missing gate.
[ "${RELEASE_PUBLICATION:-false}" = true ] || exit 0
[ "${enable_sbom}" = true ] && [ "${enable_grype}" = true ] && exit 0

exception_file=${RELEASE_EXCEPTION_FILE:-config/release-exception.cfg}
[ -f "${exception_file}" ] || {
	printf 'publication with disabled release scans requires %s\n' "${exception_file}" >&2
	exit 1
}
# This file is reviewed code in the release commit. Keep the accepted fields
# explicit so an empty or expired exception cannot silently pass the gate.
case "${exception_file}" in
/*|./*|../*) . "${exception_file}" ;;
*) . "./${exception_file}" ;;
esac
for field in RELEASE_EXCEPTION_ID RELEASE_EXCEPTION_OWNER RELEASE_EXCEPTION_RATIONALE \
	RELEASE_EXCEPTION_RISK RELEASE_EXCEPTION_APPROVAL RELEASE_EXCEPTION_COMPENSATING \
	RELEASE_EXCEPTION_EXPIRES RELEASE_EXCEPTION_TAG RELEASE_EXCEPTION_CONTROLS; do
	eval 'value=${'"${field}"':-}'
	[ -n "${value}" ] || { printf 'missing %s in release exception\n' "${field}" >&2; exit 1; }
done
[ "${RELEASE_EXCEPTION_TAG}" = "${RELEASE_TAG:-}" ] || {
	printf 'release exception does not cover tag %s\n' "${RELEASE_TAG:-}" >&2; exit 1;
}
case "${RELEASE_EXCEPTION_EXPIRES}" in
????-??-??) ;;
*) printf 'exception expiry must be YYYY-MM-DD\n' >&2; exit 1 ;;
esac
expiry=$(date -u -d "${RELEASE_EXCEPTION_EXPIRES}" +%F 2>/dev/null) || {
	printf 'invalid exception expiry\n' >&2; exit 1;
}
[ "${expiry}" = "${RELEASE_EXCEPTION_EXPIRES}" ] &&
	[ "${expiry}" \> "$(date -u +%F)" ] || {
	printf 'release exception expired\n' >&2; exit 1;
}
for control in ${RELEASE_EXCEPTION_CONTROLS}; do
	case "${control}" in sbom|grype) ;; *) printf 'unknown exception control\n' >&2; exit 1 ;; esac
done
if [ "${enable_sbom}" = false ]; then
	case " ${RELEASE_EXCEPTION_CONTROLS} " in *' sbom '*) ;; *) printf 'exception does not cover SBOM\n' >&2; exit 1 ;; esac
fi
if [ "${enable_grype}" = false ]; then
	case " ${RELEASE_EXCEPTION_CONTROLS} " in *' grype '*) ;; *) printf 'exception does not cover Grype\n' >&2; exit 1 ;; esac
fi
printf 'release exception %s permits disabled controls for %s\n' "${RELEASE_EXCEPTION_ID}" "${RELEASE_TAG}"
