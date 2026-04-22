# Makefile
PROJECT_CFG_FILE ?= config/project.cfg
PROJECT_NAME ?= kc-secure-template-dev
PROJECT_IMAGE ?= $(PROJECT_NAME):local
TEST_MODE ?= src

# Dynamically generate Makefile commands
PHONY_TARGETS := $(shell awk '/^[[:alnum:]_-]+:([^=]|$$).*##(@internal)? / { sub(/:.*/, "", $$1); print $$1 }' $(lastword $(MAKEFILE_LIST)))
.PHONY: $(PHONY_TARGETS)

help: ##@show available options
	@printf '\nAvailable targets:\n\n'
	@awk 'BEGIN { FS = ":.*## " } /^[[:alnum:]_-]+:([^=]|$$).*## / { printf "  %-24s %s\n", $$1, $$2 }' $(lastword $(MAKEFILE_LIST))

build: ## builds the project as a dev container image
	sh scripts/build.sh "$(PROJECT_CFG_FILE)"

test: ## runs lint and tests for the selected test mode
	sh scripts/test.sh "$(TEST_MODE)" "$(PROJECT_CFG_FILE)"

run: ## runs the built src container
	sh scripts/run.sh "$(PROJECT_CFG_FILE)"

stop: ## stops the running src container
	sh scripts/stop.sh "$(PROJECT_CFG_FILE)"

status: ## shows the built image and running containers
	sh scripts/status.sh "$(PROJECT_CFG_FILE)"

logs: ## prints logs from running containers
	sh scripts/logs.sh "$(PROJECT_CFG_FILE)"

clean: ## removes artifacts, caches, and the local container image
	sh scripts/clean.sh "$(PROJECT_CFG_FILE)"

shell: ## opens an shell in the running container
	sh scripts/shell.sh "$(PROJECT_CFG_FILE)"

update: ## refreshes pinned SHA hashes
	sh scripts/update.sh "$(PROJECT_CFG_FILE)"

renovate: ## runs self-hosted Renovate for this repository
	sh scripts/renovate.sh "$(PROJECT_CFG_FILE)"

example: ## runs the bundled Hello World example project
	sh scripts/example.sh "$(PROJECT_CFG_FILE)"

k8s: ## validates, renders, and packages the bundled Kubernetes Helm chart
	sh scripts/k8s.sh "$(PROJECT_CFG_FILE)"

infra: ## builds/tests/plans the bundled infra workspace and applies it when APPLY=true
	sh scripts/infra.sh "$(PROJECT_CFG_FILE)"

scan: ## runs the template security scans and workflow checks
	sh scripts/scan.sh "$(PROJECT_CFG_FILE)"

dist: ## builds the template release artifacts and integrity outputs
	sh scripts/dist.sh "$(PROJECT_CFG_FILE)"
