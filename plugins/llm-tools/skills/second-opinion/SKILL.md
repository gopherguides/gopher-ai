---
name: second-opinion
description: "Get a second LLM opinion via codex/gemini/ollama on architectural decisions, design trade-offs, library or framework choices, and security-sensitive code. Use when uncertain on a 'should I' call, want a sanity check before a high-stakes commit, or facing a contested code review. SKIP for routine questions where one model's answer is clearly sufficient."
---

# Second Opinion Skill

Proactively suggest getting another LLM's perspective when the situation warrants it.

## Trigger Conditions

Suggest a second opinion when you detect:

### 1. Architectural Decisions
- Choosing between design patterns (e.g., repository vs service layer)
- Database schema design decisions
- API design choices (REST vs GraphQL, versioning strategy)
- Service decomposition (monolith vs microservices)
- State management approaches

### 2. Complex Trade-offs
- Performance vs. readability
- Flexibility vs. simplicity
- DRY vs. explicit code
- Build vs. buy decisions
- Consistency vs. availability trade-offs

### 3. Critical Code Reviews
- Security-sensitive code (authentication, authorization, crypto)
- Performance-critical paths
- Complex algorithms or data structures
- Code handling financial transactions or PII
- Concurrency and threading logic

### 4. Explicit Requests (trigger words)
- "another perspective"
- "second opinion"
- "sanity check"
- "what do you think"
- "am I on the right track"
- "does this make sense"
- "is this a good approach"

## How to Suggest

A second opinion is most valuable from a different model family than the one
that wrote the code. Bind the active assistant surface before suggesting an
invocation.

## Codex

Offer only installed Codex skills:

- `$llm-tools:gemini <specific question>` asks Google Gemini. Explain that the
  prompt goes to a cloud provider and that adding code or repository context
  requires explicit confirmation.
- `$llm-tools:ollama <specific question>` asks an installed Ollama model. Its
  privacy boundary depends on the configured Ollama endpoint; the provider
  skill verifies loopback destinations or confirms a non-loopback transfer.

For security-sensitive or proprietary code, present Ollama only with that
endpoint check. For architectural decisions, offer either provider and let the
user choose; do not invoke one implicitly.

## Claude Code

Offer the command that fits the request:

- `/codex:review` gets OpenAI analysis through the official Codex Claude Code
  plugin when installed.
- `/llm-tools:codex review <scope>` uses the Codex CLI fallback when the
  official plugin is missing or declined.
- `/gemini <specific question>` asks Google Gemini.
- `/ollama <specific question>` asks a local model.
- `/llm-tools:review-loop --llm fable` requests a fresh-context Claude review.
- `/llm-compare <specific question>` compares multiple providers.

In Claude Code, prefer `/codex:review`, `/codex:adversarial-review`, or
`/codex:rescue` from `codex@openai-codex` when that official plugin is
installed. Keep scripted pipelines on the existing CLI flow.

For security-sensitive code, explicitly mention the local `/ollama` option.
For a focused challenge review, use `/codex:adversarial-review` when available.
For complex reasoning or rescue work, use `/codex:rescue` when available.

## When NOT to Suggest

Do not suggest second opinions when:
- User is actively implementing (don't interrupt flow)
- Task is simple/straightforward (typos, formatting, simple fixes)
- User has already made a firm decision
- User said "just do it" or similar
- It's routine code changes with clear requirements
- User previously declined suggestions in this session

## Privacy Consideration

Before sending code or repository context to a non-local provider, identify
the provider and the material that would leave the machine, then obtain
explicit confirmation. Never include secrets or unrelated files. Ollama is
local only when its effective `OLLAMA_HOST` is a verified loopback endpoint;
model downloads remain a separate user decision.
