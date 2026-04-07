---
argument-hint: "[--tier flex|standard|priority] <description of image to generate>"
description: "Generate images using Google Gemini AI"
allowed-tools: ["Bash", "Read", "AskUserQuestion"]
---

# Generate Image with Gemini

**If `$ARGUMENTS` is empty or not provided:**

Display usage information and ask for input:

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

Generate an image using the Gemini API with the prompt: $ARGUMENTS

## 1. Check Prerequisites

Verify the environment:

```bash
echo "GEMINI_API_KEY set: $([ -n "$GEMINI_API_KEY" ] && echo 'yes' || echo 'no')"
which python3
```

If `GEMINI_API_KEY` is not set, inform the user:

> `GEMINI_API_KEY` is not set. Get one free at https://aistudio.google.com/apikey
> Then export it: `export GEMINI_API_KEY="your-key-here"`

Stop and wait for the user to set the key.

If `python3` is not available, inform the user that Python 3 is required for base64 encoding/decoding of image data.

> **Note:** The Gemini CLI's Nano Banana extension (`gemini extensions install nanobanana`) was investigated as an alternative generation path, but it has a known MCP tool registration bug (Gemini CLI v0.34.0 / Nano Banana v1.0.12) where tools fail to load at runtime. Only the REST API is reliable for image generation at this time.

## 2. Select Model

Ask the user which model to use:

| Model ID | Best For | Known Issues |
|----------|----------|--------------|
| `gemini-3.1-flash-image-preview` | Fast, high-volume, newest **(Recommended)** | `aspectRatio` may be ignored in edit/background operations |
| `gemini-2.5-flash-image` | Stable, proven, fewest bugs | Most reliable for `imageConfig` params |

Default: `gemini-3.1-flash-image-preview`

## 3. Select Service Tier

First, check if `--tier` appears in `$ARGUMENTS` and extract + strip it:

```bash
# Detect if --tier flag is present at all
HAS_TIER=$(echo "$ARGUMENTS" | grep -q '\-\-tier' && echo "true" || echo "false")
# Extract the value (may be valid or invalid)
TIER_RAW=$(echo "$ARGUMENTS" | grep -oE '\-\-tier  *[^ ]+' | awk '{print $2}')
# Check if value is valid
TIER_VALID=$(echo "$TIER_RAW" | grep -qiE '^(flex|standard|priority)$' && echo "true" || echo "false")
# Strip --tier <value> from the prompt text regardless of validity
CLEAN_ARGS=$(echo "$ARGUMENTS" | sed 's/--tier  *[^ ]*//g' | sed 's/^  *//;s/  *$//')
```

**IMPORTANT:** Use `CLEAN_ARGS` (not `$ARGUMENTS`) as the image prompt from this point forward. The `--tier` flag text must not leak into `GEMINI_PROMPT`.

**If `HAS_TIER` is `true` and `TIER_VALID` is `true`:** Normalize `TIER_RAW` to uppercase (`FLEX`, `STANDARD`, or `PRIORITY`).

**If `HAS_TIER` is `true` but `TIER_VALID` is `false`:** Warn the user that the provided value is invalid and ask them to choose from: `flex`, `standard`, `priority`.

**If `HAS_TIER` is `false`**, ask the user:

> **Service Tier:** How should this request be prioritized?
>
> | Tier | Cost | Speed | Best For |
> |------|------|-------|----------|
> | `standard` | Normal pricing | Normal | Default behavior **(default)** |
> | `flex` | **~50% cheaper** | May queue (1-15 min) | Background/batch work, non-urgent |
> | `priority` | ~80% more | Fastest | Time-sensitive, production assets |
>
> Default: `standard`

