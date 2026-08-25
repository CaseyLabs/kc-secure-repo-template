# GitHub Agentic Workflows

This template includes one optional, manually dispatched GitHub Agentic
Workflow for advisory pull request review. It uses the GitHub Copilot engine;
it does not require OpenAI, Anthropic, Gemini, or another third-party model API.
The existing build, test, scan, Renovate, and release workflows remain the
authoritative deterministic controls.

GitHub Agentic Workflows is in public preview. Review upstream release notes,
the generated workflow, and authentication requirements before enabling it in a
derived repository.

## Included Files

- `.github/workflows/security-pr-review.md`
  - reviewed source for the workflow trigger, permissions, tools, safe outputs,
    and review instructions
- `.github/workflows/security-pr-review.lock.yml`
  - generated GitHub Actions workflow executed by GitHub
  - never edit this file by hand
- `.github/aw/actions-lock.json`
  - compiler cache for immutable GitHub Action pins
  - commit changes only after reviewing the resolved action and SHA
- `.github/aw/zizmor.yml`
  - limits the gh-aw-generated template-injection compatibility exception to
    the reviewer lockfile; hand-written workflows remain unconditionally scanned
- `.gitattributes`
  - identifies generated `.lock.yml` workflows to repository tooling

The current `gh aw init --engine copilot` command can create or update
`.gitattributes`, `.github/skills/agentic-workflows/SKILL.md`,
`.github/agents/agentic-workflows.md`,
`.github/workflows/copilot-setup-steps.yml`, `.github/mcp.json`, and
`.vscode/settings.json`. It can also generate an agentics maintenance workflow
when configured workflows use expiration. The skill, custom agent, Copilot
setup workflow, MCP configuration, editor settings, and maintenance workflow
are not needed to compile or run this focused reviewer, so this template omits
them. Keeping those files out avoids imposing an agent-authoring environment on
every repository created from the template. `gh aw init` does not configure the
Copilot inference secret.

## Security Boundaries

The reviewer is intentionally narrow:

- execution is manual and requires an explicit pull request number
- the agent job has only `contents: read` and `pull-requests: read`
- the only GitHub MCP operation is `pull_request_read` in the current repository
- shell, CLI proxy, external retrieval, and repository editing are disabled
- pull request text and changes are treated as untrusted instructions
- a separate safe-output job may submit at most one pull request review
- the only permitted review event is non-blocking `COMMENT`
- failure and incomplete-run issues are disabled, avoiding `issues: write`
- a second metadata read prevents reporting against a changed pull request head

The GitHub tool uses `min-integrity: none`. That is a deliberate tradeoff: a
security reviewer must be able to inspect pull requests from first-time and
unaffiliated contributors. It increases exposure to hostile prompt content, so
do not add shell access, broad MCP tools, automatic triggers, direct write
permissions, or additional safe outputs without a separate security review.

The generated workflow contains framework jobs with `pull-requests: write`.
That permission is isolated from the read-only agent and is required only for
the validated review safe output. Inspect the generated permissions whenever
the compiler or workflow source changes.

## Install And Compile

Use the reviewed compiler release recorded here. The current generated workflow
was compiled with `gh-aw` v0.86.2:

```sh
gh extension install github/gh-aw --pin v0.86.2
gh aw version
gh aw compile security-pr-review --verbose
```

If another version is already installed, remove or upgrade it explicitly before
compiling. Do not use `--approve` merely to bypass compiler safe-update checks.
Review new actions, containers, secrets, and permissions first.

Compilation is required after frontmatter changes. The Markdown instructions
are loaded at runtime, but compile after any source change in this repository so
reviewers can confirm there is no unexpected generated drift:

```sh
gh aw compile security-pr-review --verbose
git diff --exit-code -- .github/workflows/security-pr-review.lock.yml \
  .github/aw/actions-lock.json .gitattributes
```

