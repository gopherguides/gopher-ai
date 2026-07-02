---
argument-hint: "<from> <to> [file]"
description: "Convert between formats, languages, and data structures"
allowed-tools: ["Bash(cat:*)", "Bash(npx:*)", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion"]
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

Match the `<from> <to>` pair against the Supported Conversions table above. If
the pair is unsupported, say so and list the supported pairs.

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

Read the section for the requested conversion type in
`${CLAUDE_PLUGIN_ROOT}/references/conversion-examples.md` and match its
input/output style: idiomatic target-language types, nested structures
resolved into named types, comments preserved where possible.

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
