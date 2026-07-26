package vault

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/yingshu0218/myshell/internal/store"
)

var ErrConflict = errors.New("vault version conflict")

type Credential struct {
	Username string `json:"username"`
	Password string `json:"password,omitempty"`
}

type Connection struct {
	ID           string     `json:"id"`
	Name         string     `json:"name"`
	Group        string     `json:"group,omitempty"`
	Host         string     `json:"host"`
	Port         int        `json:"port"`
	Credential   Credential `json:"credential"`
	HostKey      string     `json:"hostKey,omitempty"`
	HealthPeriod int        `json:"healthPeriod,omitempty"`
	Deleted      bool       `json:"deleted,omitempty"`
	UpdatedAt    time.Time  `json:"updatedAt"`
}

type Preferences struct {
	Theme       string `json:"theme"`
	CodePreview bool   `json:"codePreview"`
}

type BackupConfig struct {
	Enabled  bool   `json:"enabled"`
	Provider string `json:"provider,omitempty"`
	APIBase  string `json:"apiBase,omitempty"`
	Owner    string `json:"owner,omitempty"`
	Repo     string `json:"repo,omitempty"`
	Branch   string `json:"branch,omitempty"`
	Schedule string `json:"schedule,omitempty"`
}

type Data struct {
	Version     uint64       `json:"version"`
	Connections []Connection `json:"connections"`
	Preferences Preferences  `json:"preferences"`
	Backup      BackupConfig `json:"backup"`
	UpdatedAt   time.Time    `json:"updatedAt"`
}

type Envelope struct {
	Format     string `json:"format"`
	Version    uint64 `json:"version"`
	Nonce      string `json:"nonce"`
	Ciphertext string `json:"ciphertext"`
	UpdatedAt  string `json:"updatedAt"`
}

type Preview struct {
	Version         uint64    `json:"version"`
	UpdatedAt       time.Time `json:"updatedAt"`
	ConnectionCount int       `json:"connectionCount"`
	ConnectionNames []string  `json:"connectionNames"`
	Theme           string    `json:"theme"`
}

type Vault struct {
	mu       sync.RWMutex
	path     string
	history  string
	key      []byte
	data     Data
	maxFiles int
}

func Open(dataDir, keyFile string) (*Vault, error) {
	key, err := readKey(keyFile)
	if err != nil {
		return nil, err
	}
	v := &Vault{
		path: filepath.Join(dataDir, "vault.json"), history: filepath.Join(dataDir, "history"),
		key: key, maxFiles: 5,
	}
	if err := v.load(); err != nil {
		return nil, err
	}
	return v, nil
}

func (v *Vault) Snapshot() Data {
	v.mu.RLock()
	defer v.mu.RUnlock()
	return clone(v.data)
}

func (v *Vault) Envelope() (Envelope, error) {
	v.mu.RLock()
	defer v.mu.RUnlock()
	return v.encrypt(v.data)
}

func (v *Vault) Replace(expected uint64, next Data) (Data, error) {
	v.mu.Lock()
	defer v.mu.Unlock()
	if expected != v.data.Version {
		return clone(v.data), ErrConflict
	}
	if err := validate(&next); err != nil {
		return Data{}, err
	}
	next.Version = v.data.Version + 1
	next.UpdatedAt = time.Now().UTC()
	for index := range next.Connections {
		if next.Connections[index].UpdatedAt.IsZero() {
			next.Connections[index].UpdatedAt = next.UpdatedAt
		}
	}
	if err := v.persist(next); err != nil {
		return Data{}, err
	}
	v.data = clone(next)
	return clone(v.data), nil
}

func (v *Vault) Find(id string) (Connection, bool) {
	v.mu.RLock()
	defer v.mu.RUnlock()
	for _, connection := range v.data.Connections {
		if connection.ID == id && !connection.Deleted {
			return connection, true
		}
	}
	return Connection{}, false
}