Store the selected tier. If `standard` or no selection, set `GEMINI_SERVICE_TIER=""` (empty — the `serviceTier` field will be omitted from the API request, which gives Google's default behavior). Otherwise set to `FLEX` or `PRIORITY` (uppercase).

## 4. Select Aspect Ratio

Ask the user which aspect ratio to use:

**Common:**

| Ratio | Use Case |
|-------|----------|
| `1:1` | Square — social media, profile pics, icons **(default)** |
| `16:9` | Widescreen — hero images, banners, blog headers |
| `9:16` | Portrait — mobile, stories, vertical banners |
| `4:3` | Standard — presentations, thumbnails |
| `3:4` | Tall — posters, book covers |

**All supported ratios:** `1:1`, `1:4`, `1:8`, `2:3`, `3:2`, `3:4`, `4:1`, `4:3`, `4:5`, `5:4`, `8:1`, `9:16`, `16:9`, `21:9`

Default: `1:1`

> **Note:** On `gemini-3.1-flash-image-preview`, `aspectRatio` may be silently ignored during image editing or background replacement operations. If aspect ratio is critical for an edit operation, consider using `gemini-2.5-flash-image` instead.

## 5. Select Image Resolution

Ask the user which resolution to use:

| Resolution | Notes |
|------------|-------|
| `1K` | Good quality, fast **(default)** |
| `2K` | Higher detail |
| `4K` | Maximum detail, slower |
| `512` | Only available on `gemini-3.1-flash-image-preview` |

Default: `1K`

> **Important:** `imageSize` values are **case-sensitive**. Use `"1K"`, `"2K"`, `"4K"` exactly — lowercase (e.g., `"1k"`) silently falls back to 512px resolution.

If user selects `512` with a model other than `gemini-3.1-flash-image-preview`, warn them and switch to `1K`.

## 6. Reference Image (Optional)

Ask the user: "Do you want to include a reference image? (path to file, or 'no')"

Default: No reference image.

If a path is provided, verify the file exists using `Read` tool. Supported formats: PNG, JPEG, WebP, GIF.

## 7. Output Path

Ask the user where to save the image, or auto-generate a descriptive filename in the current directory.

Suggested naming: `{descriptive-name}.png` (e.g., `mountain-sunset.png`, `coffee-shop-logo.png`)

## 8. Build Request JSON

Use python3 to construct the request payload. This handles base64 encoding of reference images which can be too large for shell.

**First, export the gathered values as environment variables** so the python3 script can read them:

**Important:** Always single-quote user-provided values to prevent shell injection (quotes, backticks, `$` in prompts):

```bash
export GEMINI_PROMPT='<the user'"'"'s prompt from CLEAN_ARGS (NOT raw $ARGUMENTS) — single-quote wrapped>'
export GEMINI_MODEL='<selected model, e.g. gemini-3.1-flash-image-preview>'
export GEMINI_ASPECT_RATIO='<selected ratio, e.g. 1:1>'
export GEMINI_IMAGE_SIZE='<selected resolution, e.g. 1K>'
export GEMINI_REF_IMAGE='<path to reference image, or empty>'
export GEMINI_OUTPUT_PATH='<output file path from Step 7>'
export GEMINI_SERVICE_TIER='<selected tier: FLEX, PRIORITY, or empty for standard>'
```

Then run the builder:

```bash
python3 << 'PYEOF'
import json, base64, sys, os

prompt = os.environ.get("GEMINI_PROMPT", "")
model = os.environ.get("GEMINI_MODEL", "gemini-3.1-flash-image-preview")
aspect_ratio = os.environ.get("GEMINI_ASPECT_RATIO", "1:1")
image_size = os.environ.get("GEMINI_IMAGE_SIZE", "1K")
ref_image_path = os.environ.get("GEMINI_REF_IMAGE", "")
service_tier = os.environ.get("GEMINI_SERVICE_TIER", "")
pid = os.getpid()

parts = []

if ref_image_path and os.path.exists(ref_image_path):
    ext = ref_image_path.lower().rsplit(".", 1)[-1]
    mime_map = {"png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "webp": "image/webp", "gif": "image/gif"}
    mime = mime_map.get(ext, "image/png")
    with open(ref_image_path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    parts.append({"inlineData": {"mimeType": mime, "data": b64}})

parts.append({"text": prompt})

payload = {
    "contents": [{"parts": parts}],
    "generationConfig": {
        "responseModalities": ["TEXT", "IMAGE"],
        "imageConfig": {
            "aspectRatio": aspect_ratio
        }
    }
}

if image_size != "1K":
    payload["generationConfig"]["imageConfig"]["imageSize"] = image_size

if service_tier:
    payload["serviceTier"] = service_tier

outfile = f"/tmp/gemini-image-request-{pid}.json"
with open(outfile, "w") as f:
    json.dump(payload, f)

print(outfile)
PYEOF
```

Capture the printed path as `REQUEST_FILE`. The python3 script prints the request file path to stdout.

## 9. API Call

Use the `REQUEST_FILE` path from Step 8 and the `GEMINI_MODEL` env var:

```bash
RESPONSE_FILE="/tmp/gemini-image-response-$$.json"
HTTP_STATUS=$(curl -s -o "$RESPONSE_FILE" -w "%{http_code}" -X POST \
  "https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=$GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -d @"${REQUEST_FILE}")
export GEMINI_RESPONSE_FILE="$RESPONSE_FILE"
echo "HTTP status: $HTTP_STATUS"
```

If `HTTP_STATUS` is 429, wait 30 seconds and retry the curl command once. If 400 or 403, display the error from the response body and suggest fixes. Only proceed to Step 10 if status is 200.

Check for errors in the response:
- HTTP errors or empty response → show error, suggest simpler prompt
- `"error"` key in JSON → extract and display the error message
- Status 429 → rate limited, wait 30s and retry once
- Status 400/403 → show error details, suggest simplifying the prompt or checking the API key

## 10. Extract and Save Image

Use python3 to parse the response, find the image data, and save it:

```bash
python3 << 'PYEOF'
import json, base64, sys, os

response_file = os.environ.get("GEMINI_RESPONSE_FILE", "")
output_path = os.environ.get("GEMINI_OUTPUT_PATH", "output.png")

with open(response_file) as f:
    data = json.load(f)

if "error" in data:
    print(f"API Error: {data['error'].get('message', str(data['error']))}", file=sys.stderr)
    sys.exit(1)

candidates = data.get("candidates", [])
if not candidates:
    print("No candidates in response", file=sys.stderr)
    sys.exit(1)

parts = candidates[0].get("content", {}).get("parts", [])

text_parts = []
image_data = None
image_mime = None

for part in parts:
    if "text" in part:
        text_parts.append(part["text"])
    elif "inlineData" in part:
        image_data = part["inlineData"]["data"]
        image_mime = part["inlineData"].get("mimeType", "image/png")

if not image_data:
    print("No image data in response", file=sys.stderr)
    if text_parts:
        print(f"Model response: {' '.join(text_parts)}", file=sys.stderr)
    sys.exit(1)

raw_bytes = base64.b64decode(image_data)

if output_path.lower().endswith(".png") and image_mime == "image/jpeg":
    try:
        from PIL import Image
        import io
        img = Image.open(io.BytesIO(raw_bytes))
        img.save(output_path, "PNG")
        print(f"Converted JPEG→PNG and saved to {output_path}")
    except ImportError:
        import subprocess, shutil
        if shutil.which("magick"):
            tmp_jpg = output_path + ".tmp.jpg"
            with open(tmp_jpg, "wb") as f:
                f.write(raw_bytes)
            result = subprocess.run(["magick", tmp_jpg, output_path], capture_output=True)
            os.remove(tmp_jpg)
            if result.returncode == 0:
                print(f"Converted JPEG→PNG (magick) and saved to {output_path}")
            else:
                output_path = output_path.rsplit(".", 1)[0] + ".jpg"
                with open(output_path, "wb") as f:
                    f.write(raw_bytes)
                print(f"magick failed, saved as JPEG: {output_path}")
        else:
            output_path = output_path.rsplit(".", 1)[0] + ".jpg"
            with open(output_path, "wb") as f:
                f.write(raw_bytes)
            print(f"No PNG converter available (install Pillow or ImageMagick), saved as JPEG: {output_path}")
else:
    with open(output_path, "wb") as f:
        f.write(raw_bytes)
    print(f"Saved to {output_path}")

size_kb = os.path.getsize(output_path) / 1024
print(f"Size: {size_kb:.1f} KB")

if text_parts:
    print(f"Model notes: {' '.join(text_parts)}")
PYEOF
```

## 11. Save Prompt File

Write a `{name}_prompt.txt` file alongside the image for reproducibility:

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

## 12. Cleanup and Report

```bash
rm -f "${REQUEST_FILE}" "${RESPONSE_FILE}"
```

Report to the user:
- Image saved to: `{output_path}`
- Prompt saved to: `{prompt_file}`
- File size
- Any model notes/reasoning from the text parts

Then ask: "Would you like to regenerate with different settings, adjust the prompt, or generate another image?"

## Error Handling

| Error | Action |
|-------|--------|
| Missing `GEMINI_API_KEY` | Link to https://aistudio.google.com/apikey |
| Missing `python3` | Inform user Python 3 is required |
| API 429 (rate limit) | Wait 30s and retry once |
| API 400 (bad request) | Show error, suggest simpler prompt |
| API 403 (forbidden) | Check API key, suggest regenerating at aistudio |
| JPEG response when PNG requested | Auto-convert via Pillow → magick → save as .jpg fallback |
| No image in response | Show model's text response, suggest rephrasing |
| Reference image not found | Warn and proceed without it |
| `imageSize` lowercase value | Warn about case sensitivity before sending request |
| `--tier` with invalid value | Warn user, show valid options (`flex`, `standard`, `priority`), ask again |

## Notes

- All Gemini-generated images include a SynthID watermark (automatic, no opt-out)
- Thinking/reasoning is enabled by default on image models and cannot be disabled
- The API supports up to 14 reference images per request
- Response may include both text (reasoning) and image data in the `parts[]` array
- `responseModalities: ["TEXT", "IMAGE"]` allows the model to return reasoning alongside the image
