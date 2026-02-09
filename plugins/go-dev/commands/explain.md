---
argument-hint: "<file|function|package>"
description: "Deep-dive explanation of Go code with diagrams"
model: claude-opus-4-6
allowed-tools: ["Read", "Glob", "Grep", "AskUserQuestion"]
---

**If `$ARGUMENTS` is empty or not provided:**

Display usage information and ask for input:

**Usage:** `/explain <target>`

**Examples:**

- `/explain pkg/auth/login.go` - Explain a file
- `/explain HandleAuthentication` - Explain a function
- `/explain pkg/services/` - Explain a package

**Workflow:**

1. Analyze the specified Go code target
2. Extract key concepts, interfaces, dependencies
3. Generate documentation-style explanation
4. Create Mermaid diagrams for complex flows
5. Identify idiomatic Go patterns used

Ask the user: "What file, function, or package would you like me to explain?"

---

**If `$ARGUMENTS` is provided:**

Generate a comprehensive explanation of the specified Go code. Creates documentation-style output
with Mermaid diagrams for complex flows.

## Configuration

- **Target**: `$ARGUMENTS` (file path, function name, or package)

## Context Management

Before loading file content:

1. **Check size first**: Use Glob to find the file, note its size
2. **For files >300 lines**:
   - Read first 50 lines (package, imports, type declarations)
   - Use Grep to find specific function/type definitions
   - Read only the relevant sections
   - Do NOT load entire file into context
3. **For packages with >20 files**:
   - List files first with Glob
   - Read doc.go if present
   - Sample 2-3 representative files maximum

## Steps

1. **Identify Target Scope**

   - If file path: Check file size before reading
   - If function name: Search for the function across packages
   - If package: Analyze the package structure

2. **Analyze Go Code Structure**

   For **files**, extract:
   - Package and purpose
   - Exported vs unexported identifiers
   - Types and interfaces defined
   - Key functions and methods
   - Dependencies (imports)

   For **functions**, extract:
   - Signature (receiver, params, returns)
   - Error handling patterns
   - Goroutine usage
   - Channel operations
   - Context handling

   For **packages**, extract:
   - Package purpose and API surface
   - Public interfaces
   - Internal organization
   - Dependencies on other packages

3. **Generate Explanation**

   Structure the output as:

   ```markdown
   # [Target Name]

   ## Overview
   [2-3 sentence summary of what this code does and why it exists]

   ## Key Concepts
   - **[Interface/Type]**: Purpose and usage
   - **[Pattern]**: How it's applied

   ## How It Works
   [Step-by-step explanation of the main flow]

   ## Go Patterns Used
   - **Error Handling**: How errors are wrapped/returned
   - **Interfaces**: Accept interfaces, return structs
   - **Concurrency**: Goroutines, channels, sync primitives

   ## Dependencies
   - `package-a`: Used for X
   - `package-b`: Provides Y

   ## Diagram
   [Mermaid diagram - see step 4]

   ## Important Details
   - [Edge cases handled]
   - [Performance considerations]
   - [Thread safety notes]
   ```

4. **Create Mermaid Diagrams**

   Choose the appropriate diagram type:

   **Flowchart** - For control flow, algorithms:

   ```mermaid
   flowchart TD
       A[Request] --> B{Validate}
       B -->|Valid| C[Process]
       B -->|Invalid| D[Return Error]
       C --> E{Success?}
       E -->|Yes| F[Return Result]
       E -->|No| G[Wrap Error]
   ```

   **Sequence Diagram** - For interactions between components:

   ```mermaid
   sequenceDiagram
       participant H as Handler
       participant S as Service
       participant R as Repository
       H->>S: ProcessRequest(ctx, req)
       S->>R: FindByID(ctx, id)
       R-->>S: entity, err
       S-->>H: response, err
   ```

   **Class Diagram** - For types and interfaces:

   ```mermaid
   classDiagram
       class Service {
           <<interface>>
           +Create(ctx, input) (Output, error)
           +Get(ctx, id) (Output, error)
       }
       class serviceImpl {
           -repo Repository
           +Create(ctx, input) (Output, error)
       }
       Service <|.. serviceImpl
   ```

5. **Highlight Go Idioms**

   Point out idiomatic patterns:
   - Error wrapping with `fmt.Errorf("%w", err)`
   - Context propagation
   - Defer for cleanup
   - Interface satisfaction
   - Functional options pattern
   - Builder pattern

6. **Add Context**

   - Link to related files/packages
   - Reference tests that demonstrate usage
   - Note any TODO or FIXME comments
   - Mention godoc if present

## Output Guidelines

- Write for someone unfamiliar with this specific code
- Explain the "why" not just the "what"
- Use Go terminology correctly
- Keep diagrams focused (5-10 nodes max)
- Offer to explain any referenced code in more detail

---

## Structured Output (`--json`)

When `$ARGUMENTS` contains `--json`, output **only** valid JSON matching this schema instead of markdown. Do not include any text outside the JSON object.

```json
{
  "summary": "string — 2-3 sentence overview of what the code does and why",
  "components": [
    {
      "name": "string — type, function, or interface name",
      "purpose": "string — what this component does",
      "complexity": "string — 'low', 'medium', or 'high'"
    }
  ],
  "call_graph": "string — Mermaid diagram source showing component interactions",
  "recommendations": ["string — improvement suggestions or things to watch out for"]
}
```

**Example:**

```json
{
  "summary": "Package auth provides JWT-based authentication middleware for HTTP handlers. It validates tokens, extracts claims, and injects user context.",
  "components": [
    {"name": "Middleware", "purpose": "HTTP middleware that validates JWT tokens and sets user context", "complexity": "medium"},
    {"name": "Claims", "purpose": "Custom JWT claims struct with user ID and roles", "complexity": "low"},
    {"name": "TokenService", "purpose": "Interface for token generation and validation", "complexity": "low"}
  ],
  "call_graph": "sequenceDiagram\n    participant H as Handler\n    participant M as Middleware\n    participant T as TokenService\n    M->>T: Validate(token)\n    T-->>M: claims, err\n    M->>H: next(ctx)",
  "recommendations": ["Consider adding token refresh logic", "Add rate limiting to prevent brute-force attempts"]
}
```

Strip the `--json` flag from `$ARGUMENTS` before identifying the target.


## Structured Output (--json)

If `$ARGUMENTS` contains `--json`, strip the flag from the target argument and output **only** a JSON object (no markdown, no explanation) matching this schema:

```json
{
  "summary": "string",
  "components": [{"name": "string", "purpose": "string", "complexity": "string"}],
  "call_graph": "string (mermaid)",
  "recommendations": ["string"]
}
```

- `summary`: 2-3 sentence overview of the code
- `components`: Key types, functions, or interfaces with purpose and complexity level (low/medium/high)
- `call_graph`: Mermaid diagram source as a string
- `recommendations`: Actionable improvement suggestions
