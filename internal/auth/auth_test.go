package auth

import (
	"errors"
	"testing"
	"time"
)

func newTestManager(t *testing.T) *Manager {
	t.Helper()
	manager, err := New(t.TempDir(), 5*time.Minute, time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	manager.bcryptCost = bcryptMinCost
	return manager
}

const bcryptMinCost = 4

func TestInitializeLoginAndReset(t *testing.T) {
	manager := newTestManager(t)
	if err := manager.Initialize("111111", "111111"); err != nil {
		t.Fatal(err)
	}
	session, err := manager.Login("111111", "111111", "127.0.0.1")
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := manager.Validate(session.ID); !ok {
		t.Fatal("new session should be valid")
	}
	if err := manager.ResetPassword("222222"); err != nil {
		t.Fatal(err)
	}
	if _, ok := manager.Validate(session.ID); ok {
		t.Fatal("password reset must invalidate existing sessions")
	}
	if _, err := manager.Login("111111", "111111", "127.0.0.1"); !errors.Is(err, ErrInvalidLogin) {
		t.Fatalf("old password error = %v", err)
	}
	if _, err := manager.Login("111111", "222222", "127.0.0.1"); err != nil {
		t.Fatalf("new password rejected: %v", err)
	}
}

func TestLoginRateLimit(t *testing.T) {
	manager := newTestManager(t)
	if err := manager.Initialize("111111", "111111"); err != nil {
		t.Fatal(err)
	}
	for range manager.maxFailures {
		_, _ = manager.Login("111111", "wrong-password", "198.51.100.1")
	}
	if _, err := manager.Login("111111", "111111", "198.51.100.1"); !errors.Is(err, ErrRateLimited) {
		t.Fatalf("login error = %v, want rate limited", err)
	}
}

func TestSessionExpiry(t *testing.T) {
	manager := newTestManager(t)
	now := time.Now()
	manager.now = func() time.Time { return now }
	if err := manager.Initialize("111111", "111111"); err != nil {
		t.Fatal(err)
	}
	session, err := manager.Login("111111", "111111", "local")
	if err != nil {
		t.Fatal(err)
	}
	now = now.Add(6 * time.Minute)
	if _, ok := manager.Validate(session.ID); ok {
		t.Fatal("idle session should expire")
	}
}
