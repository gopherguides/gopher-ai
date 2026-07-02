# Gemini Image — Troubleshooting

Loaded by `SKILL.md` when the API call fails, returns no image, or hits a
known model quirk. Each row maps the symptom to the action.

## Error Triage

| Error | Action |
|-------|--------|
| Missing `GEMINI_API_KEY` | Link to https://aistudio.google.com/apikey |
| Missing `python3` | Inform user Python 3 is required |
| API 429 (rate limit) | Wait 30s and retry once |
| API 400 (bad request) | If the error mentions the model name or "not found", the model was likely retired — see "Model Not Found or Retired" below. Otherwise show error, suggest simpler prompt |
| API 403 (forbidden) | Check API key, suggest regenerating |
| API 404 (not found) | Model retired or renamed — see "Model Not Found or Retired" below |
| JPEG when PNG requested | Auto-convert: Pillow → magick → .jpg fallback (handled by parse block in `request-builder.md`) |
| No image in response | Show model text, suggest rephrasing |
| `imageSize` lowercase value | Warn about case sensitivity before sending request — see `reference.md` resolution table |
| Invalid service tier value | Warn user, show valid options (`flex`, `standard`, `priority`), ask again |

## Model Not Found or Retired

Google rotates Gemini model IDs (preview suffixes graduate, old versions are
retired). If a request fails with 404, or 400 with a model-related message,
discover the currently available image models directly from the API:

```bash
curl -s "https://generativelanguage.googleapis.com/v1beta/models?key=$GEMINI_API_KEY" \
  | jq -r '.models[] | select((.supportedGenerationMethods // []) | index("generateContent")) | select(.name | test("image")) | .name' \
  | sed 's|^models/||'
```

Then:

1. Pick the closest match to what the user selected (flash-tier for speed,
   non-preview for stability), confirm the choice with the user, re-export
   `GEMINI_MODEL`, and retry the request once.
2. Tell the user the model table in `reference.md` is out of date and offer to
   update it with the IDs the API just returned — that keeps the skill
   self-healing instead of rotting when Google renames models.

Do not run this discovery call preemptively on every invocation; it only pays
for itself when a request has actually failed.

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
