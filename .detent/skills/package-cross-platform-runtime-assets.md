---
name: package-cross-platform-runtime-assets
description: Place skill-referenced runtime helpers where Claude, Codex, and Gemini distributions all include them.
when_to_use: Use when a plugin skill adds or moves an executable helper, schema, template, or other non-Markdown runtime dependency.
---

# Package cross-platform runtime assets

Put reusable executable helpers under `plugins/<plugin>/scripts/`, not inside a
skill directory. Codex copies the complete plugin, while the Gemini builder
copies Markdown from skill directories and copies plugin-level runtime
directories such as `scripts`, `lib`, `templates`, and `assets`.

Reference the helper through `${CLAUDE_PLUGIN_ROOT}` so Gemini path rewriting
can map it to the installed extension root. Invoke non-executable assets through
their interpreter when appropriate, but preserve executable mode for shell
helpers to match plugin script conventions.

Validate both behavior and packaging:

1. Exercise the helper directly with a focused fixture.
2. Run `scripts/build-universal.sh` or `scripts/test-installation.sh`.
3. Confirm Gemini dependency-closure validation finds every rewritten local
   asset.
4. Confirm the installed Gemini extension can execute the helper-backed path.
5. Run the repository validation gate after the final asset location and skill
   references are committed.