For a deliberate compiler or action upgrade, review the upstream release, pin
the new version locally, refresh action pins with
`gh aw compile --force-refresh-action-pins`, and inspect the complete generated
diff. The current v0.86.2 CLI does not include the `gh aw update-actions`
command still shown on one upstream reference page. Keep Dependabot from
updating `github/gh-aw-actions` directly; the compiler owns those generated
references.

## Authentication For A Personal Repository

The checked-in workflow expects the repository Actions secret
`COPILOT_GITHUB_TOKEN`. Its value must be a fine-grained personal access token
owned by the user whose Copilot entitlement will be used.

The minimum credential permission is:

- account permission `Copilot Requests: Read`

The token does not need repository contents, issues, pull request, Actions, or
administration permissions. The token owner must have an active GitHub Copilot
license. Store it only as the repository Actions secret; never put it in a
tracked file, shell history, example, log, or command argument.

Create the secret in GitHub under **Settings > Secrets and variables > Actions**,
or use the interactive gh-aw secret command without placing the value on the
command line:

```sh
gh aw secrets set COPILOT_GITHUB_TOKEN
```

Do not run the reviewer until the secret and Copilot entitlement are present.
No additional repository write credential is required: the validated review is
posted with the job-scoped `GITHUB_TOKEN` permission generated by gh-aw.
After setting the secret, `gh aw doctor` can check the repository and
authentication prerequisites without dispatching the reviewer.

Organization-owned derived repositories with centralized Copilot billing can
instead add `copilot-requests: write` to the Markdown `permissions:` block,
remove the personal token secret, and recompile. Confirm the organization plan
and policy support that permission before making this change.

## Run A Review

After the source and generated workflow are present on the default branch and
authentication is configured, dispatch one review from the Actions UI or run:

```sh
gh aw run security-pr-review --raw-field pr_number=123 --ref main
```

Replace `123` with the pull request number and `main` with the repository's
default branch. The result is advisory. A successful agent review does not
replace required checks, deterministic scans, or human approval.

## Downstream Template Repositories

Repositories created from this template receive the workflow files but do not
inherit Actions secrets, Copilot entitlements, workflow history, or repository
settings. The workflow remains dormant until a maintainer configures
authentication and manually dispatches it.

During template customization:

- keep the workflow only if Copilot-backed review is wanted
- revise template-integrity guidance when the derived repository is no longer a
  generic template
- keep deterministic CI and security checks independent of agent availability
- reassess permissions and prompt scope before enabling automatic triggers
- compile with the reviewed gh-aw version and commit the generated files

## Removal

To remove the reviewer from a derived repository:

```sh
gh aw remove security-pr-review
```

Review the command's diff before committing. If removing it manually, delete
both workflow files. Remove `.github/aw/actions-lock.json` and `.gitattributes`
only when no other agentic workflow uses them. Delete the
`COPILOT_GITHUB_TOKEN` repository secret separately in GitHub if nothing else
needs it. Then run the normal workflow, security, and packaging checks.

## Verification Checklist

- compile with the pinned, reviewed gh-aw release
- compile a second time and confirm no generated drift
- inspect agent and safe-output job permissions in the `.lock.yml`
- confirm only `COMMENT` reviews are allowed and the review maximum is one
- confirm external Actions and containers are immutably pinned
- confirm the zizmor exception remains limited to compiler-owned lockfiles
- run `make test`, template and smoke test modes, `make scan`, and `make dist`
- inspect the complete diff and packaged template contents
- perform a live manual review only after the required secret is configured

## Upstream References

- [GitHub Agentic Workflows](https://github.github.com/gh-aw/)
- [CLI installation](https://github.github.com/gh-aw/setup/cli/)
- [Copilot authentication](https://github.github.com/gh-aw/reference/auth/)
- [Compilation and action locking](https://github.github.com/gh-aw/reference/compilation-process/)
- [Safe outputs](https://github.github.com/gh-aw/reference/safe-outputs/)
- [GitHub tool permissions](https://github.github.com/gh-aw/reference/permissions/)
