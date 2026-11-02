---
name: goilerplate
description: "Generates new Go SaaS apps with goilerplate and updates or diagnoses generated apps. Use for goilerplate application workflows; skip component-only work (templui) and the separate create-go-project scaffold."
---

# goilerplate

Use the open-source v4 generator for requested goilerplate application work. It renders locally without an account or network access. The stack includes Go, templ, Tailwind and shadcn-templ, with HTMX, Datastar, SvelteKit or headless options and SQLite or PostgreSQL. Use `templui` for component-only work and `create-go-project` for that separate scaffold.

## New application

Confirm the requested stack and destination with the user. Install the CLI if needed:

```bash
go install github.com/axadrn/goilerplate/v4/cmd/goilerplate@latest
goilerplate version
goilerplate new --help
```

Inspect the installed version and help before generating; select options from the actual help rather than remembered flags. Run `goilerplate new` in a new directory, never over an existing application. The generator initializes Git and makes an initial commit: respect the workspace's Git and branch rules before running it. Read the generated `AGENTS.md` and README and run the project's documented checks.

## Existing application

Read its `AGENTS.md`, README, generator metadata and `go.mod`; inspect local changes and run `goilerplate doctor`. For a v4-generated app, inspect `goilerplate update --help`, use `goilerplate update`, and review its update branch and test the result before merging. Apps generated before v4 cannot use `update`: explain this and plan a manual migration with the user; do not run `new` over the app.

`github.com/templui/templui`, `.templui.json`, or goilerplate v1/v2 metadata indicates legacy usage. Ask before upgrading and agree on migration scope. If the private `templui-pro` skill is installed, defer legacy block work to it. A UI upgrade does not imply a full application migration.

Ensure `github.com/a-h/templ` and the templ generator are v0.3.1100 or later; earlier versions do not sanitize spread attributes and URLs in attributes. Upgrade older pins, regenerate, and rebuild.

## Upstream references

- Documentation: https://goilerplate.com/docs
- Documentation index: https://goilerplate.com/llms.txt
- Changelog: https://goilerplate.com/changelog
- Source: https://github.com/axadrn/goilerplate
