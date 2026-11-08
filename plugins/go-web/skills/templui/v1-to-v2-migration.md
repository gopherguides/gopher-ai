# Migrating templUI v1 to shadcn-templ v2

Use after the user approves an upgrade (see the upgrade question in `SKILL.md`). shadcn-templ v2
is the templUI 2.0 rewrite: every component was rebuilt against shadcn/ui and Base UI, so it is
a new API rather than a version bump. Treat the prop notes below as a starting map and confirm
each one against the installed component source, because v2 is still in beta and moves quickly.

## Decide the scope first

- **UI-only:** replace components and call sites; leave routing, auth, data, and the frontend
  runtime (htmx, Datastar, Alpine) alone. This is the usual case.
- **Full application:** regenerating with goilerplate is a separate decision; use the
  `go-web:goilerplate` skill and never run a generator over an existing app.

Inventory the project before editing: v1 component imports (module
`github.com/templui/templui/components/...` or local `components/...`), `.templui.json`, every
`@<name>.Script()` call in layouts, custom CSS variables, and copied legacy blocks. Present the
list and agree on which pages move. Migrate one component family at a time, each with its call
sites, in an isolated checkout.

## Swap the toolchain

1. Install the CLI from the reviewed v2 release:
   `go install github.com/axadrn/shadcn-templ/v2/cmd/shadcn-templ@latest`
2. Run `shadcn-templ init` with the project's real CSS entry. It writes `components.json`,
   merges theme variables into `assets/css/globals.css` (or the detected entry), vendors
   `tw-animate.css` and `shadcn-tailwind.css`, and installs the `utils` package.
3. Add components as each family migrates: `shadcn-templ add button dialog ...`, then
   `go tool templ generate` and `go mod tidy`.
4. Remove `.templui.json` and the v1 component directory or module requirement only after the
   last v1 import is gone. Mixed v1 and v2 packages with the same names will collide.

## Replace the JavaScript wiring

v1 renders one `Script()` template per interactive component in the layout head. v2 ships all
behavior as one bundle:

