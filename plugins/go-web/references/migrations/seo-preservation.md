# SEO and Metadata Preservation

Loaded on demand by /go-web:convert-to-go-project before converting templates. Framework-specific meta migration examples live in the per-framework guides in this directory.

**Key principle:** In Go, handlers do NOT construct meta. Templates own their meta. The supporting files (`internal/ctxkeys/keys.go`, `internal/meta/meta.go`, `internal/meta/context.go`, `templates/layouts/meta.templ`) are created from the shared template library during scaffolding.

## Migrating Site-Wide Config

Move hardcoded site names to environment variables:

```bash
# .envrc
export SITE_NAME="My App"
export SITE_URL="https://example.com"
```

Middleware injects into context, templates access via `meta.SiteNameFromCtx(ctx)`.

## Preserve Existing OG Images

When converting, identify and preserve existing OG images:

1. Check `public/`, `static/`, `assets/` for og-*.png files
2. Copy to Go project's `static/images/` directory
3. Reference in templates: `meta.New("Title", "Desc").WithOGImage("/static/images/og.png")`

Before converting templates, scan the existing project for all SEO-related content.

## Metadata Detection Commands

```bash
# Search for meta tags in templates
rg -i '<meta\s+' --glob '*.html' --glob '*.jsx' --glob '*.vue' --glob '*.blade.php' --glob '*.erb' --glob '*.twig'

# Search for OG tags
rg 'og:' --glob '*.html' --glob '*.jsx' --glob '*.vue'

# Search for JSON-LD structured data
rg 'application/ld\+json' --glob '*.html' --glob '*.jsx'

# Search for existing SEO config files
fd -e json -e yaml -e yml | xargs rg -l 'seo\|meta\|og:'
```

## Metadata to Extract

Scan for these elements:

- **Title tags**: Extract page titles from templates/views
- **Meta descriptions**: Find description meta tags
- **OG tags**: og:title, og:description, og:image, og:type, og:url
- **Twitter cards**: twitter:card, twitter:title, twitter:description, twitter:image
- **Canonical URLs**: link rel="canonical"
- **Structured data**: JSON-LD, microdata
- **Robots directives**: noindex, nofollow
- **Sitemap references**: sitemap.xml locations
- **Favicon/icons**: Various icon formats and sizes

## Framework-Specific SEO Extraction

**Next.js:**

```javascript
// Look for these patterns
export const metadata = { ... }
generateMetadata()
<Head>...</Head>
```

**Django:**

```python
# Look for these patterns
{% block meta %}
{{ page.seo_title }}
```

**Laravel:**

```php
// Look for SEO packages
@section('meta')
SEO::setTitle()
```

## Migration Pattern

When converting each page/template:

1. **Extract metadata from source**:
   - Parse the original template for all meta-related content
   - Document any dynamic metadata (e.g., `{{ page.title }}`)
   - Note any SEO-related environment variables

2. **Map to Go/Templ structure**:
   - Static metadata → Direct in template via `meta.New()`
   - Dynamic metadata → Handler passes data, template constructs meta
   - Site-wide metadata → Context via middleware

3. **Preserve OG images**:
   - Find existing OG image files
   - Copy to `static/images/`
   - Update paths in templates

4. **Report preserved metadata**:

After conversion, display a summary:

```text
## SEO Metadata Preserved

| Page | Title | Description | OG Image |
|------|-------|-------------|----------|
| /    | Home  | Welcome...  | /static/images/og-home.png |
| /about | About Us | Learn... | /static/images/og-default.png |
```
