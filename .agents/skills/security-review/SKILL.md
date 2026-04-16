---
name: security-review
description: |
  Manual-only skill.

  Use ONLY when the user explicitly invokes:
  $security-review

  Never select this skill via semantic matching.
---

# Security Review

## Activation guard

If "$security-review" is NOT present in the user request:
- Exit immediately
- Do not analyze anything
- Do not load references

---

## Token policy

- Default: no reference files
- Load at most ONE reference file
- Only load references if strictly required
- Prefer repo evidence over general guidance
- Keep output concise and high-signal

---

## Modes

### Light mode (default)

Use for:
- narrow code paths
- quick checks
- implementation guidance

Rules:
- no references unless absolutely necessary
- only high-confidence findings
- minimal output

---

### Full review mode

Use ONLY if explicitly requested (e.g. “full security review”, “threat model”)

Rules:
- define scope first
- inspect repo before references
- load at most one reference initially

---

## Workflow

1. Identify scope (files, components, boundaries)
2. Locate:
   - entrypoints
   - auth boundaries
   - user input paths
   - sensitive data handling
3. Analyze only what is in scope
4. Escalate only if risk justifies it

---

## Priority risks

Focus on real, high-impact issues:

- auth / authorization flaws
- injection risks
- SSRF / request forgery
- unsafe parsing / deserialization
- file upload / path traversal
- secrets exposure
- tenant isolation failures
- insecure defaults

Ignore:
- style issues
- speculative edge cases
- generic checklists

---

## Output format

For each issue:

- Issue: what is wrong
- Location: where it is
- Impact: why it matters
- Abuse path: how it could be exploited
- Fix: smallest safe remediation

If no issues: say so clearly.

---

## Reference usage

Only if necessary, choose ONE:

- express / node backend
- nextjs
- react / frontend
- vue
- python (fastapi / django / flask)
- golang backend

If no strong match → use none

---

## Hard rules

- Only run when "$security-review" is present
- Never trigger implicitly
- Never scan entire repo unless explicitly asked
- Never load multiple references unless absolutely required
- Never inflate output with generic advice
