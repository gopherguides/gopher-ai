# Gopher AI API Reference

REST API for Go code quality analysis, powered by [Gopher Guides](https://gopherguides.com) training materials.

**Base URL:** `https://gopherguides.com`

---

## Authentication

All endpoints require a Bearer token:

```
Authorization: Bearer $GOPHER_GUIDES_API_KEY
```

Get your API key at [gopherguides.com](https://gopherguides.com).

---

## Rate Limits

Rate limiting is enforced per API key. Check response headers (`X-RateLimit-Remaining`) for current limits.

```
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 58
X-RateLimit-Reset: 1707436800
```

When rate limited, the API returns `429 Too Many Requests`.

---

## Existing Endpoints

### `GET /api/gopher-ai/me`

Verify your API key and view account info.

**Request:**

```bash
curl -s -H "Authorization: Bearer $GOPHER_GUIDES_API_KEY" \
  https://gopherguides.com/api/gopher-ai/me
```

**Response:**

```json
{
  "ok": true,
  "user": {
    "id": "usr_abc123",
    "email": "dev@example.com",
    "plan": "pro",
    "requests_today": 42,
    "requests_limit": 5000
  }
}
```

---

### `POST /api/gopher-ai/practices`

Get prescriptive best-practice guidance on a Go topic.

**Request:**

```bash
curl -s -X POST \
  -H "Authorization: Bearer $GOPHER_GUIDES_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"topic": "error handling"}' \
  https://gopherguides.com/api/gopher-ai/practices
```

**Claude Code syntax:**

```
Run: curl -s -X POST -H "Authorization: Bearer $GOPHER_GUIDES_API_KEY" -H "Content-Type: application/json" -d '{"topic": "error handling"}' https://gopherguides.com/api/gopher-ai/practices
```

**Parameters:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `topic` | string | yes | Go topic (e.g., "error handling", "concurrency", "project structure") |
| `level` | string | no | Detail level: `brief`, `standard` (default), `detailed` |

**Response:**

```json
{
  "ok": true,
  "topic": "error handling",
  "practices": [
    {
      "title": "Always wrap errors with context",
      "description": "Use fmt.Errorf with %w to preserve the error chain...",
      "severity": "critical",
      "example": "fmt.Errorf(\"failed to create user: %w\", err)",
      "references": ["https://go.dev/blog/go1.13-errors"]
    }
  ]
}
```

---

### `POST /api/gopher-ai/audit`

Submit Go code for expert-level quality audit.

**Request:**

```bash
curl -s -X POST \
  -H "Authorization: Bearer $GOPHER_GUIDES_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"code": "package main\n\nfunc main() {\n\tos.Remove(\"tmp\")\n}", "focus": "audit"}' \
  https://gopherguides.com/api/gopher-ai/audit
```

**Parameters:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `code` | string | yes | Go source code to audit |
| `focus` | string | no | Focus area: `audit` (default), `security`, `performance`, `concurrency` |
| `severity_config` | object | no | Override default severity levels (see severity.yaml) |

**Response:**

```json
{
  "ok": true,
  "findings": [
    {
      "severity": "critical",
      "category": "error-handling",
      "title": "Unchecked error from os.Remove",
      "file": "main.go",
      "line": 4,
      "description": "The error return value of os.Remove is not checked.",
      "fix": "if err := os.Remove(\"tmp\"); err != nil { ... }"
    }
  ],
  "score": 35,
  "summary": "1 critical issue found. Error handling needs improvement."
}
```

---

### `POST /api/gopher-ai/examples`

Get code examples for specific Go patterns.

**Request:**

```bash
curl -s -X POST \
  -H "Authorization: Bearer $GOPHER_GUIDES_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"topic": "functional options pattern"}' \
  https://gopherguides.com/api/gopher-ai/examples
```

**Parameters:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `topic` | string | yes | Pattern or concept to get examples for |
| `complexity` | string | no | `basic`, `intermediate` (default), `advanced` |

**Response:**

```json
{
  "ok": true,
  "topic": "functional options pattern",
  "examples": [
    {
      "title": "Server with functional options",
      "code": "type Option func(*Server) { ... }",
      "explanation": "Functional options provide a clean API for configurable types..."
    }
  ]
}
```

---

### `POST /api/gopher-ai/review`

Review a PR diff against Gopher Guides standards.

**Request:**

```bash
DIFF=$(git diff main...HEAD)
curl -s -X POST \
  -H "Authorization: Bearer $GOPHER_GUIDES_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"diff\": $(echo "$DIFF" | jq -Rs .)}" \
  https://gopherguides.com/api/gopher-ai/review
```

**Parameters:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `diff` | string | yes | Unified diff content |
| `context` | string | no | Additional context about the PR |
| `severity_config` | object | no | Override severity levels |

**Response:**

```json
{
  "ok": true,
  "score": 78,
  "recommendation": "COMMENT",
  "comments": [
    {
      "file": "handler.go",
      "line": 42,
      "severity": "warning",
      "body": "Consider wrapping this error with context: fmt.Errorf(\"handle request: %w\", err)"
    }
  ],
  "breaking_changes": [],
  "summary": "Good overall. 2 warnings around error handling."
}
```

---

## Proposed Endpoints (Not Yet Implemented)

> **These endpoints are planned for future releases. Do not depend on them in production.**
> See [`openapi-proposed.yaml`](openapi-proposed.yaml) for the draft specification.

---

## Error Responses

All errors follow this format:

```json
{
  "ok": false,
  "error": {
    "code": "invalid_api_key",
    "message": "The provided API key is invalid or expired."
  }
}
```

| HTTP Code | Error Code | Description |
|-----------|-----------|-------------|
| 401 | `invalid_api_key` | Invalid or expired API key |
| 403 | `plan_limit` | Feature not available on your plan |
| 404 | `not_found` | Endpoint or resource not found |
| 422 | `validation_error` | Invalid request parameters |
| 429 | `rate_limited` | Too many requests |
| 500 | `internal_error` | Server error — retry later |

---

## SDKs & Integration

- **Agent Skills:** [`agent-skills/`](../../agent-skills/) — GitHub Copilot skills with built-in API integration
- **Helper Scripts:** [`agent-skills/scripts/`](../../agent-skills/scripts/) — Shell scripts for CI/CD
- **OpenAPI Spec:** [`openapi.yaml`](openapi.yaml) — Formal API specification

---

*Powered by [Gopher Guides](https://gopherguides.com) — the official Go training partner.*
