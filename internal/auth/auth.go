package auth

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"path/filepath"
	"sync"
	"time"

	"github.com/yingshu0218/myshell/internal/store"
	"golang.org/x/crypto/bcrypt"
)

var (
	ErrNotInitialized = errors.New("account is not initialized")
	ErrAlreadyExists  = errors.New("account already exists")
	ErrInvalidLogin   = errors.New("invalid username or password")
	ErrRateLimited    = errors.New("too many login attempts")
)

type Account struct {
	Username          string    `json:"username"`
	PasswordHash      string    `json:"passwordHash"`
	SessionGeneration uint64    `json:"sessionGeneration"`
	CreatedAt         time.Time `json:"createdAt"`
	UpdatedAt         time.Time `json:"updatedAt"`
}

type Session struct {
	ID         string
	CSRF       string
	Generation uint64
	CreatedAt  time.Time
	LastSeen   time.Time
	ExpiresAt  time.Time
}

type attempt struct {
	Failures int
	ResetAt  time.Time
	LockedTo time.Time
}

type Manager struct {
	mu          sync.Mutex
	path        string
	idle        time.Duration
	absolute    time.Duration
	account     *Account
	sessions    map[string]*Session
	attempts    map[string]attempt
	now         func() time.Time
	bcryptCost  int
	maxFailures int
}

func New(dataDir string, idle, absolute time.Duration) (*Manager, error) {
	manager := &Manager{
		path: filepath.Join(dataDir, "account.json"), idle: idle, absolute: absolute,
		sessions: make(map[string]*Session), attempts: make(map[string]attempt),
		now: time.Now, bcryptCost: bcrypt.DefaultCost, maxFailures: 5,
	}
	var account Account
	if err := store.ReadJSON(manager.path, &account); err == nil {
		manager.account = &account
	} else {
		exists, statErr := store.Exists(manager.path)
		if statErr != nil {
			return nil, statErr
		}
		if exists {
			return nil, err
		}
	}
	return manager, nil
}

func (m *Manager) Initialized() bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.account != nil
}

func (m *Manager) Username() (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.account == nil {
		return "", ErrNotInitialized
	}
	return m.account.Username, nil
}

func (m *Manager) Initialize(username, password string) error {
	if len(username) < 3 || len(username) > 64 {
		return errors.New("username must contain 3 to 64 characters")
	}
	if len(password) < 6 || len(password) > 256 {
		return errors.New("password must contain 6 to 256 characters")
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(password), m.bcryptCost)
	if err != nil {
		return err
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.account != nil {
		return ErrAlreadyExists
	}
	now := m.now().UTC()
	account := &Account{
		Username: username, PasswordHash: string(hash), SessionGeneration: 1,
		CreatedAt: now, UpdatedAt: now,
	}
	if err := store.WriteJSON(m.path, account, 0o600); err != nil {
		return err
	}
	m.account = account
	return nil
}

func (m *Manager) Login(username, password, remote string) (*Session, error) {
	m.mu.Lock()
	now := m.now()
	if current := m.attempts[remote]; current.LockedTo.After(now) {
		m.mu.Unlock()
		return nil, ErrRateLimited
	}
	var account *Account
	if m.account != nil {
		copy := *m.account
		account = &copy
	}
	m.mu.Unlock()
	if account == nil {
		return nil, ErrNotInitialized
	}
	validName := subtle.ConstantTimeCompare([]byte(username), []byte(account.Username)) == 1
	validPassword := bcrypt.CompareHashAndPassword([]byte(account.PasswordHash), []byte(password)) == nil
	if !validName || !validPassword {
		m.recordFailure(remote, now)
		return nil, ErrInvalidLogin
	}
	id, err := randomToken(32)
	if err != nil {
		return nil, err
	}
	csrf, err := randomToken(24)
	if err != nil {
		return nil, err
	}
	session := &Session{
		ID: id, CSRF: csrf, Generation: account.SessionGeneration,
		CreatedAt: now, LastSeen: now, ExpiresAt: now.Add(m.absolute),
	}
	m.mu.Lock()
	delete(m.attempts, remote)
	if len(m.sessions) >= 32 {
		var oldestID string
		var oldest time.Time
		for existingID, existing := range m.sessions {
			if now.After(existing.ExpiresAt) || now.Sub(existing.LastSeen) > m.idle {
				delete(m.sessions, existingID)
				continue
			}
			if oldest.IsZero() || existing.CreatedAt.Before(oldest) {
				oldestID, oldest = existingID, existing.CreatedAt
			}
		}
		if len(m.sessions) >= 32 && oldestID != "" {
			delete(m.sessions, oldestID)
		}
	}
	m.sessions[id] = session
	m.mu.Unlock()
	copy := *session
	return &copy, nil
}

func (m *Manager) Validate(id string) (*Session, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	session, ok := m.sessions[id]
	if !ok || m.account == nil {
		return nil, false
	}
	now := m.now()
	if now.After(session.ExpiresAt) || now.Sub(session.LastSeen) > m.idle ||
		session.Generation != m.account.SessionGeneration {
		delete(m.sessions, id)
		return nil, false
	}
	session.LastSeen = now
	copy := *session
	return &copy, true
}

func (m *Manager) Logout(id string) {
	m.mu.Lock()
	delete(m.sessions, id)
	m.mu.Unlock()
}

func (m *Manager) ResetPassword(password string) error {
	if len(password) < 6 || len(password) > 256 {
		return errors.New("password must contain 6 to 256 characters")
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(password), m.bcryptCost)
	if err != nil {
		return err
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.account == nil {
		return ErrNotInitialized
	}
	m.account.PasswordHash = string(hash)
	m.account.SessionGeneration++
	m.account.UpdatedAt = m.now().UTC()
	if err := store.WriteJSON(m.path, m.account, 0o600); err != nil {
		return fmt.Errorf("write account: %w", err)
	}
	clear(m.sessions)
	return nil
}

func (m *Manager) recordFailure(remote string, now time.Time) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if len(m.attempts) >= 1024 {
		for key, value := range m.attempts {
			if now.After(value.ResetAt) && now.After(value.LockedTo) {
				delete(m.attempts, key)
			}
		}
		if len(m.attempts) >= 1024 {
			for key := range m.attempts {
				delete(m.attempts, key)
				break
			}
		}
	}
	current := m.attempts[remote]
	if now.After(current.ResetAt) {
		current = attempt{ResetAt: now.Add(10 * time.Minute)}
	}
	current.Failures++
	if current.Failures >= m.maxFailures {
		current.LockedTo = now.Add(5 * time.Minute)
	}
	m.attempts[remote] = current
}

func randomToken(size int) (string, error) {
	data := make([]byte, size)
	if _, err := rand.Read(data); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(data), nil
}
