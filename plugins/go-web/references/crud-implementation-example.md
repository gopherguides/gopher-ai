# Worked Example: Domain-Specific CRUD Implementation (Notes App)

Loaded on demand by /go-web:create-go-project (Step 4) and /go-web:convert-to-go-project when generating domain-specific migrations, queries, handlers, templates, and tests. Replace the `notes`/`Note` entity with the actual domain entity, and `{{PROJECT_NAME}}` with the project module name.

## Generate Domain-Specific Files

For each identified entity, create these files (replace "example" with the actual entity):

## 1. Update Migration (replace `001_initial.sql`)

Instead of the generic "examples" table, create the actual domain table:

**Example for a Notes app (SQLite):**
```sql
-- +goose Up
CREATE TABLE notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    content TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_notes_created_at ON notes(created_at DESC);

-- +goose Down
DROP TABLE IF EXISTS notes;
```

## 2. Update SQL Queries (replace `sqlc/queries/example.sql`)

**Example for Notes (`sqlc/queries/notes.sql`):**
```sql
-- name: GetNote :one
SELECT * FROM notes WHERE id = ? LIMIT 1;

-- name: ListNotes :many
SELECT * FROM notes ORDER BY created_at DESC;

-- name: CreateNote :one
INSERT INTO notes (title, content) VALUES (?, ?) RETURNING *;

-- name: UpdateNote :exec
UPDATE notes SET title = ?, content = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?;

-- name: DeleteNote :exec
DELETE FROM notes WHERE id = ?;

-- name: SearchNotes :many
SELECT * FROM notes WHERE title LIKE ? OR content LIKE ? ORDER BY created_at DESC;
```

## 3. Create Handler (`internal/handler/<entity>.go`)

**Example (`internal/handler/notes.go`):**
```go
package handler

import (
    "net/http"
    "strconv"

    "{{PROJECT_NAME}}/internal/database/sqlc"
    "{{PROJECT_NAME}}/templates/pages/notes"

    "github.com/labstack/echo/v4"
)

func (h *Handler) ListNotes(c echo.Context) error {
    ctx := c.Request().Context()
    notesList, err := h.db.Queries.ListNotes(ctx)
    if err != nil {
        return echo.NewHTTPError(http.StatusInternalServerError, "failed to list notes")
    }
    return notes.List(notesList).Render(ctx, c.Response().Writer)
}

func (h *Handler) ShowNote(c echo.Context) error {
    ctx := c.Request().Context()
    id, err := strconv.ParseInt(c.Param("id"), 10, 64)
    if err != nil {
        return echo.NewHTTPError(http.StatusBadRequest, "invalid note ID")
    }

    note, err := h.db.Queries.GetNote(ctx, id)
    if err != nil {
        return echo.NewHTTPError(http.StatusNotFound, "note not found")
    }
    return notes.Show(note).Render(ctx, c.Response().Writer)
}

func (h *Handler) NewNote(c echo.Context) error {
    return notes.Form(nil).Render(c.Request().Context(), c.Response().Writer)
}

func (h *Handler) CreateNote(c echo.Context) error {
    ctx := c.Request().Context()
    title := c.FormValue("title")
    content := c.FormValue("content")

    if title == "" {
        return echo.NewHTTPError(http.StatusBadRequest, "title is required")
    }

    note, err := h.db.Queries.CreateNote(ctx, sqlc.CreateNoteParams{
        Title:   title,
        Content: &content,
    })
    if err != nil {
        return echo.NewHTTPError(http.StatusInternalServerError, "failed to create note")
    }

    return c.Redirect(http.StatusSeeOther, "/notes/"+strconv.FormatInt(note.ID, 10))
}

func (h *Handler) EditNote(c echo.Context) error {
    ctx := c.Request().Context()
    id, err := strconv.ParseInt(c.Param("id"), 10, 64)
    if err != nil {
        return echo.NewHTTPError(http.StatusBadRequest, "invalid note ID")
    }

    note, err := h.db.Queries.GetNote(ctx, id)
    if err != nil {
        return echo.NewHTTPError(http.StatusNotFound, "note not found")
    }
    return notes.Form(&note).Render(ctx, c.Response().Writer)
}

func (h *Handler) UpdateNote(c echo.Context) error {
    ctx := c.Request().Context()
    id, err := strconv.ParseInt(c.Param("id"), 10, 64)
    if err != nil {
        return echo.NewHTTPError(http.StatusBadRequest, "invalid note ID")
    }

    title := c.FormValue("title")
    content := c.FormValue("content")

    if title == "" {
        return echo.NewHTTPError(http.StatusBadRequest, "title is required")
    }

    err = h.db.Queries.UpdateNote(ctx, sqlc.UpdateNoteParams{
        ID:      id,
        Title:   title,
        Content: &content,
    })
    if err != nil {
        return echo.NewHTTPError(http.StatusInternalServerError, "failed to update note")
    }

    return c.Redirect(http.StatusSeeOther, "/notes/"+strconv.FormatInt(id, 10))
}

func (h *Handler) DeleteNote(c echo.Context) error {
    ctx := c.Request().Context()
    id, err := strconv.ParseInt(c.Param("id"), 10, 64)
    if err != nil {
        return echo.NewHTTPError(http.StatusBadRequest, "invalid note ID")
    }

    err = h.db.Queries.DeleteNote(ctx, id)
    if err != nil {
        return echo.NewHTTPError(http.StatusInternalServerError, "failed to delete note")
    }

    // If HTMX request, return empty content for removal
    if c.Request().Header.Get("HX-Request") == "true" {
        return c.NoContent(http.StatusOK)
    }

    return c.Redirect(http.StatusSeeOther, "/notes")
}
```

