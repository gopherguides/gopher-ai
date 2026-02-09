---
name: go-test-coverage
description: |
  WHEN: User wants to improve test coverage, find untested code, generate test stubs, or asks
  "what tests am I missing?" or "how do I improve coverage?" for a Go project.
  WHEN NOT: When running existing tests, debugging test failures, or benchmarking.
license: MIT
---

# Go Test Coverage

Test coverage gap analysis and recommendations for Go projects. Identifies missing or insufficient test coverage and generates actionable recommendations.

## What It Does

1. **Coverage Analysis** — Runs `go test -cover` and parses results
2. **Gap Identification** — Finds untested exported functions, error paths, and edge cases
3. **Recommendation Engine** — Suggests specific test cases using table-driven patterns
4. **Stub Generation** — Creates ready-to-use test file stubs

## Steps

### 1. Measure Current Coverage

```bash
# Generate coverage profile
go test -coverprofile=coverage.out ./...

# View per-function coverage
go tool cover -func=coverage.out

# Generate HTML report (optional)
go tool cover -html=coverage.out -o coverage.html
```

### 2. Identify Gaps

Parse coverage output to find:

- **Untested exported functions** — Any `func` with 0% coverage
- **Partially covered functions** — Functions with branches not hit
- **Untested error paths** — `if err != nil` blocks never executed
- **Missing edge cases** — Boundary conditions not exercised

```bash
# Find functions with 0% coverage
go tool cover -func=coverage.out | grep "0.0%"

# Find exported functions without test files
for f in $(find . -name "*.go" ! -name "*_test.go" -path "*/pkg/*" -o -name "*.go" ! -name "*_test.go" -path "*/internal/*"); do
  dir=$(dirname "$f")
  base=$(basename "$f" .go)
  if [ ! -f "${dir}/${base}_test.go" ]; then
    echo "Missing test file: ${dir}/${base}_test.go"
  fi
done
```

### 3. Generate Recommendations

For each untested function, recommend:

- **Table-driven tests** for functions with multiple input/output combinations
- **Error path tests** for functions that return errors
- **Edge case tests** for boundary values (nil, empty, zero, max)
- **Integration tests** for functions with external dependencies

### 4. Generate Test Stubs

Create test files with the table-driven pattern:

```go
func TestFunctionName(t *testing.T) {
	tests := []struct {
		name    string
		input   InputType
		want    OutputType
		wantErr bool
	}{
		{
			name:  "valid input",
			input: validInput,
			want:  expectedOutput,
		},
		{
			name:    "empty input returns error",
			input:   emptyInput,
			wantErr: true,
		},
		{
			name:    "nil input returns error",
			input:   nil,
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			got, err := FunctionName(tt.input)
			if (err != nil) != tt.wantErr {
				t.Errorf("FunctionName() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("FunctionName() = %v, want %v", got, tt.want)
			}
		})
	}
}
```

## Output Format

```markdown
## Test Coverage Report

**Project:** {name}
**Current Coverage:** {percent}%
**Target Coverage:** 80%

### Coverage by Package

| Package | Coverage | Status |
|---------|----------|--------|
| pkg/auth | 85% | ✅ |
| pkg/api | 45% | ⚠️ |
| internal/db | 20% | 🔴 |

### Untested Exported Functions

| Function | File | Priority |
|----------|------|----------|
| `HandleLogin` | pkg/auth/handler.go | High |
| `ValidateToken` | pkg/auth/token.go | High |
| `FormatResponse` | pkg/api/response.go | Medium |

### Recommended Test Cases

#### `HandleLogin` (pkg/auth/handler.go)
1. Valid credentials → successful login
2. Invalid password → 401 error
3. Missing username → validation error
4. Expired account → forbidden error
5. Rate limited → 429 error

### Generated Stubs

Test stubs have been written to:
- `pkg/auth/handler_test.go`
- `pkg/api/response_test.go`
```

## References

- Existing gopher-ai command: `plugins/go-dev/commands/test-gen.md`
- Go best practices skill: `plugins/go-dev/skills/go-best-practices/`
- [Go Testing](https://go.dev/doc/tutorial/add-a-test)

---

*Powered by [Gopher Guides](https://gopherguides.com) training materials.*
