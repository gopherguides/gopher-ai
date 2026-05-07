# Gemini Image — Troubleshooting

Loaded by `SKILL.md` when the API call fails, returns no image, or hits a
known model quirk. Each row maps the symptom to the action.

## Error Triage

| Error | Action |
|-------|--------|
| Missing `GEMINI_API_KEY` | Link to https://aistudio.google.com/apikey |
| Missing `python3` | Inform user Python 3 is required |
| API 429 (rate limit) | Wait 30s and retry once |
| API 400 (bad request) | Show error, suggest simpler prompt |
| API 403 (forbidden) | Check API key, suggest regenerating |
| JPEG when PNG requested | Auto-convert: Pillow → magick → .jpg fallback (handled by parse block in `request-builder.md`) |
| No image in response | Show model text, suggest rephrasing |
| `imageSize` lowercase value | Warn about case sensitivity before sending request — see `reference.md` resolution table |
| Invalid service tier value | Warn user, show valid options (`flex`, `standard`, `priority`), ask again |

## JPEG → PNG Conversion Path

When the user asked for PNG but the model returned JPEG, the parse block in
`request-builder.md` tries three paths in order:

1. **Pillow** (`from PIL import Image`) — preferred, single Python import.
2. **ImageMagick** (`magick` binary) — used if Pillow isn't installed; writes
   a `.tmp.jpg` then converts.
3. **Fallback** — neither available: rewrite `output_path` to `.jpg` and save
   the raw JPEG bytes. Print a notice telling the user to install Pillow or
   ImageMagick if they need PNG.

This logic lives entirely in the parse block — there's no separate command
to run.

## Aspect Ratio Silently Ignored

On `gemini-3.1-flash-image-preview`, `aspectRatio` may be silently dropped
during edit / background-replacement operations (model bug). If aspect ratio
is critical for an edit, switch the user to `gemini-2.5-flash-image`.

## `imageSize` Case Sensitivity

`"1k"` (lowercase) silently falls back to 512px output even when you asked
for `"1K"`. Validate before sending:

```bash
case "$GEMINI_IMAGE_SIZE" in
  1K|2K|4K|512) ;;
  *) echo "Warning: imageSize must be one of 1K|2K|4K|512 (case-sensitive)"; exit 1 ;;
esac
```
