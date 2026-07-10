# Gemini Image — Option Reference

Loaded by `SKILL.md` Step 2 when the agent needs full option matrices to ask
the user (or infer) model, aspect ratio, and resolution, or validate an
explicit service-tier request.

## Model Selection

| Model ID | Best For | Known Issues |
|----------|----------|--------------|
| `gemini-3.1-flash-image` | Best all-around balance of quality, cost, and latency **(Recommended)** | Flex and Priority tiers are not supported |
| `gemini-2.5-flash-image` | Legacy stable option for high-volume, low-latency work | Fixed 1K output; fewer aspect ratios |

Default: `gemini-3.1-flash-image`

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

**`gemini-3.1-flash-image`:** `1:1`, `1:4`, `1:8`, `2:3`, `3:2`, `3:4`, `4:1`, `4:3`, `4:5`, `5:4`, `8:1`, `9:16`, `16:9`, `21:9`

**`gemini-2.5-flash-image`:** `1:1`, `2:3`, `3:2`, `3:4`, `4:3`, `4:5`, `5:4`, `9:16`, `16:9`, `21:9`

## Image Resolution

| Model | Supported values | Default |
|-------|------------------|---------|
| `gemini-3.1-flash-image` | `512`, `1K`, `2K`, `4K` | `1K` |
| `gemini-2.5-flash-image` | Fixed 1K output | 1K |

> **Important:** `imageSize` values are **case-sensitive**. Use `"512"`, `"1K"`, `"2K"`, or `"4K"` exactly; lowercase values are rejected.

If the user selects `512`, `2K`, or `4K` with `gemini-2.5-flash-image`, warn them and use its fixed 1K output.

## Service Tier

Do not prompt for a service tier. Standard service is the default and omits
`serviceTier` from the request.

| Model | Flex | Priority | Request behavior |
|-------|------|----------|------------------|
| `gemini-3.1-flash-image` | Not supported | Not supported | Always omit `serviceTier` |
| `gemini-2.5-flash-image` | Supported | Supported | Emit lowercase `flex` or `priority` only when explicitly requested |

Store an explicitly supported tier as lowercase `GEMINI_SERVICE_TIER`. Use an
empty string for standard service or when the selected model does not support
the requested tier.
