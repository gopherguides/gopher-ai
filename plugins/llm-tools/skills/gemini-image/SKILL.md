---
name: gemini-image
description: |
  WHEN: User asks to "generate an image", "create an image", "make a picture",
  "create a graphic", "generate artwork", "make an illustration", "create a visual",
  "generate a photo", "make a banner", "create a hero image", "generate a thumbnail",
  "make a logo", "create an icon", "I need an image", or similar image generation
  requests. Also trigger when user says "use Gemini to make", "AI-generated image",
  or "image for my blog/site/project".
  WHEN NOT: User is discussing image formats, image processing code, or asking about
  image generation conceptually. Do not trigger for screenshots, editing existing
  images, or when the user explicitly wants DALL-E, Midjourney, or Stable Diffusion.
---

# Gemini Image Generation

You detected an image generation request. Confirm intent before proceeding.

**Say:** "It sounds like you want to generate an image. I can do that using the Gemini API or the Gemini CLI with the Nano Banana extension. Let me walk you through the options."

If the user confirms, proceed. If not, stop.

**Tip:** You can also use `/gemini-image <description>` to generate images directly.

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

| Condition | Method Available |
|-----------|-----------------|
| `GEMINI_API_KEY` set + `python3` available | REST API |
| `gemini` CLI installed + Nano Banana extension installed | Gemini CLI (Nano Banana) |

**If NEITHER method is available**, show both setup options and stop:

> Image generation requires either:
> 1. **Gemini API key** (quickest setup): get one free at https://aistudio.google.com/apikey
>    ```
>    export GEMINI_API_KEY="your-key-here"
>    ```
> 2. **Gemini CLI + Nano Banana extension** (uses Google Sign-In, 10x free quota):
>    ```
>    npm install -g @google/gemini-cli
>    gemini  # follow login prompt
>    gemini extensions install https://github.com/gemini-cli-extensions/nanobanana
>    ```

If `python3` is not available but `GEMINI_API_KEY` is set, inform the user that Python 3 is required for the REST API path and suggest the CLI path instead.

If the `gemini` CLI is installed but the Nano Banana extension is not, offer to install it:

> Nano Banana extension not found. Install it with:
> ```
> gemini extensions install https://github.com/gemini-cli-extensions/nanobanana
> ```

## 1.5. Select Generation Method

**If only ONE method is available**, auto-select it and inform the user:
- REST API only: "Using REST API (GEMINI_API_KEY detected)"
- CLI only: "Using Gemini CLI with Nano Banana extension"

**If BOTH methods are available**, ask the user:

| Method | Pros |
|--------|------|
| REST API **(default)** | Most reliable for aspect ratio and resolution settings |
| Gemini CLI (Nano Banana) | Uses Google Sign-In auth (1,000 free req/day vs 100 for API key) |

Default: REST API (more reliable for `imageConfig` parameters).

Store the selection as `GENERATION_METHOD` (either `rest_api` or `cli_nanobanana`).

## 2. Gather Image Details

Extract the image description from the user's request and confirm it.

### Model Selection

Ask the user which model to use:

| Model ID | Best For | Known Issues |
|----------|----------|--------------|
| `gemini-3.1-flash-image-preview` | Fast, high-volume, newest **(Recommended)** | `aspectRatio` may be ignored in edit/background operations |
| `gemini-2.5-flash-image` | Stable, proven, fewest bugs | Most reliable for `imageConfig` params |

Default: `gemini-3.1-flash-image-preview`

### Aspect Ratio

Infer from context when possible, then confirm:

| Context Clue | Suggested Ratio |
|--------------|-----------------|
| "hero image", "banner", "header" | `16:9` |
| "profile pic", "avatar", "icon", "logo" | `1:1` |
| "story", "mobile", "vertical" | `9:16` |
| "poster", "book cover" | `3:4` |
| "presentation", "thumbnail" | `4:3` |
| "ultrawide", "cinematic" | `21:9` |

If no context clue, default to `1:1`.

**All supported ratios:** `1:1`, `1:4`, `1:8`, `2:3`, `3:2`, `3:4`, `4:1`, `4:3`, `4:5`, `5:4`, `8:1`, `9:16`, `16:9`, `21:9`

> **Note:** On `gemini-3.1-flash-image-preview`, `aspectRatio` may be silently ignored during image editing or background replacement operations. If aspect ratio is critical for an edit operation, consider using `gemini-2.5-flash-image` instead.

### Image Resolution

Ask the user:

| Resolution | Notes |
|------------|-------|
| `1K` | Good quality, fast **(default)** |
| `2K` | Higher detail |
| `4K` | Maximum detail, slower |
| `512` | Only available on `gemini-3.1-flash-image-preview` |

Default: `1K`

> **Important:** `imageSize` values are **case-sensitive**. Use `"1K"`, `"2K"`, `"4K"` exactly — lowercase (e.g., `"1k"`) silently falls back to 512px resolution.

If user selects `512` with a model other than `gemini-3.1-flash-image-preview`, warn them and switch to `1K`.

### Reference Image (Optional)

Ask if they want to include a reference image (path to file). Default: no.

### Output Path

