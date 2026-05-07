# Gemini Image — Option Reference

Loaded by `SKILL.md` Step 2 when the agent needs full option matrices to ask
the user (or infer) model, aspect ratio, resolution, and service tier.

## Model Selection

| Model ID | Best For | Known Issues |
|----------|----------|--------------|
| `gemini-3.1-flash-image-preview` | Fast, high-volume, newest **(Recommended)** | `aspectRatio` may be ignored in edit/background operations |
| `gemini-2.5-flash-image` | Stable, proven, fewest bugs | Most reliable for `imageConfig` params |

Default: `gemini-3.1-flash-image-preview`

## Aspect Ratio

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

## Image Resolution

| Resolution | Notes |
|------------|-------|
| `1K` | Good quality, fast **(default)** |
| `2K` | Higher detail |
| `4K` | Maximum detail, slower |
| `512` | Only available on `gemini-3.1-flash-image-preview` |

Default: `1K`

> **Important:** `imageSize` values are **case-sensitive**. Use `"1K"`, `"2K"`, `"4K"` exactly — lowercase (e.g., `"1k"`) silently falls back to 512px resolution.

If the user selects `512` with a model other than `gemini-3.1-flash-image-preview`, warn them and switch to `1K`.

## Service Tier

Infer from context when possible:

| Context Clue | Suggested Tier |
|--------------|----------------|
| "background", "batch", "non-urgent", "cheap" | `flex` (~50% cheaper, may queue 1-15 min) |
| "urgent", "production", "priority", "fast" | `priority` (~80% more, fastest) |
| No urgency clue | `standard` (default — omits field) |

Ask the user to confirm if inferred, or select if no context clue:

| Tier | Cost | Speed | Best For |
|------|------|-------|----------|
| `standard` | Normal pricing | Normal | Default behavior **(default)** |
| `flex` | **~50% cheaper** | May queue (1-15 min) | Background/batch work, non-urgent |
| `priority` | ~80% more | Fastest | Time-sensitive, production assets |

Store as `GEMINI_SERVICE_TIER`. Empty string for `standard` (field omitted from request).
