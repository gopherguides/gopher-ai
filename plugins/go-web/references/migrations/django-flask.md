# Django/Flask to Go Migration

Loaded on demand by /go-web:convert-to-go-project when the source project uses Django, Flask, or FastAPI.

**URL Patterns:**

```python
# Django
urlpatterns = [
    path('users/', views.user_list, name='user_list'),
    path('users/<int:pk>/', views.user_detail, name='user_detail'),
]

# Flask
@app.route('/users')
def user_list():
    ...
```

```go
// Echo
e.GET("/users", h.UserList)
e.GET("/users/:id", h.UserDetail)
```

**Django Template to Templ:**

```django
{% extends "base.html" %}
{% block content %}
  <h1>{{ user.name }}</h1>
  {% for post in posts %}
    <article>{{ post.title }}</article>
  {% endfor %}
{% endblock %}
```

```templ
package pages

import "myapp/templates/layouts"

templ UserDetail(user User, posts []Post) {
    @layouts.Base("User") {
        <h1>{ user.Name }</h1>
        for _, post := range posts {
            <article>{ post.Title }</article>
        }
    }
}
```

**Django Model to goose Migration:**

```python
# Django model
class User(models.Model):
    email = models.EmailField(unique=True)
    name = models.CharField(max_length=100)
    created_at = models.DateTimeField(auto_now_add=True)
```

```sql
-- goose migration
-- +goose Up
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- +goose Down
DROP TABLE IF EXISTS users;
```

## Meta/SEO Migration (Django)

**From Django (template blocks):**

```django
{% raw %}
{% block meta %}
<title>{{ page_title }}</title>
<meta name="description" content="{{ page_description }}">
{% endblock %}
{% endraw %}
```

```templ
// Go template (after)
templ MyPage() {
    @layouts.Base(meta.New("Page Title", "Page description")) {
        // content
    }
}
```
