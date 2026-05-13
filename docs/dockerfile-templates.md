# Dockerfile Templates

The `config/dockerfiles/` directory contains optional production app Dockerfile
templates for common language stacks. They use Debian-based builder images and
distroless nonroot runtime images so the final application container is small and
has a reduced vulnerability surface.

Minimal-CVE container work is a maintenance posture, not a permanent guarantee.
Keep the image selectors in `config/project.cfg`, refresh locks with
`make update`, and scan selected runtime images before release.

## Go

```sh
PROJECT_DOCKERFILE='config/dockerfiles/Dockerfile.go'
PROJECT_BUILD_TARGET='dev'
PROJECT_BUILD_COMMAND='cd src && go build -trimpath -buildvcs=false ./cmd/app'
PROJECT_LINT_COMMAND='cd src && test -z "$(gofmt -l .)" && go vet ./...'
PROJECT_TEST_COMMAND='cd src && go test -v ./... && go build -trimpath -buildvcs=false ./cmd/app'
PROJECT_RUN_COMMAND='cd src && go run ./cmd/app'
```

Build the production runtime image directly when you need the hardened artifact:

```sh
docker build --target runtime -f config/dockerfiles/Dockerfile.go -t app:runtime .
```

## Python

```sh
PROJECT_DOCKERFILE='config/dockerfiles/Dockerfile.python'
PROJECT_BUILD_TARGET='dev'
PROJECT_BUILD_COMMAND='python -m compileall -q src'
PROJECT_LINT_COMMAND='python -m compileall -q src'
PROJECT_TEST_COMMAND='if [ -d src/tests ]; then python -m unittest discover -s src/tests; else python -m compileall -q src; fi'
PROJECT_RUN_COMMAND='python -m app'
```

The Python runtime template expects an importable `app` module under `src/` and
optionally installs `src/requirements.txt`.

## Node.js

```sh
PROJECT_DOCKERFILE='config/dockerfiles/Dockerfile.node'
PROJECT_BUILD_TARGET='dev'
PROJECT_BUILD_COMMAND='cd src && if npm pkg get scripts.build | grep -qv "^{}$"; then npm run build; fi'
PROJECT_LINT_COMMAND='cd src && if npm pkg get scripts.lint | grep -qv "^{}$"; then npm run lint; fi'
PROJECT_TEST_COMMAND='cd src && if npm pkg get scripts.test | grep -qv "^{}$"; then npm test; fi'
PROJECT_RUN_COMMAND='cd src && npm start'
```

The Node.js runtime template expects the production entrypoint to be
`src/server.js`. Change the final `CMD` if the project uses a different file.

## Runtime Scanning

Set this in the selected project config to make `make scan` fail on
HIGH/CRITICAL vulnerabilities in the built image:

```sh
PROJECT_SCAN_IMAGE_VULNS=true
PROJECT_SCAN_IMAGE_TARGET='runtime'
```

Keep the default disabled for the template dev image because development
toolchains intentionally contain more packages than a production runtime image.
When enabled, `make scan` still uses the dev target for repository checks, then
builds `PROJECT_SCAN_IMAGE_TARGET` separately for the vulnerability scan.
