# go-web

Opinionated Go web app scaffolding with our recommended stack.

## Installation

```bash
/plugin install go-web@gopher-ai
```

Or install via marketplace:
```bash
/plugin marketplace add gopherguides/gopher-ai
```

## Claude Code Commands

| Command | Description |
|---------|-------------|
| `/create-go-project <name>` | Scaffold a new Go web app from scratch |
| `/convert-to-go-project [target-directory]` | Convert the current or specified project to Go |

## Codex Skills

Codex exposes these skills under the `go-web` plugin. Use the qualified name
shown below to invoke project conversion explicitly; all three skills can also
activate automatically when their guidance applies.

| Skill | Invocation | Description |
|-------|------------|-------------|
| `go-web:convert-to-go-project` | `$go-web:convert-to-go-project [target-directory]` | Convert an existing project to the recommended Go web stack |
| `go-web:templui` | Auto-invoked | templUI components, interpolation, and Script() requirements |
| `go-web:htmx` | Auto-invoked | HTMX attributes, swap patterns, and Go handler integration |

Project conversion supports Express and Fastify, Django, Flask, and FastAPI,
Laravel and other PHP projects, Next.js and React, and existing Go projects
that should be extended rather than replaced.

## The Stack

- **Go + Echo v4** - Web framework
- **Templ** - Type-safe HTML templates
- **HTMX** - Server-driven interactivity (AJAX, partial updates)
- **Alpine.js** - Client-side state and reactivity
- **templUI** - UI components (uses vanilla JS via Script() templates)
- **Tailwind CSS v4** - Styling with dark mode
- **sqlc** - Type-safe SQL (no ORM)
- **goose** - Database migrations
- **Air** - Hot reload

## Default Deployment

Vercel + Neon PostgreSQL (free tier)

## Examples

```text
# Claude Code: create a new project
/create-go-project myapp

# Claude Code: convert an existing project
/convert-to-go-project ./my-project

# Codex: convert an existing project
$go-web:convert-to-go-project ./my-project
```

## License

MIT - see [LICENSE](../../LICENSE)
