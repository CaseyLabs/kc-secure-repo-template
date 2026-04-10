---
name: security-review
description: Repository-grounded security review that combines threat modeling, abuse-path analysis, security best-practice review, and remediation guidance. Use when Codex is asked to threat model a codebase or path, produce a security review or security report, identify security weaknesses, suggest secure-by-default implementations, or improve a project’s security posture. Treat threat modeling as language and platform agnostic. Use bundled framework references when they match the stack, and otherwise fall back to broadly applicable security analysis. Do not trigger for general architecture summaries, non-security debugging, or routine code review.
---

# Security Review

Deliver security work that is specific to the repository and the user request. Ground architectural and code-level claims in repo evidence, keep assumptions explicit, and prioritize realistic abuse paths and high-impact weaknesses over generic checklists.

## Quick Start

1. Determine the requested mode:
   - Threat model for a repo or subpath
   - Best-practice security review
   - Secure-by-default implementation while writing code
   - Remediation after a security report
2. Identify the in-scope paths, runtime entrypoints, deployment assumptions, and internet exposure.
3. Detect all primary languages and frameworks in scope. For web apps, check both frontend and backend.
4. Load only the relevant reference files from `references/`.
5. Keep runtime behavior separate from CI, build, dev tooling, tests, and examples.

## Workflow

### 1. Build the system and technology model

- Identify how the project runs: server, CLI, library, worker, or mixed system.
- Find entrypoints, exposed interfaces, data stores, external integrations, privileged operations, and security-sensitive configuration.
- Detect the primary languages and frameworks used in scope.
- Do not claim components, flows, or controls without evidence.

### 2. Choose the review depth

- If the user asks for threat modeling, follow the repo-centric threat-model flow and use `references/prompt-template.md` as the output contract.
- If the user asks for a security review or best-practice report, perform a prioritized code and configuration review using the relevant language or framework references.
- If the user asks for implementation help, apply the same guidance proactively so new code is secure by default.
- If the user asks for fixes after a report, address one finding at a time and validate regressions carefully.

### 3. Load references selectively

- Threat-model helpers:
  - `references/prompt-template.md`
  - `references/security-controls-and-assets.md`
- Frontend security references:
  - `references/javascript-general-web-frontend-security.md`
  - `references/javascript-jquery-web-frontend-security.md`
  - `references/javascript-typescript-react-web-frontend-security.md`
  - `references/javascript-typescript-vue-web-frontend-security.md`
- Backend and server references:
  - `references/javascript-express-web-server-security.md`
  - `references/javascript-typescript-nextjs-web-server-security.md`
  - `references/python-django-web-server-security.md`
  - `references/python-fastapi-web-server-security.md`
  - `references/python-flask-web-server-security.md`
  - `references/golang-general-backend-security.md`
- Also load any matching `general` reference for the relevant stack when present.
- If no exact reference exists, continue with language- and platform-agnostic security analysis and make any coverage limitations explicit in reports.

### 4. Threat-modeling flow

When threat modeling:

1. Extract the system model from repository evidence.
2. Enumerate trust boundaries, assets, entrypoints, and attacker capabilities.
3. Generate concrete abuse paths tied to real components and data flows.
4. Prioritize using explicit likelihood and impact reasoning.
5. Summarize key assumptions and ask 1 to 3 targeted context questions before the final report.
6. Produce a concise Markdown report that closely follows `references/prompt-template.md`.
7. Write the final file as `<repo-or-dir-name>-threat-model.md`.

Prefer a small number of high-quality threats over a long generic list. Distinguish existing mitigations from recommended mitigations, and tie each recommendation to a concrete boundary, component, or entrypoint.

### 5. Best-practice review flow

When reviewing an existing codebase for security:

1. Inspect the repo to determine the languages and frameworks in scope.
2. Read every relevant reference file for those technologies, including both frontend and backend guidance when applicable.
3. Look for high-impact weaknesses first: authn/authz gaps, unsafe input handling, insecure deserialization or parsing, SSRF-capable fetch flows, secret exposure, privilege boundary failures, multi-tenant isolation issues, sensitive data leaks, weak session handling, unsafe file handling, and impactful DoS risk.
4. Respect documented project-specific overrides when they are intentional, but note them if they weaken security posture.
5. Avoid low-signal findings that depend on unrealistic attacker control or out-of-scope deployment assumptions.

### 6. Reporting and remediation

When producing a review report:

- Ask the user where to write the report when an output file is needed. If they do not care, choose a sensible repo-local Markdown filename and state where it was written.
- Start with a short executive summary.
- Organize findings by severity and urgency.
- Give each finding a numeric ID.
- Include file and line references for code-backed findings.
- For critical findings, include a one-sentence impact statement.
- Summarize the results to the user after writing the file.

When fixing findings:

- Fix one finding at a time unless the user requests batching.
- Favor secure defaults that match the existing project architecture.
- Consider second-order behavior changes before editing.
- Add only concise comments when they materially clarify the security reason for a change.
- Run the project’s existing tests, lint, formatters, and type checks when relevant.

## Security Review Rules

- Never output secrets. Redact them and describe only their presence and location.
- Be careful about reporting missing TLS or cookie `Secure` flags in local-development setups; account for actual deployment context before raising that as a finding.
- Avoid recommending HSTS unless the user explicitly needs that analysis and deployment ownership is clear.
- Do not overstate severity when attacker preconditions are unrealistic for the system’s real usage.
- Prefer public non-enumerable identifiers over incrementing IDs for internet-exposed resources when identifier guessing matters.

## Output Expectations

- Threat models should be concise, repo-grounded, and AppSec-oriented.
- Security review reports should be prioritized, actionable, and easy to fix incrementally.
- In all modes, anchor findings to evidence and keep assumptions visible.