- Delete every `@<component>.Script()` call from layouts.
- Render `@components.Scripts()` once in `<head>` (import the project's `components` package).
- The CLI writes `assets/js/shadcn-templ-<hash>.js` and `components/scripts_bundle.go`. Commit
  `scripts_bundle.go`; ignore the generated JS like `output.css`. Serve `/assets/` with the
  other static files.
- Add `go tool shadcn-templ bundle --watch` to the dev task and `go tool shadcn-templ bundle`
  to the production build, before `templ generate`.

v2 scripts observe the DOM, so htmx and Alpine swaps need no extra wiring. Overlays move to
`<body>` while open; swap a fragment that renders an overlay already open into a dedicated
target, or its `hx-*` attributes can be missed.

## Replace the styling model

v2 components carry `cn-*` classes, and a style class on `<body>` selects one of eight visual
styles (`style-nova` by default; see `components.json`). Import the matching `style-<name>.css`
in the Tailwind build and put the class on `<body>`. Theme tokens are shadcn/ui semantic pairs
(`--primary` / `--primary-foreground`, and so on) under `:root` and `.dark`. Map custom v1
colors to those tokens instead of editing component classes.

## Component renames

| v1 | v2 |
|---|---|
| `dropdown` | `dropdownmenu` |
| `selectbox` | `select` (styled) or `nativeselect` |
| `radio` | `radiogroup` |
| `form` | `field` |
| `datepicker`, `timepicker`, `rating`, `tagsinput` | no v2 equivalent: keep a v1 copy, build on `calendar`/`popover`, or drop |

New in v2 with no v1 counterpart: alertdialog, combobox, command, contextmenu, drawer, empty,
inputgroup, item, kbd, menubar, navigationmenu, resizable, scrollarea, spinner, toggle,
togglegroup, buttongroup.

## Triggers and closes are attribute functions

v1 has `Trigger` and `Close` components with a `For` prop. v2 removes them: spread attributes
onto your own element instead.

```templ
@dialog.Dialog() {
	@button.Button(button.Props{Attributes: dialog.Trigger(ctx)}) {
		Open
	}
	@dialog.Content() {
		@dialog.Header() {
			@dialog.Title() { Title }
		}
		@button.Button(button.Props{Attributes: dialog.Close(ctx)}) {
			Close
		}
	}
}
```

- `dialog`, `sheet`: `Trigger(ctx)`, `Close(ctx)`; external controls use `TriggerFor(id)` and
  `CloseFor(id)` in place of v1's `For` prop.
- `popover`, `tooltip`, `hovercard`, `collapsible`: `Trigger(ctx)`.

## Prop changes in shared components

State props move to controlled/uncontrolled pairs: v1 `Open` becomes `DefaultOpen` (initial) or
`Open` (controlled); dismissal flags become `DisablePointerDismissal`; positioning uses
`Side`, `SideOffset`, `Align`, `AlignOffset` instead of `Placement`, `Position`, `Offset`.

- `button`: `FullWidth` removed (use `Class: "w-full"`); sizes add `xs`, `icon-xs`, `icon-sm`, `icon-lg`.
- `dialog`: root loses `Class`, `Attributes`, `DisableClickAway`, `DisableESC`; gains
  `DefaultOpen`, `DisablePointerDismissal`. `ContentProps.DisableModal` becomes `Modal`. New
  `Portal`, `Overlay`, `Title`, `Description` parts.
- `sheet`: same root changes as dialog; `Side` is no longer on the root.
- `popover`: `RootProps` becomes `Props`; content positioning props as above; `HoverDelay`,
  `Exclusive`, `ShowArrow`, and dismissal flags removed; adds `Header`, `Title`, `Description`.
- `tooltip`: root loses `Class` and `Attributes`, gains `DefaultOpen` and `Open`; content loses
  `HoverDelay`, `HoverOutDelay`, `ShowArrow`, `ID`, and `Position` (use `Side`, `SideOffset`).
- `hovercard`: delays move from content to the root (`Delay`, `CloseDelay`); arrow and ID props removed.
- `tabs`: drop `TabsID` and `IsActive`; set `DefaultValue` (or `Value`) on the root and `Value`
  on triggers and contents.
- `accordion`: root gains `DefaultValue`, `Value`, `Multiple`; items take `Value`.
- `collapsible`: root gains `DefaultOpen`, `Disabled`.
- `checkbox`: `Group`, `GroupParent`, `Icon` removed; gains `DefaultChecked`, `Indeterminate`, `ReadOnly`, `Required`.
- `switch`: gains `DefaultChecked`, `ReadOnly`, `Required`, `Size`.
- `input`, `textarea`: `Readonly` becomes `ReadOnly`; `HasError` removed (pass `aria-invalid`
  through `Attributes` and check the installed styles); input `FileAccept` becomes `Accept`;
  textarea `AutoResize` removed.
- `label`: `Error` removed. `inputotp`: `Name`, `Form`, `HasError` removed; gains `MaxLength`, `Pattern`, `DefaultValue`.
- `progress`: rebuilt from parts (`Track`, `Indicator`, `Label`, `Value`); `Label`, `ShowValue`,
  `Variant`, `Size` props removed.
- `toast`: rebuilt around a `Toaster`; props become `Type` and `Timeout`.
- `calendar`: rebuilt with a new prop set (`DefaultMonth`, `Locale`, `Modifiers`, and others);
  rewrite call sites from the v2 docs.
- `sidebar`: adds `Provider`, `Rail`, and more parts; root `Collapsed` and `KeyboardShortcut` removed.
- `breadcrumb`: `ItemProps.Current` and `SeparatorProps.UseCustom` removed. `table`:
  `RowProps.Selected` removed. `pagination`: `Label` becomes `Text`. `separator`: `Decoration` removed.
- `slider`: gains `DefaultValue`, `Orientation`; `Range` and `Value` parts removed.
- `carousel`: `Indicators` part and `ContentProps.ID` removed; root gains `Align`, `Direction`, `Orientation`.
- Unchanged or additive only: aspectratio, avatar, badge, card, copybutton, icon, skeleton.

## Porting a legacy block

A block from `legacy-blocks.md` is v1 markup. To use one in a v2 app, keep its layout and copy,
then rebuild each component call against v2 using the tables above. For new sections, check
https://shadcn-templ.com/blocks first; it currently covers app chrome (sidebar, login, signup,
dashboard), while marketing, ecommerce, and content sections exist only in the legacy set.

## Verify

Run `go tool templ generate`, `go build ./...`, the project's tests, the Tailwind build, and
`go tool shadcn-templ bundle`. Open each migrated page in a browser and exercise every
overlay, menu, tab, and form control in light and dark mode. Confirm no `@*.Script()` calls or
v1 imports remain with `rg 'templui/templui|\.Script\(\)'`.
