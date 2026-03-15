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

**Say:** "It sounds like you want to generate an image. I can do that using the Gemini API. Let me walk you through the options."

If the user confirms, proceed. If not, stop.

**Tip:** You can also use `/gemini-image <description>` to generate images directly.

## 1. Check Prerequisites

Verify the environment:

```bash
echo "GEMINI_API_KEY set: $([ -n "$GEMINI_API_KEY" ] && echo 'yes' || echo 'no')"
which python3
```

If `GEMINI_API_KEY` is not set:

> `GEMINI_API_KEY` is not set. Get one at https://aistudio.google.com/apikey
> Then export it: `export GEMINI_API_KEY="your-key-here"`

Stop and wait for the user to set the key.

If `python3` is not available, inform the user that Python 3 is required.

## 2. Gather Image Details

Extract the image description from the user's request and confirm it.

### Model Selection

Ask the user which model to use:

| Model ID | Codename | Best For |
|----------|----------|----------|
| `gemini-3.1-flash-image-preview` | Nano Banana 2 | Fast, high-volume, newest **(Recommended)** |
| `gemini-3-pro-image-preview` | Nano Banana Pro | Highest quality, complex prompts |
| `gemini-2.5-flash-image` | Nano Banana | Stable, proven, low-latency |

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

### Image Resolution

Ask the user:

| Resolution | Notes |
|------------|-------|
| `1K` | Good quality, fast **(default)** |
| `2K` | Higher detail |
| `4K` | Maximum detail, slower |
| `512` | Only available on `gemini-3.1-flash-image-preview` |

Default: `1K`

### Reference Image (Optional)

Ask if they want to include a reference image (path to file). Default: no.

### Output Path

Ask or auto-generate a descriptive filename in the current directory (e.g., `hero-banner.png`, `coffee-logo.png`).

## 3. Build Request JSON

Use python3 to construct the request payload:

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

## 4. API Call

```bash
curl -s -X POST \
  "https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=$GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -d @${REQUEST_FILE} \
  > /tmp/gemini-image-response-${PID}.json
```

Check for errors — handle 429 (rate limit, wait 30s and retry), 400/403 (show error, suggest fixes).

## 5. Extract and Save Image

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
        import subprocess
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
            print(f"Could not convert to PNG, saved as JPEG: {output_path}")
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

## 6. Save Prompt File

Write a `{name}_prompt.txt` alongside the image:

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

## 7. Cleanup and Report

```bash
rm -f /tmp/gemini-image-request-*.json /tmp/gemini-image-response-*.json
```

Report:
- Image saved to: `{output_path}`
- Prompt saved to: `{prompt_file}`
- File size
- Any model notes from text parts

Ask: "Would you like to regenerate with different settings, adjust the prompt, or generate another image?"

## Error Handling

| Error | Action |
|-------|--------|
| Missing `GEMINI_API_KEY` | Link to https://aistudio.google.com/apikey |
| Missing `python3` | Inform user Python 3 is required |
| API 429 (rate limit) | Wait 30s and retry once |
| API 400 (bad request) | Show error, suggest simpler prompt |
| API 403 (forbidden) | Check API key, suggest regenerating |
| JPEG when PNG requested | Auto-convert: Pillow → magick → .jpg fallback |
| No image in response | Show model text, suggest rephrasing |
