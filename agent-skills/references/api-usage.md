# Gopher Guides API Usage Reference

> **Privacy note:** API calls send source code or diff content to gopherguides.com for analysis. Ensure your organization permits external code analysis before using these endpoints.

## Authentication

All endpoints require `GOPHER_GUIDES_API_KEY`:

```bash
curl -s -H "Authorization: Bearer $GOPHER_GUIDES_API_KEY" \
  https://gopherguides.com/api/gopher-ai/me
```

## Endpoints

### Best Practices Query

```bash
curl -s -X POST \
  -H "Authorization: Bearer $GOPHER_GUIDES_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"topic": "error handling"}' \
  https://gopherguides.com/api/gopher-ai/practices
```

### Code Audit

```bash
curl -s -X POST \
  -H "Authorization: Bearer $GOPHER_GUIDES_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"code": "<go source>", "focus": "audit"}' \
  https://gopherguides.com/api/gopher-ai/audit
```

### Code Examples

```bash
curl -s -X POST \
  -H "Authorization: Bearer $GOPHER_GUIDES_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"topic": "table driven tests"}' \
  https://gopherguides.com/api/gopher-ai/examples
```

### PR/Diff Review

```bash
curl -s -X POST \
  -H "Authorization: Bearer $GOPHER_GUIDES_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"diff": "<unified diff>"}' \
  https://gopherguides.com/api/gopher-ai/review
```

## Response Format

All responses include:
- `content`: Formatted guidance from Gopher Guides training materials
- `sources`: Module references with similarity scores

## Full API Documentation

See [API Reference](../../docs/api/README.md) for detailed parameter documentation and response schemas.
