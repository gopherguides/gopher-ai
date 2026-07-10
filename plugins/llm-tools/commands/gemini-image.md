---
argument-hint: "[--tier flex|standard|priority] <description of image to generate>"
description: "Generate images using Google Gemini AI"
allowed-tools: ["Bash(curl:*)", "Bash(python3:*)", "Bash(echo:*)", "Bash(export:*)", "Bash(which:*)", "Bash(cat:*)", "Bash(rm:*)", "Read", "AskUserQuestion"]
---

# Generate Image with Gemini

**If `$ARGUMENTS` is empty or not provided:**

This command generates images using the Google Gemini API.

**Usage:** `/gemini-image <description of image to generate>`

**Examples:**

| Command | Description |
|---------|-------------|
| `/gemini-image a serene mountain landscape at sunset` | Nature scene |
| `/gemini-image minimalist logo for a coffee shop called "Bean There"` | Logo design |
| `/gemini-image hero image for a Go programming blog post` | Blog artwork |
| `/gemini-image redesign this logo` (with reference image) | Edit existing image |

Ask the user: "What image would you like to generate?"

---

**If `$ARGUMENTS` is provided:**

Generate an image using the Gemini API with the prompt: `$ARGUMENTS`.

## 1. Check Prerequisites

```bash
echo "GEMINI_API_KEY set: $([ -n "$GEMINI_API_KEY" ] && echo 'yes' || echo 'no')"
which python3
```

If `GEMINI_API_KEY` is not set:

> `GEMINI_API_KEY` is not set. Get one free at https://aistudio.google.com/apikey
> Then export it: `export GEMINI_API_KEY="your-key-here"`

Stop and wait for the user to set the key. If `python3` is missing, inform the user it's required.

> **Note:** The Gemini CLI's Nano Banana extension was investigated as an alternative path, but it has a known MCP tool registration bug (Gemini CLI v0.34.0 / Nano Banana v1.0.12). The REST API is the only reliable path right now.

## 2. Parse `--tier` flag

Detect, validate, and strip `--tier <value>`:

```bash
HAS_TIER=$(echo "$ARGUMENTS" | grep -q '\-\-tier' && echo "true" || echo "false")
TIER_RAW=$(echo "$ARGUMENTS" | grep -oE '\-\-tier  *[^ ]+' | awk '{print $2}')
TIER_VALID=$(echo "$TIER_RAW" | grep -qiE '^(flex|standard|priority)$' && echo "true" || echo "false")
CLEAN_ARGS=$(echo "$ARGUMENTS" | sed 's/--tier  *[^ ]*//g' | sed 's/^  *//;s/  *$//')
```

**IMPORTANT:** Use `CLEAN_ARGS` (not `$ARGUMENTS`) as the image prompt from this point forward. The `--tier` flag text must not leak into `GEMINI_PROMPT`.

If `HAS_TIER=true` AND `TIER_VALID=true` → lowercase `TIER_RAW` to `flex`/`standard`/`priority`.
If `HAS_TIER=true` AND `TIER_VALID=false` → warn the user; ask them to choose `flex`/`standard`/`priority`.
If `HAS_TIER=false` → continue with standard service. Do not prompt for a tier.

If `standard` (or no selection), set `GEMINI_SERVICE_TIER=""` (empty — `serviceTier` is omitted). Otherwise retain the lowercase tier until the model is selected in Step 3.

## 3. Gather Image Details

Ask the user (or infer from context) for:

- **Model** — `gemini-3.1-flash-image` (default) or `gemini-2.5-flash-image`
- **Aspect ratio** — default `1:1`; common: `16:9` (banner), `9:16` (mobile), `4:3`, `3:4`
- **Resolution** — `1K` (default); `512`, `2K`, and `4K` are also available on `gemini-3.1-flash-image`; `gemini-2.5-flash-image` only supports its fixed 1K output
- **Reference image** — optional path to PNG/JPEG/WebP/GIF
- **Output path** — auto-generate descriptive filename if not given

For full option matrices (all 14 aspect ratios, model trade-offs, resolution case-sensitivity warning) — Read `${CLAUDE_PLUGIN_ROOT}/skills/gemini-image/reference.md`.

