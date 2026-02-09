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

| Plan | Requests/min | Requests/day |
|------|-------------|-------------|
| Free | 10 | 100 |
| Pro | 60 | 5,000 |
| Team | 120 | 20,000 |

Rate limit headers are included in every response:

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

## Proposed Endpoints (Phase 3)

> These endpoints are planned for future releases.

### `GET /api/gopher-ai/rules`

Get configurable rule sets with severity levels and categories.

**Request:**

```bash
curl -s -H "Authorization: Bearer $GOPHER_GUIDES_API_KEY" \
  https://gopherguides.com/api/gopher-ai/rules
```

**Response:**

```json
{
  "ok": true,
  "version": "2025.1",
  "categories": [
    {
      "name": "error-handling",
      "severity": "critical",
      "rules": [
        {
          "id": "errcheck",
          "description": "Check for unchecked errors",
          "severity": "critical",
          "configurable": true
        }
      ]
    }
  ]
}
```

---

### `POST /api/gopher-ai/analyze`

Submit a full project for comprehensive analysis (code + dependencies).

**Request:**

```bash
# Create project archive
tar -czf /tmp/project.tar.gz --exclude=vendor --exclude=.git .

# Submit for analysis
curl -s -X POST \
  -H "Authorization: Bearer $GOPHER_GUIDES_API_KEY" \
  -F "project=@/tmp/project.tar.gz" \
  -F "options={\"focus\":[\"all\"]}" \
  https://gopherguides.com/api/gopher-ai/analyze
```

**Parameters:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `project` | file | yes | `.tar.gz` archive of Go project |
| `options.focus` | array | no | Areas to analyze: `all`, `security`, `performance`, `best-practices` |
| `options.severity_config` | object | no | Custom severity overrides |

**Response:**

```json
{
  "ok": true,
  "analysis_id": "ana_xyz789",
  "status": "complete",
  "score": 72,
  "findings": [...],
  "dependencies": {
    "direct": 12,
    "indirect": 45,
    "outdated": 3,
    "vulnerable": 0
  },
  "coverage": {
    "overall": 68.5,
    "packages": [...]
  },
  "report_url": "https://gopherguides.com/reports/ana_xyz789"
}
```

---

### `GET /api/gopher-ai/metrics/{repo}`

Get quality metrics over time for a repository.

**Request:**

```bash
curl -s -H "Authorization: Bearer $GOPHER_GUIDES_API_KEY" \
  "https://gopherguides.com/api/gopher-ai/metrics/gopherguides%2Fgopher-ai?period=30d"
```

**Parameters:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `repo` | path | yes | Repository in `owner/name` format (URL-encoded) |
| `period` | query | no | Time period: `7d`, `30d` (default), `90d`, `1y` |

**Response:**

```json
{
  "ok": true,
  "repo": "gopherguides/gopher-ai",
  "period": "30d",
  "data_points": [
    {
      "date": "2025-02-01",
      "score": 72,
      "coverage": 68.5,
      "critical_findings": 2,
      "warning_findings": 8
    }
  ],
  "trend": "improving",
  "delta": "+5 score points"
}
```

---

### `POST /api/gopher-ai/metrics/report`

Submit audit results for tracking and trend analysis.

**Request:**

```bash
curl -s -X POST \
  -H "Authorization: Bearer $GOPHER_GUIDES_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "repo": "gopherguides/gopher-ai",
    "commit": "abc123",
    "score": 78,
    "coverage": 72.3,
    "findings": {
      "critical": 1,
      "warning": 5,
      "suggestion": 12
    }
  }' \
  https://gopherguides.com/api/gopher-ai/metrics/report
```

**Response:**

```json
{
  "ok": true,
  "report_id": "rpt_abc123",
  "trend": "improving",
  "previous_score": 72,
  "delta": "+6"
}
```

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

- **Agent Skills:** [`.github/skills/`](../../.github/skills/) — Copilot skills with built-in API integration
- **Helper Scripts:** [`.github/skills/scripts/`](../../.github/skills/scripts/) — Shell scripts for CI/CD
- **OpenAPI Spec:** [`openapi.yaml`](openapi.yaml) — Formal API specification

---

*Powered by [Gopher Guides](https://gopherguides.com) — the official Go training partner.*
