---
name: gemini-image
description: "Generate images via the Google Gemini API. Supports GA model selection, aspect ratios, resolutions (512/1K/2K/4K), batch generation, image editing. Trigger when user wants AI-generated visual output: image, picture, photo, graphic, illustration, banner, logo, icon, thumbnail, header, hero image. SKIP screenshot inspection or image analysis with no generation/edit request."
---

# Gemini Image Generation

You detected an image generation request. Confirm intent before proceeding.

**Say:** "It sounds like you want to generate an image. I can do that using the Gemini API. Let me walk you through the options."

If the user confirms, proceed. If not, stop.

**Tip:** You can also use `/gemini-image <description>` to generate images directly.

## 1. Check Prerequisites

```bash
echo "GEMINI_API_KEY set: $([ -n "$GEMINI_API_KEY" ] && echo 'yes' || echo 'no')"
which python3
```

If `GEMINI_API_KEY` is not set:

> `GEMINI_API_KEY` is not set. Get one free at https://aistudio.google.com/apikey
> Then export it: `export GEMINI_API_KEY="your-key-here"`

Stop and wait for the user to set the key. If `python3` is missing, inform the user Python 3 is required.

> **Note:** The Gemini CLI's Nano Banana extension was investigated as an alternative generation path, but it has a known MCP tool registration bug (Gemini CLI v0.34.0 / Nano Banana v1.0.12). The REST API is the only reliable path right now.

## 2. Gather Image Details

Extract the image description from the user's request and confirm it. Then collect (ask the user or infer from context):

- **Model** — pick from the model table in `reference.md` (it lists the current default and trade-offs)
- **Aspect ratio** — infer from "banner"/"avatar"/"vertical"/etc., default `1:1`
- **Resolution** — `1K` default; model-specific alternatives are listed in `reference.md`
- **Reference image** — optional path to an existing file
- **Output path** — auto-generate a descriptive filename in CWD if not given

Do not prompt for a service tier. If the user explicitly requests one, use the model support matrix in `reference.md`; omit unsupported settings.

For full option matrices, model trade-offs, the aspect-ratio inference table, and service-tier support — Read `reference.md`.

Export the gathered values as environment variables. **Always single-quote** user-provided values to prevent shell injection (quotes, backticks, `$`):

```bash
export GEMINI_PROMPT='<user image description, single-quote wrapped>'
export GEMINI_MODEL='<selected model from the reference.md table>'
export GEMINI_ASPECT_RATIO='<selected ratio, e.g. 1:1>'
export GEMINI_IMAGE_SIZE='<selected resolution, e.g. 1K>'
export GEMINI_REF_IMAGE='<reference image path, or empty>'
export GEMINI_OUTPUT_PATH='<output file path>'
export GEMINI_SERVICE_TIER='<flex, priority, or empty for standard/unsupported>'
```

## 3. Build Request JSON

Read `request-builder.md` and run the **build block**. It writes the request to `/tmp/gemini-image-request-<pid>.json` and prints the path. Capture as `REQUEST_FILE`.

## 4. API Call

```bash
RESPONSE_FILE="/tmp/gemini-image-response-$$.json"
HTTP_STATUS=$(curl -s -o "$RESPONSE_FILE" -w "%{http_code}" -X POST \
  "https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=$GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -d @"${REQUEST_FILE}")
export GEMINI_RESPONSE_FILE="$RESPONSE_FILE"
echo "HTTP status: $HTTP_STATUS"
```

If `HTTP_STATUS` is 429, wait 30s and retry once. If 400/403/404, see `troubleshooting.md` — a 404 (or 400 naming the model) usually means the model ID was retired; the "Model Not Found" section there shows how to discover current IDs and retry. Only proceed if 200.

## 5. Extract and Save Image

Read `request-builder.md` and run the **parse block**. It handles base64 decoding, JPEG→PNG conversion when needed, and writes to `GEMINI_OUTPUT_PATH`.

## 6. Save Prompt File

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

## 7. Cleanup and Report

```bash
rm -f "${REQUEST_FILE}" "${RESPONSE_FILE}"
```

Report:
- Image saved to: `{output_path}`
- Prompt saved to: `{prompt_file}`
- File size and any model notes from text parts

Ask: "Would you like to regenerate with different settings, adjust the prompt, or generate another image?"

## Error Handling

For HTTP errors, missing image data, JPEG-vs-PNG handling, lowercase `imageSize`, and invalid service-tier values — Read `troubleshooting.md`.

## Further Reading

- `reference.md` — model comparison, aspect-ratio inference, resolution/tier matrices
- `request-builder.md` — the Python build and parse blocks for steps 3 and 5
- `troubleshooting.md` — error triage and JPEG→PNG conversion paths
