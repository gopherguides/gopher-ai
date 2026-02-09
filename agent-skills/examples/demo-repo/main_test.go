package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestGetUser(t *testing.T) {
	svc := NewUserService("test-db")

	// Only tests the happy path — missing error cases, edge cases
	name, err := svc.GetUser("admin")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if name != "Administrator" {
		t.Errorf("got %q, want %q", name, "Administrator")
	}
}

func TestGetUser_NotFound(t *testing.T) {
	svc := NewUserService("test-db")

	name, err := svc.GetUser("unknown")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if name != "user_unknown" {
		t.Errorf("got %q, want %q", name, "user_unknown")
	}
}

// Missing tests:
// - TestSaveUser
// - TestDeleteTempFiles
// - TestFormatID
// - TestHandleHealth with different methods
// - Edge cases: empty ID, special characters

func TestHandleHealth(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	w := httptest.NewRecorder()

	handleHealth(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("got status %d, want %d", w.Code, http.StatusOK)
	}
	// Missing: check response body
}
