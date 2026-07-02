# Conversion Examples

Input/output pairs showing the expected style for each conversion type.
Loaded on demand by `/convert` — read the section matching the requested
conversion.

## Contents

- JSON to TypeScript
- OpenAPI to SDK
- SQL to Prisma
- CSV to JSON
- GraphQL to TypeScript

## JSON to TypeScript

Input:

```json
{
  "id": "123",
  "name": "Alice",
  "email": "alice@example.com",
  "age": 28,
  "roles": ["admin", "user"],
  "settings": {
    "theme": "dark",
    "notifications": true
  }
}
```

Output:

```typescript
interface User {
  id: string;
  name: string;
  email: string;
  age: number;
  roles: string[];
  settings: UserSettings;
}

interface UserSettings {
  theme: string;
  notifications: boolean;
}
```

## OpenAPI to SDK

Input (OpenAPI spec):

```yaml
paths:
  /users:
    get:
      summary: List users
      responses:
        '200':
          content:
            application/json:
              schema:
                type: array
                items:
                  $ref: '#/components/schemas/User'
```

Output (TypeScript client):

```typescript
export class UsersApi {
  constructor(private client: HttpClient) {}

  async listUsers(): Promise<User[]> {
    return this.client.get<User[]>('/users');
  }

  async getUser(id: string): Promise<User> {
    return this.client.get<User>(`/users/${id}`);
  }

  async createUser(data: CreateUserRequest): Promise<User> {
    return this.client.post<User>('/users', data);
  }
}
```

## SQL to Prisma

Input:

```sql
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email VARCHAR(255) UNIQUE NOT NULL,
  name VARCHAR(100),
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE posts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title VARCHAR(255) NOT NULL,
  content TEXT,
  user_id UUID REFERENCES users(id),
  published BOOLEAN DEFAULT false
);
```

Output:

```prisma
model User {
  id        String   @id @default(cuid())
  email     String   @unique
  name      String?
  createdAt DateTime @default(now())
  posts     Post[]
}

model Post {
  id        String   @id @default(cuid())
  title     String
  content   String?
  published Boolean  @default(false)
  user      User     @relation(fields: [userId], references: [id])
  userId    String
}
```

## CSV to JSON

Input:

```csv
name,email,age
Alice,alice@example.com,28
Bob,bob@example.com,35
```

Output:

```json
[
  { "name": "Alice", "email": "alice@example.com", "age": 28 },
  { "name": "Bob", "email": "bob@example.com", "age": 35 }
]
```

## GraphQL to TypeScript

Input:

```graphql
type User {
  id: ID!
  name: String!
  email: String!
  posts: [Post!]!
}

type Post {
  id: ID!
  title: String!
  author: User!
}

type Query {
  users: [User!]!
  user(id: ID!): User
}
```

Output:

```typescript
interface User {
  id: string;
  name: string;
  email: string;
  posts: Post[];
}

interface Post {
  id: string;
  title: string;
  author: User;
}

interface Query {
  users: User[];
  user: (args: { id: string }) => User | null;
}
```