After selecting the model, check the service-tier matrix in `reference.md`. `gemini-3.1-flash-image` does not support Flex or Priority, so warn if either was requested and set `GEMINI_SERVICE_TIER=""`. Only retain `flex` or `priority` for `gemini-2.5-flash-image`.

## 4. Build Request JSON

Export the gathered values as environment variables. **Always single-quote** user-provided values to prevent shell injection (quotes, backticks, `$` in prompts):

```bash
export GEMINI_PROMPT='<CLEAN_ARGS — single-quote wrapped, NOT raw $ARGUMENTS>'
export GEMINI_MODEL='<selected model>'
export GEMINI_ASPECT_RATIO='<selected ratio>'
export GEMINI_IMAGE_SIZE='<selected resolution>'
export GEMINI_REF_IMAGE='<reference path, or empty>'
export GEMINI_OUTPUT_PATH='<output file path>'
export GEMINI_SERVICE_TIER='<flex, priority, or empty for standard/unsupported>'
```

→ Read `${CLAUDE_PLUGIN_ROOT}/skills/gemini-image/request-builder.md` and run the **build block**. It writes the request to `/tmp/gemini-image-request-<pid>.json` and prints the path. Capture as `REQUEST_FILE`.

## 5. API Call

```bash
RESPONSE_FILE="/tmp/gemini-image-response-$$.json"
HTTP_STATUS=$(curl -s -o "$RESPONSE_FILE" -w "%{http_code}" -X POST \
  "https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=$GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -d @"${REQUEST_FILE}")
export GEMINI_RESPONSE_FILE="$RESPONSE_FILE"
echo "HTTP status: $HTTP_STATUS"
```

If `HTTP_STATUS` is 429, wait 30s and retry once. If 400/403, see `${CLAUDE_PLUGIN_ROOT}/skills/gemini-image/troubleshooting.md`. Only proceed if 200.

## 6. Extract and Save Image

→ Read `${CLAUDE_PLUGIN_ROOT}/skills/gemini-image/request-builder.md` and run the **parse block**. It handles base64 decoding, JPEG→PNG conversion when needed (Pillow → ImageMagick → fallback to .jpg), and writes to `GEMINI_OUTPUT_PATH`.

## 7. Save Prompt File

```bash
PROMPT_FILE="${GEMINI_OUTPUT_PATH%.*}_prompt.txt"
cat > "$PROMPT_FILE" << EOF
Prompt: ${GEMINI_PROMPT}
Model: ${GEMINI_MODEL}
Aspect Ratio: ${GEMINI_ASPECT_RATIO}
Resolution: ${GEMINI_IMAGE_SIZE}
Service Tier: ${GEMINI_SERVICE_TIER:-standard}
Reference Image: ${GEMINI_REF_IMAGE:-none}
Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
```

## 8. Cleanup and Report

```bash
rm -f "${REQUEST_FILE}" "${RESPONSE_FILE}"
```

Report:
- Image saved to: `{output_path}`
- Prompt saved to: `{prompt_file}`
- File size and any model notes from text parts

Ask: "Would you like to regenerate with different settings, adjust the prompt, or generate another image?"

## Error Handling

For HTTP errors, missing image data, JPEG-vs-PNG handling, lowercase `imageSize`, and invalid `--tier` values — Read `${CLAUDE_PLUGIN_ROOT}/skills/gemini-image/troubleshooting.md`.

## Notes

- All Gemini-generated images include a SynthID watermark (automatic, no opt-out)
- Thinking/reasoning is enabled by default on image models and cannot be disabled
- The API supports up to 14 reference images per request
- Response may include both text (reasoning) and image data in `parts[]`
- `responseModalities: ["TEXT", "IMAGE"]` allows the model to return reasoning alongside the image

## Further Reading

This command shares its option matrices, request-building Python, and error triage with the `gemini-image` skill (refactored in PR 1):

- `${CLAUDE_PLUGIN_ROOT}/skills/gemini-image/reference.md` — model comparison, full aspect-ratio table (14 ratios), resolution + tier matrices
- `${CLAUDE_PLUGIN_ROOT}/skills/gemini-image/request-builder.md` — Python build + parse blocks
- `${CLAUDE_PLUGIN_ROOT}/skills/gemini-image/troubleshooting.md` — error triage + JPEG→PNG conversion paths