Ask or auto-generate a descriptive filename in the current directory (e.g., `hero-banner.png`, `coffee-logo.png`).

## 3. Generate Image

### 3A. REST API Path

**If `GENERATION_METHOD` is `rest_api`:**

#### Build Request JSON

**First, export the gathered values as environment variables** so the python3 script can read them:

**Important:** Always single-quote user-provided values to prevent shell injection (quotes, backticks, `$` in prompts):

```bash
export GEMINI_PROMPT='<the user'"'"'s image description — single-quote wrapped>'
export GEMINI_MODEL='<selected model, e.g. gemini-3.1-flash-image-preview>'
export GEMINI_ASPECT_RATIO='<selected ratio, e.g. 1:1>'
export GEMINI_IMAGE_SIZE='<selected resolution, e.g. 1K>'
export GEMINI_REF_IMAGE='<path to reference image, or empty>'
export GEMINI_OUTPUT_PATH='<output file path>'
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

Capture the printed path as `REQUEST_FILE`.

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

If `HTTP_STATUS` is 429, wait 30s and retry once. If 400/403, show the error and suggest fixes. Only proceed if 200.

#### Extract and Save Image

Use python3 to parse the response and save:

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

### 3B. CLI Path (Nano Banana Extension)

**If `GENERATION_METHOD` is `cli_nanobanana`:**

#### Generate via Nano Banana

Export the gathered values, then run the Gemini CLI with the Nano Banana extension's `/generate` command:

**Important:** Always single-quote user-provided values to prevent shell injection:

```bash
export GEMINI_PROMPT='<the user'"'"'s image description — single-quote wrapped>'
export GEMINI_MODEL='<selected model, e.g. gemini-3.1-flash-image-preview>'
export GEMINI_ASPECT_RATIO='<selected ratio, e.g. 1:1>'
export GEMINI_IMAGE_SIZE='<selected resolution, e.g. 1K>'
export GEMINI_REF_IMAGE='<path to reference image, or empty>'
export GEMINI_OUTPUT_PATH='<output file path>'
```

```bash
NANOBANANA_DIR="./nanobanana-output"
mkdir -p "$NANOBANANA_DIR"

BEFORE_COUNT=$(ls "$NANOBANANA_DIR" 2>/dev/null | wc -l | tr -d ' ')

printf '/generate %s\n' "$GEMINI_PROMPT" | gemini 2>&1

AFTER_COUNT=$(ls "$NANOBANANA_DIR" 2>/dev/null | wc -l | tr -d ' ')
if [ "$AFTER_COUNT" -gt "$BEFORE_COUNT" ]; then
  GENERATED_FILE=$(ls -t "$NANOBANANA_DIR"/* 2>/dev/null | head -1)
  if [ -n "$GENERATED_FILE" ]; then
    mv "$GENERATED_FILE" "$GEMINI_OUTPUT_PATH"
    echo "Saved to $GEMINI_OUTPUT_PATH"
    SIZE_KB=$(du -k "$GEMINI_OUTPUT_PATH" | cut -f1)
    echo "Size: ${SIZE_KB} KB"
  fi
else
  echo "No image was generated. Check gemini CLI output above for errors." >&2
  echo "Tip: Try the REST API path instead (set GEMINI_API_KEY)." >&2
fi
```

If the Nano Banana extension supports aspect ratio and resolution flags, include them:

```bash
printf '/generate --aspect-ratio %s --size %s %s\n' "$GEMINI_ASPECT_RATIO" "$GEMINI_IMAGE_SIZE" "$GEMINI_PROMPT" | gemini 2>&1
```

**Reference images** with the CLI path: If a reference image was provided, use the `/edit` command instead:

```bash
printf '/edit --image %s %s\n' "$GEMINI_REF_IMAGE" "$GEMINI_PROMPT" | gemini 2>&1
```

## 4. Save Prompt File

Write a `{name}_prompt.txt` alongside the image:

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

## 5. Cleanup and Report

```bash
rm -f "${REQUEST_FILE}" "${RESPONSE_FILE}"
```

Report:
- Image saved to: `{output_path}`
- Prompt saved to: `{prompt_file}`
- File size
- Generation method used
- Any model notes from text parts

Ask: "Would you like to regenerate with different settings, adjust the prompt, or generate another image?"

## Error Handling

| Error | Action |
|-------|--------|
| No `GEMINI_API_KEY` AND no CLI + extension | Show both setup options (API key and CLI install instructions) |
| Missing `python3` (REST API path only) | Suggest CLI path, or install Python 3 |
| API 429 (rate limit) | Wait 30s and retry once |
| API 400 (bad request) | Show error, suggest simpler prompt |
| API 403 (forbidden) | Check API key, suggest regenerating |
| JPEG when PNG requested | Auto-convert: Pillow → magick → .jpg fallback |
| No image in response | Show model text, suggest rephrasing |
| Nano Banana extension not installed | Show install command: `gemini extensions install https://github.com/gemini-cli-extensions/nanobanana` |
| CLI generates no output | Check CLI output for errors, suggest REST API as fallback |
| `imageSize` lowercase value | Warn about case sensitivity before sending request |