## 4. Register Routes (update `internal/handler/handler.go`)

Add routes in `RegisterRoutes`:
```go
// Notes routes
e.GET("/notes", h.ListNotes)
e.GET("/notes/new", h.NewNote)
e.POST("/notes", h.CreateNote)
e.GET("/notes/:id", h.ShowNote)
e.GET("/notes/:id/edit", h.EditNote)
e.PUT("/notes/:id", h.UpdateNote)
e.DELETE("/notes/:id", h.DeleteNote)
```

## 5. Create Templates

**`templates/pages/notes/list.templ`:**
```templ
package notes

import (
    "{{PROJECT_NAME}}/internal/database/sqlc"
    "{{PROJECT_NAME}}/internal/meta"
    "{{PROJECT_NAME}}/templates/layouts"
)

templ List(notes []sqlc.Note) {
    @layouts.Base(meta.New("Notes", "Manage your notes")) {
        <div class="flex justify-between items-center mb-6">
            <h1 class="text-2xl font-bold">Notes</h1>
            <a href="/notes/new" class="px-4 py-2 bg-primary text-primary-foreground rounded hover:bg-primary/90">
                New Note
            </a>
        </div>

        if len(notes) == 0 {
            <p class="text-muted-foreground">No notes yet. Create your first note!</p>
        } else {
            <div class="grid gap-4">
                for _, note := range notes {
                    @NoteCard(note)
                }
            </div>
        }
    }
}

templ NoteCard(note sqlc.Note) {
    <div id={ "note-" + strconv.FormatInt(note.ID, 10) } class="p-4 border border-border rounded-lg hover:border-primary transition-colors">
        <a href={ templ.SafeURL("/notes/" + strconv.FormatInt(note.ID, 10)) }>
            <h2 class="font-semibold">{ note.Title }</h2>
            if note.Content != nil && *note.Content != "" {
                <p class="text-muted-foreground text-sm mt-1 line-clamp-2">{ *note.Content }</p>
            }
        </a>
    </div>
}
```

**`templates/pages/notes/show.templ`:**
```templ
package notes

import (
    "strconv"

    "{{PROJECT_NAME}}/internal/database/sqlc"
    "{{PROJECT_NAME}}/internal/meta"
    "{{PROJECT_NAME}}/templates/layouts"
)

templ Show(note sqlc.Note) {
    @layouts.Base(meta.New(note.Title, "View note details")) {
        <div class="mb-6">
            <a href="/notes" class="text-muted-foreground hover:text-foreground">← Back to notes</a>
        </div>

        <article class="prose max-w-none">
            <h1>{ note.Title }</h1>
            if note.Content != nil {
                <p class="whitespace-pre-wrap">{ *note.Content }</p>
            }
        </article>

        <div class="mt-8 flex gap-4">
            <a href={ templ.SafeURL("/notes/" + strconv.FormatInt(note.ID, 10) + "/edit") }
               class="px-4 py-2 bg-primary text-primary-foreground rounded hover:bg-primary/90">
                Edit
            </a>
            <button hx-delete={ "/notes/" + strconv.FormatInt(note.ID, 10) }
                    hx-confirm="Are you sure you want to delete this note?"
                    hx-target="body"
                    hx-push-url="/notes"
                    class="px-4 py-2 bg-destructive text-destructive-foreground rounded hover:bg-destructive/90">
                Delete
            </button>
        </div>
    }
}
```

