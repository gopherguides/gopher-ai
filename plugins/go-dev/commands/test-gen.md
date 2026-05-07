---
argument-hint: "<file|function>"
description: "Generate comprehensive Go tests with table-driven patterns"
allowed-tools: ["Bash", "Read", "Write", "Glob", "Grep", "AskUserQuestion"]
---

**If `$ARGUMENTS` is empty or not provided:**

**Usage:** `/test-gen <target>`

- `/test-gen pkg/auth/login.go` — generate tests for a file
- `/test-gen HandleAuthentication` — generate tests for a function
- `/test-gen pkg/utils/` — generate tests for a package

**Workflow:** detect testing setup (testify/gomock/etc.) → analyze target → generate test cases (happy path, edge cases, errors) → create test file with table-driven patterns → self-review for coverage gaps.

Ask: "What file or function would you like me to generate tests for?"

---

**If `$ARGUMENTS` is provided:**

Generate comprehensive Go tests for the specified code with table-driven patterns and edge cases.

## Loop Initialization

!`if [ ! -x "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" ]; then echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh (or refresh-plugins.sh) and restart Claude Code."; exit 1; else "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "test-gen" "COMPLETE"; fi`

## Configuration

- **Target**: `$ARGUMENTS` (file path or function name)

## Steps

### 1. Detect Testing Environment

- testify: `go list -m all | grep testify`
- gomock: `go list -m all | grep gomock`
- mockery: look for `mockery.yaml` / `.mockery.yaml`
- Existing `_test.go` patterns

Also detect: file naming (`*_test.go`), package organization (same vs `_test` suffix), assertions (testify assert/require vs stdlib), mocking (gomock, mockery, hand-written).

### 2. Analyze Target

Read the target and extract: function signatures + parameters, return types and possible values, dependencies/interfaces, error conditions and returns, side effects (mutations, I/O, network), conditional branches and logic paths.

### 3. Identify Test Cases

| Category | Examples |
|----------|----------|
| **Happy path** | Basic functionality, expected returns, standard use cases |
| **Edge cases** | Empty inputs (`nil`/`""`/`[]byte{}`/empty slice); boundary values (`0`, `-1`, max int, empty string); single vs multiple elements; Unicode/special chars |
| **Error scenarios** | Invalid input types, out-of-range values, missing required parameters, context cancellation, I/O failures |
| **Concurrency** (if applicable) | Race conditions, deadlocks, parallel execution with `t.Parallel()` |

### 4. Generate Test Code

Table-driven (stdlib):

```go
func TestFunctionName(t *testing.T) {
    tests := []struct {
        name    string
        input   InputType
        want    OutputType
        wantErr bool
    }{
        {name: "valid input returns expected result", input: validInput, want: expectedOutput},
        {name: "empty input returns error", input: emptyInput, wantErr: true},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got, err := FunctionName(tt.input)
            if (err != nil) != tt.wantErr {
                t.Errorf("FunctionName() error = %v, wantErr %v", err, tt.wantErr); return
            }
            if !reflect.DeepEqual(got, tt.want) {
                t.Errorf("FunctionName() = %v, want %v", got, tt.want)
            }
        })
    }
}
```

Testify variant:

```go
for _, tt := range tests {
    t.Run(tt.name, func(t *testing.T) {
        got, err := FunctionName(tt.input)
        if tt.wantErr { require.Error(t, err); return }
        require.NoError(t, err)
        assert.Equal(t, tt.want, got)
    })
}
```

### 5. Mocking (when needed)

Use interfaces for mockable dependencies. Generate with gomock or mockery. Stub external services/APIs. Mock database calls with sqlmock.

### 6. Test Data

Fixtures for complex structs; factory functions for repeated patterns; **realistic sample data** (not "test"/"foo"/"bar"); data that exercises edge cases.

### 7. Self-Review

- [ ] All exported functions covered
- [ ] Edge cases covered
- [ ] Error paths tested
- [ ] Tests follow Go conventions
- [ ] Assertions are meaningful
- [ ] `t.Parallel()` used where appropriate

### 8. Output

Provide complete test file ready to save, test-strategy explanation, list of assumptions made, and suggestions for additional tests requiring manual setup.

## Go-Specific Best Practices

- Table-driven tests for multiple scenarios
- `t.Parallel()` for independent tests
- `t.Helper()` in test helpers
- Subtests via `t.Run()` for organization
- testify `require` for fatal assertions, `assert` for non-fatal
- Name cases descriptively: `empty_input_returns_error`
- Keep each test focused on one behavior

## Structured Output (`--json`)

When `$ARGUMENTS` contains `--json`, strip the flag and after completing all steps, output **only** a JSON object — no markdown, no explanation:

```json
{
  "test_cases": [
    {
      "name": "string — test case name (e.g. 'valid_input_returns_expected_result')",
      "input": "any — the input value or description",
      "expected": "any — the expected output value or description",
      "edge_case": "boolean — true if this is an edge case or error scenario"
    }
  ],
  "coverage_estimate": "string — estimated coverage percentage or qualitative assessment",
  "testing_framework": "string — detected framework (e.g. 'stdlib', 'testify', 'gomock')"
}
```

Example:

```json
{
  "test_cases": [
    {"name": "valid_email_returns_true", "input": "user@example.com", "expected": true, "edge_case": false},
    {"name": "empty_string_returns_error", "input": "", "expected": "error: empty email", "edge_case": true}
  ],
  "coverage_estimate": "85% — covers happy path, empty input, and format validation",
  "testing_framework": "testify"
}
```

Still generate and write the test file as normal — JSON goes to stdout instead of the markdown summary.

> **Important:** in `--json` mode, do NOT emit the `<done>COMPLETE</done>` marker. JSON itself signals completion.

## Completion Criteria

DO NOT output `<done>COMPLETE</done>` until ALL of these are TRUE:

1. Test file generated with comprehensive cases
2. Test file compiles without errors
3. `go test` runs and ALL tests PASS
4. Coverage includes happy path, edge cases, and error scenarios

```
<done>COMPLETE</done>
```

**Safety:** if 15+ iterations without success, document blockers and ask.
