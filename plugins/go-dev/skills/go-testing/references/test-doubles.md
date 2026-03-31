# Test Doubles

## Types of Test Doubles

| Type | Purpose | State Tracking | When to Use |
|------|---------|---------------|-------------|
| **Stub** | Returns canned responses | No | Testing code that depends on a value from a collaborator |
| **Fake** | Working implementation with shortcuts | No | Testing against a simplified version of a real dependency (in-memory DB, local filesystem) |
| **Mock** | Verifies interactions (methods called, arguments passed) | Yes | Testing that code calls a dependency correctly (sends email, publishes event) |
| **Spy** | Records calls for later inspection | Yes | Testing call patterns without prescribing behavior upfront |

**Default choice: Stub.** Use mocks only when the interaction itself is the behavior under test (e.g., verifying an email was sent). Over-mocking leads to brittle tests coupled to implementation.

## Interface-Based Test Doubles

Define narrow interfaces at the consumer side. A stub implements only the methods the consumer needs:

```go
type UserStore interface {
	GetUser(ctx context.Context, id string) (*User, error)
	SaveUser(ctx context.Context, user *User) error
}
```

### Stub

```go
type stubUserStore struct {
	users map[string]*User
	err   error
}

func (s *stubUserStore) GetUser(_ context.Context, id string) (*User, error) {
	if s.err != nil {
		return nil, s.err
	}
	u, ok := s.users[id]
	if !ok {
		return nil, ErrNotFound
	}
	return u, nil
}

func (s *stubUserStore) SaveUser(_ context.Context, user *User) error {
	if s.err != nil {
		return s.err
	}
	s.users[user.ID] = user
	return nil
}
```

Using the stub in a test:

```go
func TestGetUserProfile(t *testing.T) {
	store := &stubUserStore{
		users: map[string]*User{
			"u1": {ID: "u1", Name: "Alice", Email: "alice@example.com"},
		},
	}
	svc := NewProfileService(store)

	profile, err := svc.GetProfile(context.Background(), "u1")

	require.NoError(t, err)
	assert.Equal(t, "Alice", profile.Name)
}
```

### Fake

A fake provides a working implementation suitable for tests but not production. In-memory stores are the most common fakes:

```go
type fakeUserStore struct {
	mu    sync.Mutex
	users map[string]*User
}

func newFakeUserStore() *fakeUserStore {
	return &fakeUserStore{users: make(map[string]*User)}
}

func (f *fakeUserStore) GetUser(_ context.Context, id string) (*User, error) {
	f.mu.Lock()
	defer f.mu.Unlock()

	u, ok := f.users[id]
	if !ok {
		return nil, ErrNotFound
	}
	return u, nil
}

func (f *fakeUserStore) SaveUser(_ context.Context, user *User) error {
	f.mu.Lock()
	defer f.mu.Unlock()

	f.users[user.ID] = user
	return nil
}
```

### Spy

A spy wraps real behavior while recording calls:

```go
type spyNotifier struct {
	calls []NotifyCall
}

type NotifyCall struct {
	UserID  string
	Message string
}

func (s *spyNotifier) Notify(_ context.Context, userID, message string) error {
	s.calls = append(s.calls, NotifyCall{UserID: userID, Message: message})
	return nil
}
```

Using the spy:

```go
func TestOrderPlacement(t *testing.T) {
	notifier := &spyNotifier{}
	svc := NewOrderService(newFakeUserStore(), notifier)

	err := svc.PlaceOrder(context.Background(), "u1", "item-42")

	require.NoError(t, err)
	require.Len(t, notifier.calls, 1)
	assert.Equal(t, "u1", notifier.calls[0].UserID)
	assert.Contains(t, notifier.calls[0].Message, "item-42")
}
```

## Testify Mock Patterns

For complex interaction verification, use `testify/mock`:

```go
type MockEmailSender struct {
	mock.Mock
}

func (m *MockEmailSender) Send(ctx context.Context, to, subject, body string) error {
	args := m.Called(ctx, to, subject, body)
	return args.Error(0)
}
```

```go
func TestSendWelcomeEmail(t *testing.T) {
	sender := new(MockEmailSender)
	sender.On("Send",
		mock.Anything,
		"alice@example.com",
		"Welcome!",
		mock.AnythingOfType("string"),
	).Return(nil)

	svc := NewOnboardingService(sender)
	err := svc.WelcomeUser(context.Background(), &User{
		Email: "alice@example.com",
		Name:  "Alice",
	})

	require.NoError(t, err)
	sender.AssertExpectations(t)
}
```

Prefer hand-written stubs over testify mocks for simple cases. Use `testify/mock` when:
- The interface has many methods and you only care about a few
- You need to verify specific argument values
- You need to return different values on successive calls

## httptest for HTTP Testing

### Testing HTTP Handlers