func (v *Vault) RestoreEnvelope(expected uint64, envelope Envelope) (Data, error) {
	v.mu.Lock()
	defer v.mu.Unlock()
	if expected != v.data.Version {
		return clone(v.data), ErrConflict
	}
	var next Data
	if err := v.decrypt(envelope, &next); err != nil {
		return Data{}, err
	}
	if err := validate(&next); err != nil {
		return Data{}, err
	}
	next.Version = v.data.Version + 1
	next.UpdatedAt = time.Now().UTC()
	if err := v.persist(next); err != nil {
		return Data{}, err
	}
	v.data = clone(next)
	return clone(next), nil
}

func (v *Vault) InspectEnvelope(envelope Envelope) (Preview, error) {
	v.mu.RLock()
	defer v.mu.RUnlock()
	var data Data
	if err := v.decrypt(envelope, &data); err != nil {
		return Preview{}, err
	}
	if err := validate(&data); err != nil {
		return Preview{}, err
	}
	preview := Preview{
		Version: data.Version, UpdatedAt: data.UpdatedAt, Theme: data.Preferences.Theme,
	}
	for _, connection := range data.Connections {
		if connection.Deleted {
			continue
		}
		preview.ConnectionCount++
		if len(preview.ConnectionNames) < 10 {
			preview.ConnectionNames = append(preview.ConnectionNames, connection.Name)
		}
	}
	return preview, nil
}

func (v *Vault) load() error {
	var envelope Envelope
	err := store.ReadJSON(v.path, &envelope)
	if err != nil {
		exists, statErr := store.Exists(v.path)
		if statErr != nil {
			return statErr
		}
		if !exists {
			v.data = Data{
				Version: 1, Connections: []Connection{},
				Preferences: Preferences{Theme: "midnight", CodePreview: true},
				UpdatedAt:   time.Now().UTC(),
			}
			return v.persist(v.data)
		}
		return err
	}
	if err := v.decrypt(envelope, &v.data); err != nil {
		return err
	}
	if v.data.Connections == nil {
		v.data.Connections = []Connection{}
	}
	return nil
}

func (v *Vault) persist(data Data) error {
	envelope, err := v.encrypt(data)
	if err != nil {
		return err
	}
	if old, err := os.ReadFile(v.path); err == nil {
		if err := os.MkdirAll(v.history, 0o700); err != nil {
			return err
		}
		name := filepath.Join(v.history, fmt.Sprintf("vault-%020d.json", v.data.Version))
		if err := os.WriteFile(name, old, 0o600); err != nil {
			return err
		}
		if err := trimHistory(v.history, v.maxFiles); err != nil {
			return err
		}
	}
	return store.WriteJSON(v.path, envelope, 0o600)
}

func (v *Vault) encrypt(data Data) (Envelope, error) {
	plaintext, err := json.Marshal(data)
	if err != nil {
		return Envelope{}, err
	}
	block, err := aes.NewCipher(v.key)
	if err != nil {
		return Envelope{}, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return Envelope{}, err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return Envelope{}, err
	}
	aad := []byte(fmt.Sprintf("myshell:v1:%d", data.Version))
	ciphertext := gcm.Seal(nil, nonce, plaintext, aad)
	return Envelope{
		Format: "myshell-aes-256-gcm-v1", Version: data.Version,
		Nonce:      base64.RawStdEncoding.EncodeToString(nonce),
		Ciphertext: base64.RawStdEncoding.EncodeToString(ciphertext),
		UpdatedAt:  data.UpdatedAt.Format(time.RFC3339Nano),
	}, nil
}

func (v *Vault) decrypt(envelope Envelope, target any) error {
	if envelope.Format != "myshell-aes-256-gcm-v1" {
		return errors.New("unsupported vault format")
	}
	nonce, err := base64.RawStdEncoding.DecodeString(envelope.Nonce)
	if err != nil {
		return errors.New("invalid vault nonce")
	}
	ciphertext, err := base64.RawStdEncoding.DecodeString(envelope.Ciphertext)
	if err != nil {
		return errors.New("invalid vault ciphertext")
	}
	block, err := aes.NewCipher(v.key)
	if err != nil {
		return err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return err
	}
	aad := []byte(fmt.Sprintf("myshell:v1:%d", envelope.Version))
	plaintext, err := gcm.Open(nil, nonce, ciphertext, aad)
	if err != nil {
		return errors.New("vault authentication failed")
	}
	if err := json.Unmarshal(plaintext, target); err != nil {
		return errors.New("invalid vault payload")
	}
	return nil
}

