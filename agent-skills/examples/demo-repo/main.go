// Package main demonstrates common Go code quality issues.
package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"sync"
)

// Issue: Global mutable state
var userCache = map[string]string{}
var cacheMu sync.Mutex

// Issue: Unnecessary init function
func init() {
	userCache["admin"] = "Administrator"
}

// UserService is a user service.
// Issue: In a 'user' package, this name would stutter (user.UserService)
type UserService struct {
	db string
}

// NewUserService creates a new UserService.
func NewUserService(db string) *UserService {
	return &UserService{db: db}
}

// GetUser retrieves a user by ID.
func (s *UserService) GetUser(id string) (string, error) {
	cacheMu.Lock()
	if name, ok := userCache[id]; ok {
		cacheMu.Unlock()
		return name, nil
	}
	cacheMu.Unlock()

	// Issue: Simulated DB call without context.Context
	return fmt.Sprintf("user_%s", id), nil
}

// SaveUser saves a user.
func (s *UserService) SaveUser(id, name string) error {
	cacheMu.Lock()
	userCache[id] = name
	cacheMu.Unlock()

	// Issue: Error not wrapped with context
	return nil
}

// DeleteTempFiles cleans up temporary files.
func DeleteTempFiles(pattern string) {
	files, _ := os.ReadDir("/tmp") // Issue: Error ignored
	for _, f := range files {
		// Issue: Error from Remove not checked
		os.Remove("/tmp/" + f.Name())
	}
}

// handleHealth is an HTTP health check handler.
func handleHealth(w http.ResponseWriter, r *http.Request) {
	// Issue: Error from Write not checked
	w.Write([]byte("ok"))
}

// Issue: Missing godoc on exported function
func FormatID(prefix string, id int) string {
	return fmt.Sprintf("%s-%d", prefix, id)
}

func main() {
	svc := NewUserService("postgres://localhost/demo")

	http.HandleFunc("/health", handleHealth)
	http.HandleFunc("/user", func(w http.ResponseWriter, r *http.Request) {
		id := r.URL.Query().Get("id")
		name, err := svc.GetUser(id)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		fmt.Fprintf(w, "Hello, %s", name)
	})

	// Issue: log.Fatal in main is fine, but no graceful shutdown
	log.Fatal(http.ListenAndServe(":8080", nil))
}
