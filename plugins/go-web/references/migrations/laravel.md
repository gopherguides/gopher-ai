# Laravel to Go Migration

Loaded on demand by /go-web:convert-to-go-project when the source project uses Laravel or other PHP frameworks.

**Route Mapping:**

```php
// Laravel
Route::get('/users', [UserController::class, 'index']);
Route::post('/users', [UserController::class, 'store']);
Route::get('/users/{user}', [UserController::class, 'show']);
```

```go
// Echo
e.GET("/users", h.UserIndex)
e.POST("/users", h.UserStore)
e.GET("/users/:id", h.UserShow)
```

**Blade to Templ:**

```blade
@extends('layouts.app')

@section('content')
    <h1>{{ $user->name }}</h1>
    @foreach($posts as $post)
        <article>{{ $post->title }}</article>
    @endforeach
@endsection
```

```templ
package pages

import "myapp/templates/layouts"

templ UserShow(user User, posts []Post) {
    @layouts.Base("User") {
        <h1>{ user.Name }</h1>
        for _, post := range posts {
            <article>{ post.Title }</article>
        }
    }
}
```

**Eloquent to sqlc:**

```php
// Laravel Eloquent
$users = User::where('active', true)->orderBy('name')->get();
```

```sql
-- sqlc query
-- name: ListActiveUsers :many
SELECT * FROM users WHERE active = true ORDER BY name;
```

## Meta/SEO Migration (Laravel)

**From Laravel (controller passes vars):**

```php
// Laravel (before)
return view('page', ['title' => 'My Page']);
```

```go
// Go handler (after) - does NOT pass meta
func (h *Handler) Page(c echo.Context) error {
    return pages.Page().Render(c.Request().Context(), c.Response().Writer)
}
```

```templ
// Go template - owns its meta
templ Page() {
    @layouts.Base(meta.New("My Page", "Description")) {
        // content
    }
}
```
