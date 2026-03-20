---
argument-hint: "<description of image to generate>"
description: "Generate images using Google Gemini AI"
allowed-tools: ["Bash", "Read", "AskUserQuestion"]
---

# Generate Image with Gemini

**If `$ARGUMENTS` is empty or not provided:**

Display usage information and ask for input:

This command generates images using the Google Gemini API or the Gemini CLI with the Nano Banana extension.

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

Verify the environment to determine available generation methods:

```bash
echo "GEMINI_API_KEY set: $([ -n "$GEMINI_API_KEY" ] && echo 'yes' || echo 'no')"
which python3 2>/dev/null && echo "python3: available" || echo "python3: not found"
which gemini 2>/dev/null && echo "gemini CLI: available" || echo "gemini CLI: not found"
if which gemini >/dev/null 2>&1; then
  gemini extensions list 2>/dev/null | grep -qi nanobanana && echo "Nano Banana extension: installed" || echo "Nano Banana extension: not installed"
fi
```

**Determine available methods:**

Both methods require a Gemini API key. The Nano Banana extension checks these env vars in order: `NANOBANANA_API_KEY`, `NANOBANANA_GEMINI_API_KEY`, `NANOBANANA_GOOGLE_API_KEY`, `GEMINI_API_KEY`, `GOOGLE_API_KEY`.

| Condition | Method Available |
|-----------|-----------------|
| `GEMINI_API_KEY` set + `python3` available | REST API (direct curl) |
| `gemini` CLI + Nano Banana extension + any API key env var set | Gemini CLI (Nano Banana) |

**If no API key is set at all**, show setup instructions and stop:

> Image generation requires a Gemini API key. Get one free at https://aistudio.google.com/apikey
>
> ```
> export GEMINI_API_KEY="your-key-here"
> ```
>
> **Optional:** Install the Gemini CLI + Nano Banana extension for richer image commands (batch generation, styles, icons, patterns, diagrams):
> ```
> npm install -g @google/gemini-cli
> gemini extensions install https://github.com/gemini-cli-extensions/nanobanana
> ```
> The extension uses `GEMINI_API_KEY` as a fallback, so no separate key is needed.

If `python3` is not available but `GEMINI_API_KEY` is set, inform the user that Python 3 is required for the REST API path and suggest the CLI path instead.

If the `gemini` CLI is installed but the Nano Banana extension is not, offer to install it:

> Nano Banana extension not found. Install it with:
> ```
> gemini extensions install https://github.com/gemini-cli-extensions/nanobanana
> ```

## 2. Select Generation Method

**If only ONE method is available**, auto-select it and inform the user:
- REST API only: "Using REST API (GEMINI_API_KEY + python3 detected)"
- CLI only: "Using Gemini CLI with Nano Banana extension"

**If BOTH methods are available**, ask the user:

| Method | Pros |
|--------|------|
| REST API **(default)** | Most reliable for aspect ratio and resolution settings |
| Gemini CLI (Nano Banana) | Richer commands: batch generation (`--count`), style variations (`--styles`), icons, patterns, diagrams, story sequences |

Default: REST API (more reliable for `imageConfig` parameters).

Store the selection as `GENERATION_METHOD` (either `rest_api` or `cli_nanobanana`).

## 3. Select Model

Ask the user which model to use:

| Model ID | Best For | Known Issues |
|----------|----------|--------------|
| `gemini-3.1-flash-image-preview` | Fast, high-volume, newest **(Recommended)** | `aspectRatio` may be ignored in edit/background operations |
| `gemini-2.5-flash-image` | Stable, proven, fewest bugs | Most reliable for `imageConfig` params |

Default: `gemini-3.1-flash-image-preview`

For the CLI path, model selection uses the `NANOBANANA_MODEL` env var (defaults to `gemini-3.1-flash-image-preview`).

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

## 8. Generate Image

### 8A. REST API Path

**If `GENERATION_METHOD` is `rest_api`:**

