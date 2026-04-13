#!/usr/bin/env bash
set -euo pipefail

# Bootstrap a GitHub App for self-hosted Renovate using the GitHub App manifest flow.
#
# Supports:
# - GitHub user-owned apps
# - GitHub org-owned apps
# - public or private target repos
#
# Default target:
#   owner: CaseyLabs
#   repo:  kc-secure-repo-template
#
# Requirements:
# - bash
# - python3
# - curl
# - gh
#
# Notes:
# - GitHub App creation still requires a browser handoff / approval step.
# - The returned manifest code must be exchanged within GitHub's allowed window.
# - Renovate requires an installation token when running as a GitHub App.
# - Private repos work fine, but the app must be installed on the target repo.

OWNER="${OWNER:-CaseyLabs}"
REPO="${REPO:-kc-secure-repo-template}"

# ACCOUNT_KIND:
# - user: creates the app under a GitHub user account
# - org:  creates the app under a GitHub organization
ACCOUNT_KIND="${ACCOUNT_KIND:-user}"

APP_NAME="${APP_NAME:-Renovate-Bot}"
APP_DESCRIPTION="${APP_DESCRIPTION:-Renovate-Bot creates pull requests for tooling upgrades}"

CALLBACK_HOST="${CALLBACK_HOST:-127.0.0.1}"
CALLBACK_PORT="${CALLBACK_PORT:-8123}"
CALLBACK_URL="http://${CALLBACK_HOST}:${CALLBACK_PORT}/callback"
if [[ "${ACCOUNT_KIND}" == "org" ]]; then
	POST_INSTALL_URL="${POST_INSTALL_URL:-https://github.com/organizations/${OWNER}/settings/installations}"
else
	POST_INSTALL_URL="${POST_INSTALL_URL:-https://github.com/settings/installations}"
fi

# Where to save a local copy for local-only/container runs.
LOCAL_CONFIG_DIR="${LOCAL_CONFIG_DIR:-$HOME/.config/renovate}"
LOCAL_APP_SLUG_FILE="${LOCAL_CONFIG_DIR}/${OWNER}-${REPO}.app-slug"
LOCAL_APP_ID_FILE="${LOCAL_CONFIG_DIR}/${OWNER}-${REPO}.app-id"
LOCAL_CLIENT_ID_FILE="${LOCAL_CONFIG_DIR}/${OWNER}-${REPO}.client-id"
LOCAL_PRIVATE_KEY_FILE="${LOCAL_CONFIG_DIR}/${OWNER}-${REPO}.private-key.pem"

# Repo Actions variable/secret names
CLIENT_ID_VAR_NAME="${CLIENT_ID_VAR_NAME:-RENOVATE_APP_CLIENT_ID}"
APP_ID_VAR_NAME="${APP_ID_VAR_NAME:-RENOVATE_APP_ID}"
PRIVATE_KEY_SECRET_NAME="${PRIVATE_KEY_SECRET_NAME:-RENOVATE_APP_PRIVATE_KEY}"

need_cmd() {
	command -v "$1" >/dev/null 2>&1 || {
		echo "Error: missing required command: $1" >&2
		exit 1
	}
}

need_cmd bash
need_cmd python3
need_cmd curl
need_cmd gh

gh auth status >/dev/null 2>&1 || {
	echo "Error: gh is not authenticated. Run: gh auth login" >&2
	exit 1
}

mkdir -p "${LOCAL_CONFIG_DIR}"

WORKDIR="$(mktemp -d)"
cleanup() {
	if [[ -n "${SERVER_PID:-}" ]]; then
		kill "${SERVER_PID}" >/dev/null 2>&1 || true
	fi
	rm -rf "${WORKDIR}"
}
trap cleanup EXIT

STATE="$(
	python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(24))
PY
)"

cat >"${WORKDIR}/callback_server.py" <<'PY'
import http.server
import socketserver
import sys
import urllib.parse
from pathlib import Path

