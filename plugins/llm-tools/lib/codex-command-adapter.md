# Codex Command Adapter

This adapter lets a Codex provider skill reuse the matching Claude Code command
body without maintaining a second workflow. Apply these rules before following
that body.

## Invocation Arguments

Bind the invocation text to `SKILL_ARGS` without evaluating it:

1. Preserve `SKILL_ARGS` when a parent workflow explicitly supplied it,
   including an explicitly empty value.
2. On Claude Code, bind the injected `$ARGUMENTS` value.
3. On Codex with an explicit invocation, find the exact qualified
   `$llm-tools:<skill-name>` token and bind only the text following that name.
4. Bind `SKILL_ARGS` to an empty string when no invocation text is present.

Treat every `$ARGUMENTS` or `${ARGUMENTS}` reference in the command body as a
reference to `SKILL_ARGS`. Preserve whitespace and never read arguments from a
shell environment variable.

## Plugin Resources

Resolve the concrete absolute plugin root once from the selected skill. Treat
every `$CLAUDE_PLUGIN_ROOT` or `${CLAUDE_PLUGIN_ROOT}` reference in the command
body as that concrete root. Replace notation before running a command or
reading a resource.

## Provider Boundary

Google Gemini is a cloud provider. Before invoking it, state that Google Gemini
will receive the prompt and identify every additional context source selected,
such as file contents, a diff, logs, or a session summary. Obtain explicit confirmation
after that disclosure whenever the payload includes code or other repository
data. An explicit skill invocation authorizes sending its attached prompt text
only; it does not authorize adding repository or session context. Never send
secrets, credentials, tokens, or unrelated files.

Before invoking Ollama, resolve the effective endpoint from `OLLAMA_HOST`,
using `http://127.0.0.1:11434` when the variable is unset. Parse the endpoint as
data without evaluating it. Treat only `localhost`, IPv4 addresses in
`127.0.0.0/8`, and the IPv6 address `::1` as local. For those loopback hosts,
state that the prompt stays on the machine.

For any other or unparseable host, do not repeat the command body's local-only
claims. Disclose the configured destination by scheme, host, and port, and
redact any credentials, tokens, query values, or paths.
Obtain explicit confirmation before sending the prompt or any context.
An explicit skill invocation does not authorize a non-loopback Ollama
transfer. Starting the Ollama server or downloading a model is a separate
state-changing action and still requires the command body's user decision.

## Surface Translation

On Codex:

- Replace `/gemini` suggestions with `$llm-tools:gemini`.
- Replace `/ollama` suggestions with `$llm-tools:ollama`.
- Omit suggestions for `/codex`, `/llm-compare`, or `/review-loop`; those
  Claude Code workflows are not Codex skills.
- Treat “Claude session” as the current Codex session and “Claude generates” as
  the current assistant generating the result.
- Never recommend a Claude Code slash command or the Claude-only
  `codex@openai-codex` plugin.

Use the active surface's native structured-input capability for required
choices. If it is unavailable, ask one concise question in the final response
and stop before the provider call. Do not infer consent from a default option.

## Provider Runner

Use this runner for prompt-only provider execution after the prerequisite,
model-selection, privacy, and consent gates have passed. For file, diff, or
session context, preserve the command body's input assembly and the same final
provider argument ordering.

```bash
llm_tools_run_provider() {
  local provider="${1:?provider is required}"
  local model="${2:-}"
  local prompt="${3:?prompt is required}"

  case "$provider" in
    gemini)
      if [ -n "$model" ]; then
        gemini "$prompt" -m "$model"
      else
        gemini "$prompt"
      fi
      ;;
    ollama)
      if [ -z "$model" ]; then
        printf 'Ollama model is required.\n' >&2
        return 2
      fi
      ollama run "$model" "$prompt"
      ;;
    *)
      printf 'Unsupported llm-tools provider: %s\n' "$provider" >&2
      return 2
      ;;
  esac
}
```

Do not replace an unavailable provider with another provider. Preserve the
command body's installation guidance, error handling, review-fix test fallback,
and follow-up behavior after translating its command names for Codex.
