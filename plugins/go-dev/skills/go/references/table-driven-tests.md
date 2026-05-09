# Table-Driven Tests

## Basic Table-Driven Structure

The table-driven pattern uses a slice of test case structs iterated with `t.Run`. Each struct defines inputs, expected outputs, and a descriptive name.

```go
func TestAdd(t *testing.T) {
	tests := []struct {
		name string
		a    int
		b    int
		want int
	}{
		{
			name: "positive numbers",
			a:    2,
			b:    3,
			want: 5,
		},
		{
			name: "negative numbers",
			a:    -1,
			b:    -2,
			want: -3,
		},
		{
			name: "zero values",
			a:    0,
			b:    0,
			want: 0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := Add(tt.a, tt.b)
			if got != tt.want {
				t.Errorf("Add(%d, %d) = %d, want %d", tt.a, tt.b, got, tt.want)
			}
		})
	}
}
```

## Subtests with t.Run

Subtests provide scoped test execution, independent failure reporting, and the ability to run a single case with `-run`:

```bash
go test -run TestAdd/positive_numbers -v
```

Subtests also enable shared setup at the parent level with per-case variation inside `t.Run`.

## Parallel Subtests

When test cases are independent, use `t.Parallel()` in both the parent and each subtest. Capture the loop variable to avoid closure issues in Go versions before 1.22:

```go
func TestParse(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		input   string
		want    int
		wantErr bool
	}{
		{
			name:  "valid integer",
			input: "42",
			want:  42,
		},
		{
			name:    "invalid input",
			input:   "abc",
			wantErr: true,
		},
		{
			name:  "negative number",
			input: "-7",
			want:  -7,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			got, err := Parse(tt.input)
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

In Go 1.22+ with `GOEXPERIMENT=loopvar` (default in Go 1.23+), the `tt := tt` line is unnecessary because loop variables are scoped per iteration.

## Testing Errors

When a test case expects an error, include a `wantErr` field or a more specific `wantErrIs` field for sentinel error checking:

```go
func TestWithdraw(t *testing.T) {
	tests := []struct {
		name      string
		balance   float64
		amount    float64
		want      float64
		wantErrIs error
	}{
		{
			name:    "successful withdrawal",
			balance: 100.0,
			amount:  30.0,
			want:    70.0,
		},
		{
			name:      "insufficient funds",
			balance:   10.0,
			amount:    50.0,
			wantErrIs: ErrInsufficientFunds,
		},
		{
			name:      "negative amount",
			balance:   100.0,
			amount:    -10.0,
			wantErrIs: ErrNegativeAmount,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			account := NewAccount(tt.balance)
			got, err := account.Withdraw(tt.amount)

			if tt.wantErrIs != nil {
				require.ErrorIs(t, err, tt.wantErrIs)
				return
			}
			require.NoError(t, err)
			assert.InDelta(t, tt.want, got, 0.001)
		})
	}
}
```

## Test Helper Functions

Any function that calls `t.Fatal`, `t.Error`, or similar methods on behalf of a test should call `t.Helper()` first. This ensures that when the test fails, the reported line number points to the caller, not the helper:

```go
func assertJSON(t *testing.T, got, want any) {
	t.Helper()

	gotBytes, err := json.Marshal(got)
	if err != nil {
		t.Fatalf("marshaling got: %v", err)
	}

	wantBytes, err := json.Marshal(want)
	if err != nil {
		t.Fatalf("marshaling want: %v", err)
	}

	if !bytes.Equal(gotBytes, wantBytes) {
		t.Errorf("JSON mismatch:\ngot:  %s\nwant: %s", gotBytes, wantBytes)
	}
}
```

Helper functions that create resources should return a cleanup function or use `t.Cleanup`:

```go
func newTestServer(t *testing.T, handler http.Handler) *httptest.Server {
	t.Helper()

	srv := httptest.NewServer(handler)
	t.Cleanup(srv.Close)

	return srv
}
```

## t.Cleanup Patterns

`t.Cleanup` registers a function that runs after the test (and all its subtests) complete. Unlike `defer`, cleanup functions run even if a test calls `t.FailNow()` or `t.Fatal()`. Cleanup functions run in LIFO order (last registered, first executed):

```go
func TestDatabaseOperations(t *testing.T) {
	db := setupTestDB(t)

	t.Cleanup(func() {
		db.Exec("DROP TABLE test_users")
		db.Close()
	})

	t.Run("insert", func(t *testing.T) {
		_, err := db.Exec("INSERT INTO test_users (name) VALUES (?)", "alice")
		require.NoError(t, err)
	})

	t.Run("query", func(t *testing.T) {
		var name string
		err := db.QueryRow("SELECT name FROM test_users LIMIT 1").Scan(&name)
		require.NoError(t, err)
		assert.Equal(t, "alice", name)
	})
}
```

## Golden File Testing

Golden files store expected output on disk. Tests compare actual output against the golden file and offer a flag to update it:

```go
var update = flag.Bool("update", false, "update golden files")