host = sys.argv[1]
port = int(sys.argv[2])
outfile = Path(sys.argv[3])

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path != "/callback":
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"Not found")
            return

        params = urllib.parse.parse_qs(parsed.query)
        code = params.get("code", [""])[0]
        state = params.get("state", [""])[0]
        outfile.write_text(code + "\n" + state + "\n", encoding="utf-8")

        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(
            b"GitHub callback received.\n"
            b"You can return to the terminal.\n"
        )

    def log_message(self, format, *args):
        pass

with socketserver.TCPServer((host, port), Handler) as httpd:
    httpd.timeout = 3600
    while not outfile.exists():
        httpd.handle_request()
PY

CALLBACK_FILE="${WORKDIR}/callback.txt"
python3 "${WORKDIR}/callback_server.py" "${CALLBACK_HOST}" "${CALLBACK_PORT}" "${CALLBACK_FILE}" &
SERVER_PID=$!

export ACCOUNT_KIND APP_NAME APP_DESCRIPTION CALLBACK_URL POST_INSTALL_URL
python3 - <<'PY' >"${WORKDIR}/manifest.json"
import json
import os

manifest = {
    "name": os.environ["APP_NAME"],
    "url": "https://example.invalid/renovate",
    "description": os.environ["APP_DESCRIPTION"],
    "public": False,
    "redirect_url": os.environ["CALLBACK_URL"],
    "callback_urls": [os.environ["CALLBACK_URL"]],
    "setup_url": os.environ["POST_INSTALL_URL"],
    "hook_attributes": {
        "url": "https://example.invalid/renovate/webhook",
        "active": False
    },
    "default_permissions": {
        "checks": "write",
        "statuses": "write",
        "contents": "write",
        "issues": "write",
        "pull_requests": "write",
        "workflows": "write",
        "administration": "read",
        "vulnerability_alerts": "read",
        "metadata": "read"
    },
    "default_events": [
        "security_advisory",
        "check_run",
        "check_suite",
        "issues",
        "pull_request",
        "push",
        "repository",
        "status"
    ]
}
if os.environ["ACCOUNT_KIND"] == "org":
    manifest["default_permissions"]["members"] = "read"
print(json.dumps(manifest))
PY

if [[ "${ACCOUNT_KIND}" == "org" ]]; then
	REGISTER_ENDPOINT="https://github.com/organizations/${OWNER}/settings/apps/new"
else
	REGISTER_ENDPOINT="https://github.com/settings/apps/new"
fi

export REGISTER_ENDPOINT STATE WORKDIR
python3 - <<'PY' >"${WORKDIR}/register.html"
import html
import os
from pathlib import Path

manifest = Path(os.environ["WORKDIR"]) / "manifest.json"
manifest_json = manifest.read_text(encoding="utf-8")

register_endpoint = os.environ["REGISTER_ENDPOINT"]
state = os.environ["STATE"]

page = f"""<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>Register Renovate GitHub App</title>
  </head>
  <body>
    <p>Opening GitHub App registration…</p>
    <form id="register" method="post" action="{html.escape(register_endpoint)}?state={html.escape(state)}">
      <input type="hidden" name="manifest" value="{html.escape(manifest_json, quote=True)}">
    </form>
    <script>
      document.getElementById('register').submit();
    </script>
  </body>
</html>
"""
print(page)
PY

echo "Opening GitHub App registration page in your browser..."
python3 -m webbrowser "file://${WORKDIR}/register.html" >/dev/null 2>&1 || true

echo "If your browser did not open, open this file manually:"
echo "  file://${WORKDIR}/register.html"
echo
echo "Waiting for callback on ${CALLBACK_URL} ..."

for _ in $(seq 1 3600); do
	if [[ -f "${CALLBACK_FILE}" ]]; then
		break
	fi
	sleep 1
done

if [[ ! -f "${CALLBACK_FILE}" ]]; then
	echo "Error: timed out waiting for the GitHub callback." >&2
	exit 1
fi