func validate(data *Data) error {
	if len(data.Connections) > 500 {
		return errors.New("vault cannot contain more than 500 connections")
	}
	ids := make(map[string]struct{}, len(data.Connections))
	for index := range data.Connections {
		connection := &data.Connections[index]
		connection.ID = strings.TrimSpace(connection.ID)
		connection.Name = strings.TrimSpace(connection.Name)
		connection.Host = strings.TrimSpace(connection.Host)
		if connection.ID == "" || connection.Name == "" || connection.Host == "" {
			return errors.New("connection id, name and host are required")
		}
		if strings.HasPrefix(connection.Host, "-") || strings.ContainsAny(connection.Host, " \t\r\n@/") {
			return errors.New("connection host contains unsupported characters")
		}
		if strings.HasPrefix(connection.Credential.Username, "-") ||
			strings.ContainsAny(connection.Credential.Username, " \t\r\n@") {
			return errors.New("SSH username contains unsupported characters")
		}
		if strings.ContainsAny(connection.Credential.Password, "\x00\r\n") {
			return errors.New("SSH password cannot contain line breaks")
		}
		if _, exists := ids[connection.ID]; exists {
			return errors.New("connection ids must be unique")
		}
		ids[connection.ID] = struct{}{}
		if connection.Port == 0 {
			connection.Port = 22
		}
		if connection.Port < 1 || connection.Port > 65535 {
			return errors.New("connection port is invalid")
		}
		if connection.HealthPeriod != 0 && !slices.Contains([]int{5, 15, 30, 60}, connection.HealthPeriod) {
			return errors.New("health period must be 0, 5, 15, 30 or 60")
		}
	}
	if data.Preferences.Theme == "" {
		data.Preferences.Theme = "midnight"
	}
	if data.Backup.Enabled {
		if data.Backup.Provider != "github" && data.Backup.Provider != "gitea" {
			return errors.New("backup provider must be github or gitea")
		}
		if data.Backup.Owner == "" || data.Backup.Repo == "" {
			return errors.New("backup owner and repository are required")
		}
		if data.Backup.Branch == "" {
			data.Backup.Branch = "main"
		}
		if data.Backup.Schedule != "" && data.Backup.Schedule != "daily" && data.Backup.Schedule != "weekly" {
			return errors.New("backup schedule must be daily or weekly")
		}
	}
	return nil
}

func readKey(path string) ([]byte, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read vault key secret: %w", err)
	}
	value := strings.TrimSpace(string(raw))
	key, decodeErr := base64.StdEncoding.DecodeString(value)
	if decodeErr != nil {
		key, decodeErr = base64.RawStdEncoding.DecodeString(value)
	}
	if decodeErr != nil || len(key) != 32 {
		key = []byte(value)
	}
	if len(key) != 32 {
		return nil, errors.New("vault key must contain exactly 32 random bytes or base64-encoded 32 bytes")
	}
	return key, nil
}

func trimHistory(directory string, max int) error {
	entries, err := os.ReadDir(directory)
	if err != nil {
		return err
	}
	if len(entries) <= max {
		return nil
	}
	slices.SortFunc(entries, func(a, b os.DirEntry) int {
		return strings.Compare(a.Name(), b.Name())
	})
	for _, entry := range entries[:len(entries)-max] {
		if err := os.Remove(filepath.Join(directory, entry.Name())); err != nil {
			return err
		}
	}
	return nil
}

func clone(data Data) Data {
	copy := data
	copy.Connections = append([]Connection{}, data.Connections...)
	return copy
}
