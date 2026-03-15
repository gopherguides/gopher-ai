---
argument-hint: "<description of image to generate>"
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

> `GEMINI_API_KEY` is not set. Get one at https://aistudio.google.com/apikey
> Then export it: `export GEMINI_API_KEY="your-key-here"`

Stop and wait for the user to set the key.

If `python3` is not available, inform the user that Python 3 is required for base64 encoding/decoding of image data.

## 2. Select Model

Ask the user which model to use:

| Model ID | Codename | Best For |
|----------|----------|----------|
| `gemini-3.1-flash-image-preview` | Nano Banana 2 | Fast, high-volume, newest **(Recommended)** |
| `gemini-3-pro-image-preview` | Nano Banana Pro | Highest quality, complex prompts |
| `gemini-2.5-flash-image` | Nano Banana | Stable, proven, low-latency |

Default: `gemini-3.1-flash-image-preview`

## 3. Select Aspect Ratio

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

## 4. Select Image Resolution

Ask the user which resolution to use:

| Resolution | Notes |
|------------|-------|
| `1K` | Good quality, fast **(default)** |
| `2K` | Higher detail |
| `4K` | Maximum detail, slower |
| `512` | Only available on `gemini-3.1-flash-image-preview` |

Default: `1K`

If user selects `512` with a model other than `gemini-3.1-flash-image-preview`, warn them and switch to `1K`.

## 5. Reference Image (Optional)

Ask the user: "Do you want to include a reference image? (path to file, or 'no')"

Default: No reference image.

If a path is provided, verify the file exists using `Read` tool. Supported formats: PNG, JPEG, WebP, GIF.

## 6. Output Path

Ask the user where to save the image, or auto-generate a descriptive filename in the current directory.

Suggested naming: `{descriptive-name}.png` (e.g., `mountain-sunset.png`, `coffee-shop-logo.png`)

## 7. Build Request JSON

Use python3 to construct the request payload. This handles base64 encoding of reference images which can be too large for shell.

**First, export the gathered values as environment variables** so the python3 script can read them:

```bash
export GEMINI_PROMPT="<the user's prompt from $ARGUMENTS>"
export GEMINI_MODEL="<selected model, e.g. gemini-3.1-flash-image-preview>"
export GEMINI_ASPECT_RATIO="<selected ratio, e.g. 1:1>"
export GEMINI_IMAGE_SIZE="<selected resolution, e.g. 1K>"
export GEMINI_REF_IMAGE="<path to reference image, or empty>"
export GEMINI_OUTPUT_PATH="<output file path from Step 6>"
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

## 8. API Call

Use the `REQUEST_FILE` path from Step 7 and the `GEMINI_MODEL` env var:

```bash
RESPONSE_FILE="/tmp/gemini-image-response-$$.json"
curl -s -X POST \
  "https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=$GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -d @"${REQUEST_FILE}" \
  > "$RESPONSE_FILE"
export GEMINI_RESPONSE_FILE="$RESPONSE_FILE"
```

Check for errors in the response:
- HTTP errors or empty response → show error, suggest simpler prompt
- `"error"` key in JSON → extract and display the error message
- Status 429 → rate limited, wait 30s and retry once
- Status 400/403 → show error details, suggest simplifying the prompt or checking the API key

## 9. Extract and Save Image

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

## 10. Save Prompt File

Write a `{name}_prompt.txt` file alongside the image for reproducibility:

```bash
cat > "${OUTPUT_DIR}/${IMAGE_NAME}_prompt.txt" << EOF
Prompt: ${PROMPT}
Model: ${MODEL}
Aspect Ratio: ${ASPECT_RATIO}
Resolution: ${IMAGE_SIZE}
Reference Image: ${REF_IMAGE_PATH:-none}
Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
```

## 11. Cleanup and Report

```bash
rm -f /tmp/gemini-image-request-*.json /tmp/gemini-image-response-*.json
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

## Notes

- All Gemini-generated images include a SynthID watermark (automatic, no opt-out)
- Thinking/reasoning is enabled by default on image models and cannot be disabled
- The API supports up to 14 reference images per request
- Response may include both text (reasoning) and image data in the `parts[]` array
- `responseModalities: ["TEXT", "IMAGE"]` allows the model to return reasoning alongside the image
