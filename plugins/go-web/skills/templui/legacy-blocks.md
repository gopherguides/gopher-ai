# Legacy templUI Pro blocks

Use after the user chooses to keep templUI v1 for the task, or when porting a legacy block to
shadcn-templ (then also read `v1-to-v2-migration.md`).

## Source

The 222 original templUI Pro blocks are frozen and licensed 0BSD. Gopher Guides mirrors the
upstream archive on the `templui-pro-blocks` branch of its goilerplate fork:

- Browse: https://github.com/gopherguides/goilerplate/tree/templui-pro-blocks
- Clone: `git clone --branch templui-pro-blocks --single-branch https://github.com/gopherguides/goilerplate.git templui-pro-blocks`
- Upstream announcement: https://github.com/axadrn/goilerplate/discussions/32

`PROVENANCE.md` on that branch records the archive checksum. Its first commit is the archive as
published; later commits (such as the templ v0.3.1100 bump) are Gopher Guides changes.

## Select blocks

Blocks live in `blocks/<category>/<category>_NNN.templ`. Categories include ecommerce, stats,
hero, blog, auth, ai, chat, account, sidebar, cta, pricing, testimonial, footer, feature, faq,
team, newsletter, navbar, notification, gallery, contact, table, search, profile, layout,
cookie, announcement, timeline, social, comparison, calendar, countdown, and state.

Read `blocks/AGENTS.md` first: it indexes every block with its category, use case, and a
one-line description. Then open only the relevant files. For a quick fix, compare the primary
block with one sibling; for new design work, read at least five blocks in the category, or the
whole category when it is small. Copy `.templ` sources only. `*_templ.go` files are generated
and are not committed on the branch.

## Adapt into a v1 project

The archive is self-contained: its blocks import the bundled v1 components as
`templui-pro-blocks/templui/components/<name>`. When copying a block:

1. Change the `package` clause to the destination package.
2. Rewrite each component import to the project's own v1 components: the module path
   (`github.com/templui/templui/components/<name>`) when the project imports the module, or the
   project's local `components/<name>` directory when it owns copies.
3. Make sure every imported component exists in the project. Install missing local copies with
   the v1 CLI (`templui-cli.md`).
4. Wire each interactive component's `Script()` into the layout head (`script-templates.md`).
5. Run templ generation, the Go build, and the CSS build, then preview interactive behavior.

To browse every block locally, clone the branch and run `task dev`, then open
http://localhost:7331/blocks. Read the branch's `Taskfile.yml` first: the archive's dev task
stops processes on ports 8090 and 7331.

Ensure the project uses `github.com/a-h/templ` v0.3.1100 or later before generating code.
