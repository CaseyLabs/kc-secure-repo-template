# Makefile
PROJECT_ENV ?= project.env
PROJECT_NAME ?= kc-secure-template-dev
PROJECT_IMAGE ?= $(PROJECT_NAME):local

# Dynamically generate Makefile commands
PHONY_TARGETS := $(shell awk '/^[[:alnum:]_-]+:([^=]|$$).*##(@internal)? / { sub(/:.*/, "", $$1); print $$1 }' $(lastword $(MAKEFILE_LIST)))
.PHONY: $(PHONY_TARGETS)

help: ##@show available options
	@printf '\nAvailable targets:\n\n'
	@awk 'BEGIN { FS = ":.*## " } /^[[:alnum:]_-]+:([^=]|$$).*## / { printf "  %-24s %s\n", $$1, $$2 }' $(lastword $(MAKEFILE_LIST))

build: ## builds the project as a dev container image
	sh scripts/build.sh "$(PROJECT_ENV)"

test: ## runs lint and tests against the built src image
	sh scripts/test.sh "$(PROJECT_ENV)"

run: ## runs the built src container
	sh scripts/run.sh "$(PROJECT_ENV)"

stop: ## stops the running src container
	sh scripts/stop.sh "$(PROJECT_ENV)"

status: ## shows the built image and running containers
	sh scripts/status.sh "$(PROJECT_ENV)"

logs: ## prints logs from running containers
	sh scripts/logs.sh "$(PROJECT_ENV)"

clean: ## removes artifacts, caches, and the local container image
	sh scripts/clean.sh "$(PROJECT_ENV)"

shell: ## opens an shell in the running container
	sh scripts/shell.sh "$(PROJECT_ENV)"

update: ## refreshes pinned SHA hashes
	sh scripts/update.sh "$(PROJECT_ENV)"

example: ## runs the bundled Hello World example project
	sh scripts/example.sh "$(PROJECT_ENV)"

infra: ## builds/tests/plans the bundled infra workspace and applies it when APPLY=true
	sh scripts/infra.sh "$(PROJECT_ENV)"

scan: ## runs the template security scans and workflow checks
	sh scripts/scan.sh "$(PROJECT_ENV)"

dist: ## builds the template release artifacts and integrity outputs
	sh scripts/dist.sh "$(PROJECT_ENV)"