CODE="$(sed -n '1p' "${CALLBACK_FILE}")"
RETURNED_STATE="$(sed -n '2p' "${CALLBACK_FILE}")"

if [[ -z "${CODE}" ]]; then
	echo "Error: callback did not include a manifest code." >&2
	exit 1
fi

if [[ "${RETURNED_STATE}" != "${STATE}" ]]; then
	echo "Error: state mismatch in callback." >&2
	exit 1
fi

echo "Exchanging manifest code for app credentials..."
curl -fsSL \
	-X POST \
	-H "Accept: application/vnd.github+json" \
	"https://api.github.com/app-manifests/${CODE}/conversions" \
	>"${WORKDIR}/app.json"

python3 - "${WORKDIR}/app.json" "${LOCAL_APP_SLUG_FILE}" "${LOCAL_APP_ID_FILE}" "${LOCAL_CLIENT_ID_FILE}" "${LOCAL_PRIVATE_KEY_FILE}" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))

slug_file = Path(sys.argv[2])
app_id_file = Path(sys.argv[3])
client_id_file = Path(sys.argv[4])
private_key_file = Path(sys.argv[5])

slug = data.get("slug", "")
app_id = str(data["id"])
client_id = data["client_id"]
pem = data["pem"]

if slug:
    slug_file.write_text(slug + "\n", encoding="utf-8")
app_id_file.write_text(app_id + "\n", encoding="utf-8")
client_id_file.write_text(client_id + "\n", encoding="utf-8")
private_key_file.write_text(pem, encoding="utf-8")
private_key_file.chmod(0o600)
PY

APP_ID="$(tr -d '\n' <"${LOCAL_APP_ID_FILE}")"
CLIENT_ID="$(tr -d '\n' <"${LOCAL_CLIENT_ID_FILE}")"
APP_SLUG=""
INSTALL_URL=""
if [[ -f "${LOCAL_APP_SLUG_FILE}" ]]; then
	APP_SLUG="$(tr -d '\n' <"${LOCAL_APP_SLUG_FILE}")"
	INSTALL_URL="https://github.com/apps/${APP_SLUG}/installations/new"
fi

echo "Writing repository variable: ${CLIENT_ID_VAR_NAME}"
gh variable set "${CLIENT_ID_VAR_NAME}" \
	--repo "${OWNER}/${REPO}" \
	--body "${CLIENT_ID}"

echo "Writing repository variable: ${APP_ID_VAR_NAME}"
gh variable set "${APP_ID_VAR_NAME}" \
	--repo "${OWNER}/${REPO}" \
	--body "${APP_ID}"

echo "Writing repository secret: ${PRIVATE_KEY_SECRET_NAME}"
gh secret set "${PRIVATE_KEY_SECRET_NAME}" \
	--repo "${OWNER}/${REPO}" \
	<"${LOCAL_PRIVATE_KEY_FILE}"

echo
echo "Bootstrap complete."
echo "Target repo: ${OWNER}/${REPO}"
echo "Local files:"
echo "  ${LOCAL_APP_ID_FILE}"
echo "  ${LOCAL_CLIENT_ID_FILE}"
echo "  ${LOCAL_PRIVATE_KEY_FILE}"
if [[ -f "${LOCAL_APP_SLUG_FILE}" ]]; then
	echo "  ${LOCAL_APP_SLUG_FILE}"
fi
echo
echo "Repository values/secrets written:"
echo "  Variable: ${APP_ID_VAR_NAME}"
echo "  Variable: ${CLIENT_ID_VAR_NAME}"
echo "  Secret:   ${PRIVATE_KEY_SECRET_NAME}"
echo
echo "Next steps:"
if [[ -n "${INSTALL_URL}" ]]; then
	echo "1. Install the GitHub App on the target repo:"
	echo "   ${INSTALL_URL}"
	echo "   Select: ${OWNER}/${REPO}"
else
	echo "1. Install the GitHub App on the target repo."
fi
echo "2. Commit the workflow and config files below."
echo "3. Run the workflow manually once."