**`templates/pages/notes/form.templ`:**
```templ
package notes

import (
    "strconv"

    "{{PROJECT_NAME}}/internal/database/sqlc"
    "{{PROJECT_NAME}}/internal/meta"
    "{{PROJECT_NAME}}/templates/layouts"
)

templ Form(note *sqlc.Note) {
    @layouts.Base(meta.New(formTitle(note), "Create or edit a note")) {
        <div class="mb-6">
            <a href="/notes" class="text-muted-foreground hover:text-foreground">← Back to notes</a>
        </div>

        <h1 class="text-2xl font-bold mb-6">{ formTitle(note) }</h1>

        <form method="POST" action={ formAction(note) } class="space-y-4 max-w-xl">
            if note != nil {
                <input type="hidden" name="_method" value="PUT"/>
            }

            <div>
                <label for="title" class="block text-sm font-medium mb-1">Title</label>
                <input type="text" id="title" name="title"
                       value={ formValue(note) }
                       required
                       class="w-full px-3 py-2 border border-border rounded focus:outline-none focus:ring-2 focus:ring-primary"/>
            </div>

            <div>
                <label for="content" class="block text-sm font-medium mb-1">Content</label>
                <textarea id="content" name="content" rows="10"
                          class="w-full px-3 py-2 border border-border rounded focus:outline-none focus:ring-2 focus:ring-primary">{ formContent(note) }</textarea>
            </div>

            <button type="submit"
                    class="px-4 py-2 bg-primary text-primary-foreground rounded hover:bg-primary/90">
                { submitLabel(note) }
            </button>
        </form>
    }
}

func formTitle(note *sqlc.Note) string {
    if note == nil {
        return "New Note"
    }
    return "Edit Note"
}

func formAction(note *sqlc.Note) templ.SafeURL {
    if note == nil {
        return "/notes"
    }
    return templ.SafeURL("/notes/" + strconv.FormatInt(note.ID, 10))
}

func formValue(note *sqlc.Note) string {
    if note == nil {
        return ""
    }
    return note.Title
}

func formContent(note *sqlc.Note) string {
    if note == nil || note.Content == nil {
        return ""
    }
    return *note.Content
}

func submitLabel(note *sqlc.Note) string {
    if note == nil {
        return "Create Note"
    }
    return "Update Note"
}
```

## Generate Tests

Create tests for each handler:

**`internal/handler/notes_test.go`:**
```go
package handler

import (
    "net/http"
    "net/http/httptest"
    "net/url"
    "strings"
    "testing"

    "{{PROJECT_NAME}}/internal/testutil"

    "github.com/labstack/echo/v4"
)

func TestListNotes(t *testing.T) {
    t.Parallel()

    db := testutil.NewTestDB(t)
    cfg := testutil.NewTestConfig(t)
    h := New(cfg, db)

    e := echo.New()
    req := httptest.NewRequest(http.MethodGet, "/notes", nil)
    rec := httptest.NewRecorder()
    c := e.NewContext(req, rec)

    if err := h.ListNotes(c); err != nil {
        t.Errorf("ListNotes() error = %v", err)
    }

    if rec.Code != http.StatusOK {
        t.Errorf("ListNotes() status = %d, want %d", rec.Code, http.StatusOK)
    }
}

func TestCreateNote(t *testing.T) {
    t.Parallel()

    db := testutil.NewTestDB(t)
    cfg := testutil.NewTestConfig(t)
    h := New(cfg, db)

    e := echo.New()
    form := url.Values{}
    form.Add("title", "Test Note")
    form.Add("content", "Test content")

    req := httptest.NewRequest(http.MethodPost, "/notes", strings.NewReader(form.Encode()))
    req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
    rec := httptest.NewRecorder()
    c := e.NewContext(req, rec)

    if err := h.CreateNote(c); err != nil {
        t.Errorf("CreateNote() error = %v", err)
    }

    if rec.Code != http.StatusSeeOther {
        t.Errorf("CreateNote() status = %d, want %d", rec.Code, http.StatusSeeOther)
    }
}

func TestCreateNote_EmptyTitle(t *testing.T) {
    t.Parallel()

    db := testutil.NewTestDB(t)
    cfg := testutil.NewTestConfig(t)
    h := New(cfg, db)

    e := echo.New()
    form := url.Values{}
    form.Add("title", "")
    form.Add("content", "Test content")

    req := httptest.NewRequest(http.MethodPost, "/notes", strings.NewReader(form.Encode()))
    req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
    rec := httptest.NewRecorder()
    c := e.NewContext(req, rec)

    err := h.CreateNote(c)
    if err == nil {
        t.Error("CreateNote() expected error for empty title, got nil")
    }
}
```