#### Build Request JSON

Use python3 to construct the request payload. This handles base64 encoding of reference images which can be too large for shell.

**First, export the gathered values as environment variables** so the python3 script can read them:

**Important:** Always single-quote user-provided values to prevent shell injection (quotes, backticks, `$` in prompts):

```bash
export GEMINI_PROMPT='<the user'"'"'s prompt from $ARGUMENTS — single-quote wrapped>'
export GEMINI_MODEL='<selected model, e.g. gemini-3.1-flash-image-preview>'
export GEMINI_ASPECT_RATIO='<selected ratio, e.g. 1:1>'
export GEMINI_IMAGE_SIZE='<selected resolution, e.g. 1K>'
export GEMINI_REF_IMAGE='<path to reference image, or empty>'
export GEMINI_OUTPUT_PATH='<output file path from Step 7>'
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

outfile = f"/tmp/gemini-image-request-{pid}.json"
with open(outfile, "w") as f:
    json.dump(payload, f)

print(outfile)
PYEOF
```

Capture the printed path as `REQUEST_FILE`. The python3 script prints the request file path to stdout.

#### API Call

Use the `REQUEST_FILE` path and the `GEMINI_MODEL` env var:

```bash
RESPONSE_FILE="/tmp/gemini-image-response-$$.json"
HTTP_STATUS=$(curl -s -o "$RESPONSE_FILE" -w "%{http_code}" -X POST \
  "https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=$GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -d @"${REQUEST_FILE}")
export GEMINI_RESPONSE_FILE="$RESPONSE_FILE"
echo "HTTP status: $HTTP_STATUS"
```

If `HTTP_STATUS` is 429, wait 30 seconds and retry the curl command once. If 400 or 403, display the error from the response body and suggest fixes. Only proceed if status is 200.

Check for errors in the response:
- HTTP errors or empty response → show error, suggest simpler prompt
- `"error"` key in JSON → extract and display the error message
- Status 429 → rate limited, wait 30s and retry once
- Status 400/403 → show error details, suggest simplifying the prompt or checking the API key

#### Extract and Save Image

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

### 8B. CLI Path (Nano Banana Extension)

**If `GENERATION_METHOD` is `cli_nanobanana`:**

> **Known issue (as of Gemini CLI v0.34.0 / Nano Banana v1.0.12):** The extension's MCP tools (`generate_image`, `edit_image`, etc.) may fail to register in the CLI with `Tool "generate_image" not found`. If this happens, fall back to the REST API path automatically and inform the user.

The Nano Banana extension runs as an MCP server inside the Gemini CLI, providing these tools: `generate_image`, `edit_image`, `restore_image`, `generate_icon`, `generate_pattern`, `generate_story`, `generate_diagram`.

The extension requires an API key. It also requires separate configuration via `gemini extensions config nanobanana "API Key"` — the `GEMINI_API_KEY` env var fallback in the source code may not be sufficient since the CLI checks extension settings before starting the MCP server.

#### Set Model (if not default)

If the user chose `gemini-2.5-flash-image` instead of the default:

```bash
export NANOBANANA_MODEL='gemini-2.5-flash-image'
```

#### Generate via Nano Banana

Export the API key if needed (the extension checks `GEMINI_API_KEY` as a fallback):

```bash
export GEMINI_PROMPT='<the user'"'"'s prompt — single-quote wrapped>'
export GEMINI_OUTPUT_PATH='<output file path from Step 7>'
```

**Simple generation:**

```bash
printf '/generate "%s"\n' "$GEMINI_PROMPT" | gemini 2>&1
```

**With batch/style options** (CLI path advantage):

```bash
# Multiple variations
printf '/generate "%s" --count=3 --preview\n' "$GEMINI_PROMPT" | gemini 2>&1

# Style variations
printf '/generate "%s" --styles="watercolor,oil-painting" --count=4\n' "$GEMINI_PROMPT" | gemini 2>&1
```

