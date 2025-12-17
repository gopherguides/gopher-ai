---
argument-hint: "<from> <to> [file]"
description: "Convert between formats, languages, and data structures"
model: claude-opus-4-5-20251101
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion"]
---

**If `$ARGUMENTS` is empty or not provided:**

Show available conversion types and usage.

**Usage:** `/convert <from> <to> [file]`

**Examples:**

- `/convert json typescript` - JSON to TypeScript types
- `/convert openapi sdk` - OpenAPI spec to client SDK
- `/convert sql prisma` - SQL schema to Prisma models
- `/convert csv json data.csv` - CSV file to JSON
- `/convert yaml json config.yaml` - YAML to JSON

**Supported Conversions:**

| From | To | Description |
| ---- | -- | ----------- |
| json | typescript | JSON to TS interfaces |
| openapi | sdk | OpenAPI to client code |
| sql | prisma/typeorm | SQL to ORM models |
| protobuf | typescript | Proto to TS types |
| csv | json | CSV to JSON array |
| yaml | json | YAML to JSON |
| graphql | typescript | GraphQL to TS types |

What would you like to convert?

---

**If `$ARGUMENTS` is provided:**

Parse arguments and perform the conversion.

## Configuration

Parse arguments:

- **From**: Source format (first argument)
- **To**: Target format (second argument)
- **File**: Optional input file (third argument)

## Steps

### 1. Detect Conversion Type

Map input to conversion handler:

| Pattern | Handler |
| ------- | ------- |
| json → typescript | `jsonToTypeScript` |
| openapi → sdk | `openapiToSdk` |
| sql → prisma | `sqlToPrisma` |
| csv → json | `csvToJson` |
| yaml → json | `yamlToJson` |
| graphql → typescript | `graphqlToTypeScript` |
| protobuf → typescript | `protobufToTypeScript` |

### 2. Read Input

If file provided:

```bash
cat <file>
```

If no file, look for common sources:

```bash
# OpenAPI
cat openapi.yaml swagger.json api.yaml 2>/dev/null | head -1

# SQL
cat schema.sql migrations/*.sql 2>/dev/null | head -1

# GraphQL
cat schema.graphql *.graphql 2>/dev/null | head -1
```

Or ask user to paste input.

### 3. Perform Conversion

#### JSON to TypeScript

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

#### OpenAPI to SDK

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

#### SQL to Prisma

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

#### CSV to JSON

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

#### GraphQL to TypeScript

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

### 4. Output Result

Write to file or display:

```markdown
## Conversion Complete

**From**: JSON
**To**: TypeScript

### Output

[Generated code]

### File Created

`types/user.ts` (45 lines)
```

### 5. Validate Output

For code output, check syntax:

```bash
# TypeScript
npx tsc --noEmit output.ts 2>/dev/null

# Prisma
npx prisma validate 2>/dev/null
```

## Conversion Options

| Option | Description |
| ------ | ----------- |
| `--strict` | Generate stricter types |
| `--optional` | Mark all fields optional |
| `--readonly` | Use readonly properties |
| `--output <file>` | Write to specific file |

## Output Structure

```markdown
## Conversion: JSON → TypeScript

### Input

[Source content summary]

### Output

[Generated code]

### Files Created

| File | Lines |
| ---- | ----- |
| types/user.ts | 45 |

### Usage

[How to use the generated code]
```

## Notes

- Preserves comments where possible
- Handles nested structures
- Generates clean, idiomatic code
- Validates output syntax
- Supports stdin for piping