func TestRender(t *testing.T) {
	tests := []struct {
		name  string
		input string
	}{
		{name: "simple", input: "Hello, World"},
		{name: "with_markdown", input: "# Title\n\nParagraph"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := Render(tt.input)

			golden := filepath.Join("testdata", tt.name+".golden")
			if *update {
				os.MkdirAll("testdata", 0o755)
				os.WriteFile(golden, []byte(got), 0o644)
			}

			want, err := os.ReadFile(golden)
			require.NoError(t, err)
			assert.Equal(t, string(want), got)
		})
	}
}
```

Update golden files with:

```bash
go test -run TestRender -update
```

## Setup and Teardown with TestMain

`TestMain` controls test lifecycle for an entire package. Use it for expensive one-time setup like starting a database container:

```go
var testDB *sql.DB

func TestMain(m *testing.M) {
	var cleanup func()
	testDB, cleanup = startTestDatabase()

	code := m.Run()

	cleanup()
	os.Exit(code)
}
```

Prefer `t.Cleanup` for per-test setup. Reserve `TestMain` for package-level resources shared across all tests.

## Fuzzing (Go 1.18+)

Fuzz tests discover edge cases by generating random inputs. The fuzz function receives a `*testing.F` and adds seed corpus entries with `f.Add`:

```go
func FuzzParseAmount(f *testing.F) {
	f.Add("100.00")
	f.Add("-50.25")
	f.Add("0")
	f.Add("")
	f.Add("not a number")
	f.Add("99999999999999999999")

	f.Fuzz(func(t *testing.T, input string) {
		amount, err := ParseAmount(input)
		if err != nil {
			return
		}

		roundTrip := amount.String()
		reparsed, err := ParseAmount(roundTrip)
		if err != nil {
			t.Fatalf("round-trip failed: ParseAmount(%q) returned %v, String() = %q, reparse error: %v",
				input, amount, roundTrip, err)
		}

		if !amount.Equal(reparsed) {
			t.Errorf("round-trip mismatch: %v != %v", amount, reparsed)
		}
	})
}
```

Run fuzz tests with:

```bash
go test -fuzz=FuzzParseAmount -fuzztime=30s
```

Fuzz tests found in `testdata/fuzz/<FuncName>/` are automatically used as regression tests in normal `go test` runs.

## t.Setenv for Environment Variables

`t.Setenv` sets an environment variable for the duration of the test and restores the original value on cleanup. It cannot be used with `t.Parallel()`:

```go
func TestConfigFromEnv(t *testing.T) {
	t.Setenv("APP_PORT", "9090")
	t.Setenv("APP_DEBUG", "true")

	cfg := LoadConfig()

	assert.Equal(t, 9090, cfg.Port)
	assert.True(t, cfg.Debug)
}
```

## testing/fstest.MapFS

`MapFS` provides an in-memory filesystem for testing code that accepts `fs.FS`:

```go
func TestFindGoFiles(t *testing.T) {
	fsys := fstest.MapFS{
		"main.go":           {Data: []byte("package main")},
		"util/helper.go":    {Data: []byte("package util")},
		"util/helper_test.go": {Data: []byte("package util")},
		"README.md":         {Data: []byte("# Project")},
	}

	got := FindGoFiles(fsys)

	want := []string{"main.go", "util/helper.go", "util/helper_test.go"}
	assert.ElementsMatch(t, want, got)
}
```