`httptest.NewRecorder` creates a `ResponseRecorder` for testing handlers without starting a server:

```go
func TestHealthHandler(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rec := httptest.NewRecorder()

	HealthHandler(rec, req)

	assert.Equal(t, http.StatusOK, rec.Code)
	assert.JSONEq(t, `{"status":"ok"}`, rec.Body.String())
}
```

### Testing HTTP Clients

`httptest.NewServer` starts a real HTTP server on localhost for testing client code:

```go
func TestAPIClient(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		assert.Equal(t, "/api/users/u1", r.URL.Path)
		assert.Equal(t, "Bearer test-token", r.Header.Get("Authorization"))

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(User{ID: "u1", Name: "Alice"})
	}))
	t.Cleanup(srv.Close)

	client := NewAPIClient(srv.URL, "test-token")
	user, err := client.GetUser(context.Background(), "u1")

	require.NoError(t, err)
	assert.Equal(t, "Alice", user.Name)
}
```

### Testing TLS Clients

```go
func TestTLSClient(t *testing.T) {
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	t.Cleanup(srv.Close)

	client := srv.Client()
	resp, err := client.Get(srv.URL + "/secure")

	require.NoError(t, err)
	defer resp.Body.Close()
	assert.Equal(t, http.StatusOK, resp.StatusCode)
}
```

## sqlmock for Database Testing

`go-sqlmock` intercepts database calls and verifies queries without a running database:

```go
func TestCreateUser(t *testing.T) {
	db, mock, err := sqlmock.New()
	require.NoError(t, err)
	t.Cleanup(func() { db.Close() })

	mock.ExpectExec(`INSERT INTO users`).
		WithArgs("alice", "alice@example.com").
		WillReturnResult(sqlmock.NewResult(1, 1))

	repo := NewUserRepository(db)
	err = repo.Create(context.Background(), &User{
		Name:  "alice",
		Email: "alice@example.com",
	})

	require.NoError(t, err)
	require.NoError(t, mock.ExpectationsWereMet())
}
```

```go
func TestListUsers(t *testing.T) {
	db, mock, err := sqlmock.New()
	require.NoError(t, err)
	t.Cleanup(func() { db.Close() })

	rows := sqlmock.NewRows([]string{"id", "name", "email"}).
		AddRow(1, "alice", "alice@example.com").
		AddRow(2, "bob", "bob@example.com")

	mock.ExpectQuery(`SELECT (.+) FROM users`).
		WillReturnRows(rows)

	repo := NewUserRepository(db)
	users, err := repo.List(context.Background())

	require.NoError(t, err)
	require.Len(t, users, 2)
	assert.Equal(t, "alice", users[0].Name)
	assert.Equal(t, "bob", users[1].Name)
	require.NoError(t, mock.ExpectationsWereMet())
}
```

Prefer real database tests (using testcontainers or a test database) for integration testing. Use sqlmock for unit tests that need to verify SQL interactions without database infrastructure.

## Decision Table: Real vs Test Double

| Situation | Recommendation |
|-----------|---------------|
| Dependency is fast, deterministic, and has no side effects | Use the real thing |
| Dependency requires infrastructure (database, message queue) | Fake for unit tests, real for integration tests |
| Testing error paths that are hard to trigger with real dependency | Stub with error responses |
| Verifying that a side effect occurred (email sent, event published) | Spy or mock |
| Dependency is slow or flaky | Stub or fake |
| Third-party API you don't control | Stub behind your own interface |
| Dependency has complex state machine behavior | Fake with simplified but correct behavior |

## Interface Design for Testability

Define interfaces at the consumer, not the producer. Keep interfaces small:

```go
type OrderPlacer struct {
	inventory InventoryChecker
	payments  PaymentProcessor
	notifier  OrderNotifier
}

type InventoryChecker interface {
	CheckStock(ctx context.Context, itemID string, qty int) (bool, error)
}

type PaymentProcessor interface {
	Charge(ctx context.Context, userID string, amount Money) (TransactionID, error)
}

type OrderNotifier interface {
	NotifyOrderPlaced(ctx context.Context, order *Order) error
}
```

Each interface has a single method or a small cohesive set of methods. This makes stubs trivial to write and keeps test setup minimal.

## Anti-Patterns to Avoid

**Mocking everything** -- If every dependency is mocked, the test verifies that your mocks work, not that your code works. Use real dependencies where practical.

**Mocking what you don't own** -- Do not mock `http.Client`, `sql.DB`, or other standard library types directly. Wrap them in your own interface and mock that.

**Asserting on internal calls** -- A mock that verifies `store.GetUser` was called exactly once with specific arguments creates a test coupled to implementation. If you refactor the code to batch queries, the test breaks even though behavior is preserved.

**Shared mutable test state** -- Global variables or package-level mocks shared between tests cause ordering dependencies and flaky tests. Each test should create its own doubles.
