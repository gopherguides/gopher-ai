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

## Commands

| Command | Description |
|---------|-------------|
| `/create-go-project <name>` | Scaffold a new Go web app from scratch |
| `/convert-to-go-project` | Migrate Express/Django/Laravel/Next.js to Go |

## The Stack

- **Go + Echo v4** - Web framework
- **Templ** - Type-safe HTML templates
- **HTMX** - Server-driven interactivity
- **Alpine.js** - Client-side interactivity
- **Tailwind CSS v4** - Styling with dark mode
- **sqlc** - Type-safe SQL (no ORM)
- **goose** - Database migrations
- **Air** - Hot reload

## Default Deployment

Vercel + Neon PostgreSQL (free tier)

## Examples

```bash
# Create a new project
/create-go-project myapp

# Convert existing project to Go stack
/convert-to-go-project
```

## License

MIT - see [LICENSE](../../LICENSE)