**Reference images** — use the `/edit` command:

```bash
printf '/edit %s "%s"\n' "$GEMINI_REF_IMAGE" "$GEMINI_PROMPT" | gemini 2>&1
```

**Image restoration:**

```bash
printf '/restore %s\n' "$GEMINI_REF_IMAGE" | gemini 2>&1
```

#### Locate and Move Output

The extension saves images to `./nanobanana-output/` with smart filenames. Move the output to the user's requested path:

```bash
NANOBANANA_DIR="./nanobanana-output"
GENERATED_FILE=$(ls -t "$NANOBANANA_DIR"/* 2>/dev/null | head -1)
if [ -n "$GENERATED_FILE" ]; then
  mv "$GENERATED_FILE" "$GEMINI_OUTPUT_PATH"
  echo "Saved to $GEMINI_OUTPUT_PATH"
  SIZE_KB=$(du -k "$GEMINI_OUTPUT_PATH" | cut -f1)
  echo "Size: ${SIZE_KB} KB"
else
  echo "No image was generated. Check gemini CLI output above for errors." >&2
fi
```

## 9. Save Prompt File

Write a `{name}_prompt.txt` file alongside the image for reproducibility:

```bash
PROMPT_FILE="${GEMINI_OUTPUT_PATH%.*}_prompt.txt"
cat > "$PROMPT_FILE" << EOF
Prompt: ${GEMINI_PROMPT}
Model: ${GEMINI_MODEL}
Generation Method: ${GENERATION_METHOD}
Aspect Ratio: ${GEMINI_ASPECT_RATIO}
Resolution: ${GEMINI_IMAGE_SIZE}
Reference Image: ${GEMINI_REF_IMAGE:-none}
Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
```

## 10. Cleanup and Report

```bash
rm -f "${REQUEST_FILE}" "${RESPONSE_FILE}"
```

Report to the user:
- Image saved to: `{output_path}`
- Prompt saved to: `{prompt_file}`
- File size
- Generation method used
- Any model notes/reasoning from the text parts

Then ask: "Would you like to regenerate with different settings, adjust the prompt, or generate another image?"

## Error Handling

| Error | Action |
|-------|--------|
| No API key set (any env var) | Link to https://aistudio.google.com/apikey, show both generation paths |
| Missing `python3` (REST API path only) | Suggest CLI path, or install Python 3 |
| API 429 (rate limit) | Wait 30s and retry once |
| API 400 (bad request) | Show error, suggest simpler prompt |
| API 403 (forbidden) | Check API key, suggest regenerating at aistudio |
| JPEG response when PNG requested | Auto-convert via Pillow → magick → save as .jpg fallback |
| No image in response | Show model's text response, suggest rephrasing |
| Reference image not found | Warn and proceed without it |
| Nano Banana extension not installed | Show install command: `gemini extensions install https://github.com/gemini-cli-extensions/nanobanana` |
| CLI generates no output | Check CLI output for errors, suggest REST API as fallback |
| `imageSize` lowercase value | Warn about case sensitivity before sending request |

## Notes

- All Gemini-generated images include a SynthID watermark (automatic, no opt-out)
- Thinking/reasoning is enabled by default on image models and cannot be disabled
- The API supports up to 14 reference images per request
- Response may include both text (reasoning) and image data in the `parts[]` array
- `responseModalities: ["TEXT", "IMAGE"]` allows the model to return reasoning alongside the image
- The Nano Banana extension provides additional commands beyond `/generate`: `/edit`, `/restore`, `/icon`, `/pattern`, `/story`, `/diagram`
- Extension API key fallback chain: `NANOBANANA_API_KEY` → `NANOBANANA_GEMINI_API_KEY` → `NANOBANANA_GOOGLE_API_KEY` → `GEMINI_API_KEY` → `GOOGLE_API_KEY`
- Extension model selection via `NANOBANANA_MODEL` env var (default: `gemini-3.1-flash-image-preview`)
