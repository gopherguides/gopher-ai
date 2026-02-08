---
argument-hint: "<file|function>"
description: "Generate comprehensive Go tests with table-driven patterns"
model: claude-opus-4-6
allowed-tools: ["Bash", "Read", "Write", "Glob", "Grep", "AskUserQuestion"]
---

**If `$ARGUMENTS` is empty or not provided:**

Display usage information and ask for input:

**Usage:** `/test-gen <target>`

**Examples:**

- `/test-gen pkg/auth/login.go` - Generate tests for a file
- `/test-gen HandleAuthentication` - Generate tests for a function
- `/test-gen pkg/utils/` - Generate tests for a package

**Workflow:**

1. Detect your project's testing setup (testify, gomock, etc.)
2. Analyze the target code structure
3. Generate comprehensive test cases (happy path, edge cases, errors)
4. Create test file following Go table-driven test patterns
5. Self-review for coverage gaps

Ask the user: "What file or function would you like me to generate tests for?"

---

**If `$ARGUMENTS` is provided:**

Generate comprehensive Go tests for the specified code. Follows idiomatic Go patterns including
table-driven tests and includes edge cases, boundary conditions, and error scenarios.

## Loop Initialization

Initialize persistent loop to ensure tests are complete and passing:
!`"${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "test-gen" "COMPLETE"`

## Configuration

- **Target**: `$ARGUMENTS` (file path or function name)

## Steps

1. **Detect Testing Environment**

   Identify the project's testing setup:
   - Check for testify: `go list -m all | grep testify`
   - Check for gomock: `go list -m all | grep gomock`
   - Check for mockery: look for mockery.yaml or .mockery.yaml
   - Examine existing `_test.go` files for patterns

   Also detect:
   - Test file naming convention (`*_test.go`)
   - Package organization (same package vs `_test` suffix)
   - Assertion patterns (testify assert/require vs standard)
   - Mocking patterns (gomock, mockery, hand-written)

2. **Analyze Target Code**

   Read the target file/function and extract:
   - Function signatures and parameters
   - Return types and possible values
   - Dependencies and interfaces
   - Error conditions and returns
   - Side effects (mutations, I/O, network)
   - Conditional branches and logic paths

3. **Identify Test Cases**

   Generate tests for:

   **Happy Path**
   - Basic functionality with typical inputs
   - Expected return values
   - Standard use cases

   **Edge Cases**
   - Empty inputs (nil, "", []byte{}, empty slice)
   - Boundary values (0, -1, max int, empty string)
   - Single element vs multiple elements
   - Unicode and special characters

   **Error Scenarios**
   - Invalid input types
   - Out-of-range values
   - Missing required parameters
   - Context cancellation
   - I/O failures

   **Concurrency** (if applicable)
   - Race conditions
   - Deadlock scenarios
   - Parallel execution with t.Parallel()

4. **Generate Test Code**

   Use table-driven test pattern:

   ```go
   func TestFunctionName(t *testing.T) {
       tests := []struct {
           name    string
           input   InputType
           want    OutputType
           wantErr bool
       }{
           {
               name:  "valid input returns expected result",
               input: validInput,
               want:  expectedOutput,
           },
           {
               name:    "empty input returns error",
               input:   emptyInput,
               wantErr: true,
           },
       }

       for _, tt := range tests {
           t.Run(tt.name, func(t *testing.T) {
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

   For testify users:

   ```go
   func TestFunctionName(t *testing.T) {
       tests := []struct {
           name    string
           input   InputType
           want    OutputType
           wantErr bool
       }{
           // test cases
       }

       for _, tt := range tests {
           t.Run(tt.name, func(t *testing.T) {
               got, err := FunctionName(tt.input)
               if tt.wantErr {
                   require.Error(t, err)
                   return
               }
               require.NoError(t, err)
               assert.Equal(t, tt.want, got)
           })
       }
   }
   ```

5. **Add Mocking** (when needed)

   For dependencies:
   - Use interfaces for mockable dependencies
   - Generate mocks with gomock or mockery
   - Stub external services/APIs
   - Mock database calls with sqlmock

6. **Generate Test Data**

   Create:
   - Fixtures for complex structs
   - Factory functions for repeated patterns
   - Realistic sample data (not just "test", "foo", "bar")
   - Data that exercises edge cases

7. **Self-Review**

   Before outputting, check:
   - [ ] Are all exported functions covered?
   - [ ] Are edge cases covered?
   - [ ] Are error paths tested?
   - [ ] Do tests follow Go conventions?
   - [ ] Are assertions meaningful?
   - [ ] Is t.Parallel() used where appropriate?

8. **Output**

   Provide:
   - Complete test file ready to save
   - Explanation of test strategy
   - List of any assumptions made
   - Suggestions for additional tests that require manual setup

## Go-Specific Best Practices

- Use table-driven tests for multiple scenarios
- Call t.Parallel() for independent tests
- Use t.Helper() in test helper functions
- Prefer subtests with t.Run() for organization
- Use testify/require for fatal assertions, assert for non-fatal
- Name test cases descriptively: "empty_input_returns_error"
- Keep test functions focused on one behavior

---

## Structured Output (--json)

If `$ARGUMENTS` contains `--json`, strip the flag from the target argument and after completing all steps, output **only** a JSON object (no markdown, no explanation) matching this schema:

```json
{
  "test_cases": [
    {"name": "string", "input": "any", "expected": "any", "edge_case": true}
  ],
  "coverage_estimate": "string",
  "testing_framework": "string"
}
```

- `test_cases`: Array of generated test case metadata (name, representative input/expected values, whether it's an edge case)
- `coverage_estimate`: Estimated code coverage (e.g., "~85% - covers happy path, edge cases, error scenarios")
- `testing_framework`: Detected framework (e.g., "stdlib", "testify", "gomock+testify")

Still generate and write the test file as normal, but output JSON to stdout instead of the markdown summary.

---

## Completion Criteria

**DO NOT output `<done>COMPLETE</done>` until ALL of these conditions are TRUE:**

1. Test file is generated with comprehensive test cases
2. Test file compiles without errors
3. `go test` runs and ALL tests PASS
4. Coverage includes happy path, edge cases, and error scenarios

**When ALL criteria are met, output exactly:**

```
<done>COMPLETE</done>
```

This signals the loop to exit. If you output this prematurely, the tests may be incomplete or failing.

---

**Safety note:** If you've iterated 15+ times without success, document what's blocking progress and ask the user for guidance.
